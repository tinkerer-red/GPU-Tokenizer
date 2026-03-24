enum GPU_TOKEN {
	OMIT,
	ISOLATE,
	CONCATENATE,
}

function GPUTokenizer() constructor {
	
	// =============== INTERNALS ===============
	
	surfSource   = -1;
	surfOutput   = -1;
	srcTexW      = 0;  srcTexH = 0;
	outTexW      = 0;  outTexH = 0;
	
	surfCompile  = -1;   // compile buffer uploaded as texture
	surfLookup   = -1;   // output of compile shader, input to tokenizer
	lookupW      = 0;
	lookupH      = 0;
	
	// Compile buffer - all add* calls write directly to this
	bufCompile     = buffer_create(4096, buffer_grow, 1);
	ctxRuleCount   = 0;
	ctxDataBytes   = 0;
	ctxDataOffset  = 0;
	unmatchedMode  = GPU_TOKEN.OMIT;
	outputLength   = 0;
	
	// Reusable pad buffer for source upload
	bufPad     = -1;
	bufPadSize = 0;
	
	// Fixed layout offsets
	static OFFSET_CLASSES     = 0;
	static OFFSET_MERGE       = 256;
	static OFFSET_START_MERGE = 65792;
	static OFFSET_CTX_START   = 131328;
	static OFFSET_CTX_INDEX   = 131584;
	
	// Tokenizer shader handles (static - resolved once)
	static uLoc_srcSize       = shader_get_uniform(sh_gpu_tokenizer, "u_srcSize");
	static uLoc_outSize       = shader_get_uniform(sh_gpu_tokenizer, "u_outSize");
	static uLoc_totalBytes    = shader_get_uniform(sh_gpu_tokenizer, "u_totalBytes");
	static uLoc_unmatchedMode = shader_get_uniform(sh_gpu_tokenizer, "u_unmatchedMode");
	static uLoc_lookupWidth   = shader_get_uniform(sh_gpu_tokenizer, "u_lookupWidth");
	static uLoc_lookupHeight  = shader_get_uniform(sh_gpu_tokenizer, "u_lookupHeight");
	static uLoc_ctxDataOffset = shader_get_uniform(sh_gpu_tokenizer, "u_ctxDataOffset");
	static sIdx_lookup        = shader_get_sampler_index(sh_gpu_tokenizer, "u_texLookup");
	
	// Compile shader handles (static - resolved once)
	static cLoc_compileSize    = shader_get_uniform(sh_gpu_compile, "u_compileSize");
	static cLoc_lookupSize     = shader_get_uniform(sh_gpu_compile, "u_lookupSize");
	static cLoc_compileBytes   = shader_get_uniform(sh_gpu_compile, "u_compileBytes");
	static cLoc_numCtxRules    = shader_get_uniform(sh_gpu_compile, "u_numCtxRules");
	static cLoc_ctxDataOffset  = shader_get_uniform(sh_gpu_compile, "u_ctxDataOffset");
	static cLoc_unmatchedMode  = shader_get_uniform(sh_gpu_compile, "u_unmatchedMode");
	
	
	// =============== PUBLIC API ===============
	
	#region jsDoc
	/// @func    addPattern(_regex)
	/// @desc    Parses a simplified regex pattern and appends its compiled membership data to the internal compile buffer.
	/// @self    GPUTokenizer
	/// @param   {String} regex_value : The regex pattern to compile into tokenizer rule data.
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static addPattern = function(_regex) {
		buffer_write(bufCompile, buffer_u8, 1);  // type = PATTERN
		var _numGroupsPos = buffer_tell(bufCompile);
		buffer_write(bufCompile, buffer_u8, 0);  // placeholder numGroups

		var _numGroups = 0;
		var _len = string_length(_regex);
		var _pos = 1;

		while (_pos <= _len) {
			var _ch = string_char_at(_regex, _pos);

			// Write repeats placeholder
			var _repeatsPos = buffer_tell(bufCompile);
			buffer_write(bufCompile, buffer_u8, 0);

			// Write 256 membership bytes (all 0)
			var _memStart = buffer_tell(bufCompile);
			buffer_fill(bufCompile, _memStart, buffer_u8, 0, 256);
			buffer_seek(bufCompile, buffer_seek_relative, 256);

			if (_ch == "[") {
				// Bracket expression
				_pos++;
				var _neg = false;
				if (_pos <= _len && string_char_at(_regex, _pos) == "^") { _neg = true; _pos++; }
				if (_neg) buffer_fill(bufCompile, _memStart, buffer_u8, 255, 256);

				var _pokeVal = _neg ? 0 : 255;
				while (_pos <= _len) {
					var _bch = string_char_at(_regex, _pos);
					if (_bch == "]") { _pos++; break; }
					if (_bch == "\\" && _pos + 1 <= _len) {
						_pos++;
						pokeShorthand(bufCompile, _memStart, string_char_at(_regex, _pos), _pokeVal);
						_pos++; continue;
					}
					if (_pos + 2 <= _len && string_char_at(_regex, _pos+1) == "-" && string_char_at(_regex, _pos+2) != "]") {
						var _from = ord(_bch);
						var _to = ord(string_char_at(_regex, _pos+2));
						for (var _c = _from; _c <= _to; _c++)
							buffer_poke(bufCompile, _memStart + _c, buffer_u8, _pokeVal);
						_pos += 3; continue;
					}
					buffer_poke(bufCompile, _memStart + ord(_bch), buffer_u8, _pokeVal);
					_pos++;
				}
			} else if (_ch == "\\" && _pos + 1 <= _len) {
				_pos++;
				pokeShorthand(bufCompile, _memStart, string_char_at(_regex, _pos), 255);
				_pos++;
			} else if (_ch == ".") {
				buffer_fill(bufCompile, _memStart, buffer_u8, 255, 256);
				buffer_poke(bufCompile, _memStart + 0x0A, buffer_u8, 0);
				_pos++;
			} else {
				buffer_poke(bufCompile, _memStart + ord(_ch), buffer_u8, 255);
				_pos++;
			}

			// Check for quantifier
			if (_pos <= _len) {
				var _n = string_char_at(_regex, _pos);
				if (_n == "*" || _n == "+") {
					buffer_poke(bufCompile, _repeatsPos, buffer_u8, 1);
					_pos++;
				}
			}
			_numGroups++;
		}

		// Patch numGroups
		buffer_poke(bufCompile, _numGroupsPos, buffer_u8, _numGroups);
		return self;
	};
	
	#region jsDoc
	/// @func    addContextPattern(_open, _close, _escape, [_keepOpen], [_keepClose], [_keepEscape])
	/// @desc    Adds a context rule using opening, closing, and escape sequences, with flags controlling whether each delimiter is preserved in output.
	/// @self    GPUTokenizer
	/// @param   {String} open_value : The opening delimiter sequence.
	/// @param   {String} close_value : The closing delimiter sequence.
	/// @param   {String} escape_value : The escape sequence used inside the context.
	/// @param   {Bool} [keep_open=true] : Whether the opening delimiter should be preserved.
	/// @param   {Bool} [keep_close=true] : Whether the closing delimiter should be preserved.
	/// @param   {Bool} [keep_escape=true] : Whether the escape sequence should be preserved.
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static addContextPattern = function(_open, _close, _escape, _keepOpen = true, _keepClose = true, _keepEscape = true) {
		buffer_write(bufCompile, buffer_u8, 2);  // type = CONTEXT
		buffer_write(bufCompile, buffer_string, _open);
		buffer_write(bufCompile, buffer_string, _close);
		buffer_write(bufCompile, buffer_string, _escape);
		var _flags = (_keepOpen ? 1 : 0) | (_keepClose ? 2 : 0) | (_keepEscape ? 4 : 0);
		buffer_write(bufCompile, buffer_u8, _flags);
		ctxRuleCount++;
		ctxDataBytes += string_byte_length(_open) + 1 + string_byte_length(_close) + 1 + string_byte_length(_escape) + 1;
		return self;
	};
	
	#region jsDoc
	/// @func    addDelimiter(_chars)
	/// @desc    Adds a delimiter rule by compiling the provided character membership set into the internal compile buffer.
	/// @self    GPUTokenizer
	/// @param   {String} chars_value : The character set or shorthand sequence to treat as delimiters.
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static addDelimiter = function(_chars) {
		buffer_write(bufCompile, buffer_u8, 3);  // type = DELIMITER
		var _memStart = buffer_tell(bufCompile);
		buffer_fill(bufCompile, _memStart, buffer_u8, 0, 256);
		buffer_seek(bufCompile, buffer_seek_relative, 256);
		pokeMembership(bufCompile, _memStart, _chars);
		return self;
	};
	
	#region jsDoc
	/// @func    addIgnore(_chars)
	/// @desc    Adds an ignore rule by compiling the provided character membership set into the internal compile buffer.
	/// @self    GPUTokenizer
	/// @param   {String} chars_value : The character set or shorthand sequence to ignore during tokenization.
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static addIgnore = function(_chars) {
		buffer_write(bufCompile, buffer_u8, 4);  // type = IGNORE
		var _memStart = buffer_tell(bufCompile);
		buffer_fill(bufCompile, _memStart, buffer_u8, 0, 256);
		buffer_seek(bufCompile, buffer_seek_relative, 256);
		pokeMembership(bufCompile, _memStart, _chars);
		return self;
	};
	
	#region jsDoc
	/// @func    setUnmatchedRule(_mode)
	/// @desc    Sets how unmatched input should be handled by the tokenizer.
	/// @self    GPUTokenizer
	/// @param   {Enum.GPU_TOKEN} mode_value : The unmatched-token handling mode.
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static setUnmatchedRule = function(_mode) {
		unmatchedMode = _mode;
		return self;
	};
	
	
	// =============== COMPILE ===============
	
	#region jsDoc
	/// @func    compile()
	/// @desc    Finalizes the current compile buffer, uploads it to a compile surface, and builds the lookup surface used during tokenization.
	/// @self    GPUTokenizer
	/// @returns {Struct.GPUTokenizer}
	#endregion
	static compile = function() {
		var _compile_bytes = buffer_tell(bufCompile) + 1;

		ctxDataOffset = OFFSET_CTX_INDEX + ctxRuleCount * 4;

		var _lookup_bytes = ctxDataOffset + ctxDataBytes;
		var _lookup_pixels = ceil(_lookup_bytes / 4);

		lookupW = 1;
		while (lookupW * lookupW < _lookup_pixels) {
			lookupW *= 2;
		}

		lookupH = 1;
		while (lookupH < ceil(_lookup_pixels / lookupW)) {
			lookupH *= 2;
		}

		var _compile_pixels = ceil(_compile_bytes / 4);
		var _compile_width = 1;
		while (_compile_width * _compile_width < _compile_pixels) {
			_compile_width *= 2;
		}

		var _compile_height = 1;
		while (_compile_height < ceil(_compile_pixels / _compile_width)) {
			_compile_height *= 2;
		}

		var _compile_texture_size = _compile_width * _compile_height * 4;
		var _compile_upload_buffer = buffer_create(_compile_texture_size, buffer_fixed, 1);

		buffer_fill(_compile_upload_buffer, 0, buffer_u8, 0, _compile_texture_size);
		buffer_copy(bufCompile, 0, _compile_bytes - 1, _compile_upload_buffer, 0);
		buffer_poke(_compile_upload_buffer, _compile_bytes - 1, buffer_u8, 0);
		
		if (surface_exists(surfCompile)) {
			surface_free(surfCompile);
		}
		surfCompile = surface_create(_compile_width, _compile_height);
		buffer_set_surface(_compile_upload_buffer, surfCompile, 0);
		buffer_delete(_compile_upload_buffer);
		
		if (surface_exists(surfLookup)) {
			surface_free(surfLookup);
		}
		surfLookup = surface_create(lookupW, lookupH);
		
		surface_set_target(surfLookup);
		draw_clear_alpha(c_black, 0);
		gpu_set_blendenable(false);
		gpu_set_tex_filter(false);
		shader_set(sh_gpu_compile);
		
		shader_set_uniform_f(cLoc_compileSize, _compile_width, _compile_height);
		shader_set_uniform_f(cLoc_lookupSize, lookupW, lookupH);
		shader_set_uniform_f(cLoc_compileBytes, _compile_bytes);
		shader_set_uniform_f(cLoc_numCtxRules, ctxRuleCount);
		shader_set_uniform_f(cLoc_ctxDataOffset, ctxDataOffset);
		shader_set_uniform_f(cLoc_unmatchedMode, unmatchedMode);
		
		draw_surface_stretched(surfCompile, 0, 0, lookupW, lookupH);
		
		shader_reset();
		surface_reset_target();
		gpu_set_blendenable(true);
		gpu_set_tex_filter(true);
		
		return self;
	};
	
	
	// =============== TOKENIZE ===============
	
	#region jsDoc
	/// @func    tokenize(_input)
	/// @desc    Tokenizes a source string by uploading it to the source surface and reading back the GPU-produced token buffer.
	/// @self    GPUTokenizer
	/// @param   {String} input_value : The input text to tokenize.
	/// @returns {Buffer}
	#endregion
	static tokenize = function(_input) {
		var _byte_length = string_byte_length(_input);
		if (_byte_length == 0) {
			outputLength = 0;
			var _empty_buffer = buffer_create(1, buffer_fixed, 1);
			buffer_poke(_empty_buffer, 0, buffer_u8, 0);
			return _empty_buffer;
		}

		var _source_pixels = ceil(_byte_length / 4);
		var _source_width = 1;
		while (_source_width * _source_width < _source_pixels) {
			_source_width *= 2;
		}

		var _source_height = 1;
		while (_source_height < ceil(_source_pixels / _source_width)) {
			_source_height *= 2;
		}

		var _output_bytes = _byte_length * 2;
		var _output_pixels = ceil(_output_bytes / 4);
		var _output_width = 1;
		while (_output_width * _output_width < _output_pixels) {
			_output_width *= 2;
		}

		var _output_height = 1;
		while (_output_height < ceil(_output_pixels / _output_width)) {
			_output_height *= 2;
		}

		if (_source_width != srcTexW || _source_height != srcTexH || !surface_exists(surfSource)) {
			if (surface_exists(surfSource)) {
				surface_free(surfSource);
			}
			surfSource = surface_create(_source_width, _source_height);
			srcTexW = _source_width;
			srcTexH = _source_height;
		}

		if (_output_width != outTexW || _output_height != outTexH || !surface_exists(surfOutput)) {
			if (surface_exists(surfOutput)) {
				surface_free(surfOutput);
			}
			surfOutput = surface_create(_output_width, _output_height);
			outTexW = _output_width;
			outTexH = _output_height;
		}

		if (!surface_exists(surfLookup)) {
			compile();
		}

		var _source_texture_size = _source_width * _source_height * 4;
		if (bufPad == -1 || bufPadSize < _source_texture_size) {
			if (bufPad != -1) {
				buffer_delete(bufPad);
			}
			bufPad = buffer_create(_source_texture_size, buffer_fixed, 1);
			bufPadSize = _source_texture_size;
		}

		buffer_fill(bufPad, 0, buffer_u8, 0, _source_texture_size);
		buffer_seek(bufPad, buffer_seek_start, 0);
		buffer_write(bufPad, buffer_text, _input);
		buffer_set_surface(bufPad, surfSource, 0);

		surface_set_target(surfOutput);
		draw_clear_alpha(c_black, 0);
		gpu_set_blendenable(false);
		gpu_set_tex_filter(false);
		shader_set(sh_gpu_tokenizer);

		texture_set_stage(sIdx_lookup, surface_get_texture(surfLookup));
		gpu_set_tex_filter_ext(sIdx_lookup, false);

		shader_set_uniform_f(uLoc_srcSize, _source_width, _source_height);
		shader_set_uniform_f(uLoc_outSize, _output_width, _output_height);
		shader_set_uniform_f(uLoc_totalBytes, _byte_length);
		shader_set_uniform_f(uLoc_unmatchedMode, unmatchedMode);
		shader_set_uniform_f(uLoc_lookupWidth, lookupW);
		shader_set_uniform_f(uLoc_lookupHeight, lookupH);
		shader_set_uniform_f(uLoc_ctxDataOffset, ctxDataOffset);

		draw_surface_stretched(surfSource, 0, 0, _output_width, _output_height);

		shader_reset();
		surface_reset_target();
		gpu_set_blendenable(true);
		gpu_set_tex_filter(true);

		var _output_texture_size = _output_width * _output_height * 4;
		var _output_buffer = buffer_create(_output_texture_size, buffer_fixed, 1);
		buffer_get_surface(_output_buffer, surfOutput, 0);

		outputLength = _output_bytes;
		return _output_buffer;
	};
	
	#region jsDoc
	/// @func    tokenizeBuffer(_buffer, _byteLen)
	/// @desc    Tokenizes a prebuilt byte buffer by uploading it to the source surface and reading back the GPU-produced token buffer.
	/// @self    GPUTokenizer
	/// @param   {Buffer} buffer_value : The source buffer containing input bytes.
	/// @param   {Real} byte_length : The number of bytes from the source buffer to tokenize.
	/// @returns {Buffer}
	#endregion
	static tokenizeBuffer = function(_buffer, _byteLen) {
		var _byte_length = _byteLen;
		if (_byte_length == 0) {
			outputLength = 0;
			var _empty_buffer = buffer_create(1, buffer_fixed, 1);
			buffer_poke(_empty_buffer, 0, buffer_u8, 0);
			return _empty_buffer;
		}

		var _source_pixels = ceil(_byte_length / 4);
		var _source_width = 1;
		while (_source_width * _source_width < _source_pixels) {
			_source_width *= 2;
		}

		var _source_height = 1;
		while (_source_height < ceil(_source_pixels / _source_width)) {
			_source_height *= 2;
		}

		var _output_bytes = _byte_length * 2;
		var _output_pixels = ceil(_output_bytes / 4);
		var _output_width = 1;
		while (_output_width * _output_width < _output_pixels) {
			_output_width *= 2;
		}

		var _output_height = 1;
		while (_output_height < ceil(_output_pixels / _output_width)) {
			_output_height *= 2;
		}

		if (_source_width != srcTexW || _source_height != srcTexH || !surface_exists(surfSource)) {
			if (surface_exists(surfSource)) {
				surface_free(surfSource);
			}
			surfSource = surface_create(_source_width, _source_height);
			srcTexW = _source_width;
			srcTexH = _source_height;
		}

		if (_output_width != outTexW || _output_height != outTexH || !surface_exists(surfOutput)) {
			if (surface_exists(surfOutput)) {
				surface_free(surfOutput);
			}
			surfOutput = surface_create(_output_width, _output_height);
			outTexW = _output_width;
			outTexH = _output_height;
		}

		if (!surface_exists(surfLookup)) {
			compile();
		}

		var _source_texture_size = _source_width * _source_height * 4;
		if (bufPad == -1 || bufPadSize < _source_texture_size) {
			if (bufPad != -1) {
				buffer_delete(bufPad);
			}
			bufPad = buffer_create(_source_texture_size, buffer_fixed, 1);
			bufPadSize = _source_texture_size;
		}

		buffer_copy(_buffer, 0, _byte_length, bufPad, 0);
		if (_byte_length < _source_texture_size) {
			buffer_fill(bufPad, _byte_length, buffer_u8, 0, _source_texture_size - _byte_length);
		}
		buffer_set_surface(bufPad, surfSource, 0);

		surface_set_target(surfOutput);
		draw_clear_alpha(c_black, 0);
		gpu_set_blendenable(false);
		gpu_set_tex_filter(false);
		shader_set(sh_gpu_tokenizer);

		texture_set_stage(sIdx_lookup, surface_get_texture(surfLookup));
		gpu_set_tex_filter_ext(sIdx_lookup, false);

		shader_set_uniform_f(uLoc_srcSize, _source_width, _source_height);
		shader_set_uniform_f(uLoc_outSize, _output_width, _output_height);
		shader_set_uniform_f(uLoc_totalBytes, _byte_length);
		shader_set_uniform_f(uLoc_unmatchedMode, unmatchedMode);
		shader_set_uniform_f(uLoc_lookupWidth, lookupW);
		shader_set_uniform_f(uLoc_lookupHeight, lookupH);
		shader_set_uniform_f(uLoc_ctxDataOffset, ctxDataOffset);

		draw_surface_stretched(surfSource, 0, 0, _output_width, _output_height);

		shader_reset();
		surface_reset_target();
		gpu_set_blendenable(true);
		gpu_set_tex_filter(true);

		var _output_texture_size = _output_width * _output_height * 4;
		var _output_buffer = buffer_create(_output_texture_size, buffer_fixed, 1);
		buffer_get_surface(_output_buffer, surfOutput, 0);

		outputLength = _output_bytes;
		return _output_buffer;
	};
	
	// =============== HELPERS ===============
	
	#region jsDoc
	/// @func    pokeShorthand(_buf, _memStart, _ch, _val)
	/// @desc    Writes membership bytes into a 256-byte membership table for a regex shorthand or escaped character.
	/// @self    GPUTokenizer
	/// @param   {Buffer} buffer_value : The destination buffer containing the membership table.
	/// @param   {Real} membership_start : The starting offset of the membership table within the destination buffer.
	/// @param   {String} char_value : The shorthand or escaped character to expand.
	/// @param   {Real} membership_value : The byte value to write into matching membership slots.
	/// @returns {Undefined}
	#endregion
	static pokeShorthand = function(_buf, _memStart, _ch, _val) {
		switch (_ch) {
			case "d": for (var _c=48;_c<=57;_c++) buffer_poke(_buf,_memStart+_c,buffer_u8,_val); break;
			case "D":
				for (var _c=0;_c<48;_c++) buffer_poke(_buf,_memStart+_c,buffer_u8,_val);
				for (var _c=58;_c<=255;_c++) buffer_poke(_buf,_memStart+_c,buffer_u8,_val); break;
			case "w":
				for (var _c=97;_c<=122;_c++) buffer_poke(_buf,_memStart+_c,buffer_u8,_val);
				for (var _c=65;_c<=90;_c++) buffer_poke(_buf,_memStart+_c,buffer_u8,_val);
				buffer_poke(_buf,_memStart+95,buffer_u8,_val); break;
			case "W":
				for (var _c=0;_c<=255;_c++) {
					if ((_c>=97&&_c<=122)||(_c>=65&&_c<=90)||_c==95) continue;
					buffer_poke(_buf,_memStart+_c,buffer_u8,_val);
				} break;
			case "s":
				buffer_poke(_buf,_memStart+0x20,buffer_u8,_val);
				buffer_poke(_buf,_memStart+0x09,buffer_u8,_val);
				buffer_poke(_buf,_memStart+0x0A,buffer_u8,_val);
				buffer_poke(_buf,_memStart+0x0D,buffer_u8,_val); break;
			case "S":
				for (var _c=0;_c<=255;_c++) {
					if (_c==0x20||_c==0x09||_c==0x0A||_c==0x0D) continue;
					buffer_poke(_buf,_memStart+_c,buffer_u8,_val);
				} break;
			case "n": buffer_poke(_buf,_memStart+0x0A,buffer_u8,_val); break;
			case "r": buffer_poke(_buf,_memStart+0x0D,buffer_u8,_val); break;
			case "t": buffer_poke(_buf,_memStart+0x09,buffer_u8,_val); break;
			default:  buffer_poke(_buf,_memStart+ord(_ch),buffer_u8,_val); break;
		}
	};
	
	#region jsDoc
	/// @func    pokeMembership(_buf, _memStart, _chars)
	/// @desc    Parses a character membership string, expands escape sequences, and writes the resulting membership bytes into the destination buffer.
	/// @self    GPUTokenizer
	/// @param   {Buffer} buffer_value : The destination buffer containing the membership table.
	/// @param   {Real} membership_start : The starting offset of the membership table within the destination buffer.
	/// @param   {String} chars_value : The character set definition to parse and apply.
	/// @returns {Undefined}
	#endregion
	static pokeMembership = function(_buf, _memStart, _chars) {
		var _len = string_length(_chars);
		var _pos = 1;
		while (_pos <= _len) {
			var _ch = string_char_at(_chars, _pos);
			if (_ch == "\\" && _pos + 1 <= _len) {
				_pos++;
				pokeShorthand(_buf, _memStart, string_char_at(_chars, _pos), 255);
			} else {
				buffer_poke(_buf, _memStart + ord(_ch), buffer_u8, 255);
			}
			_pos++;
		}
	};
	
	#region jsDoc
	/// @func    destroy()
	/// @desc    Frees all owned surfaces and buffers used by the tokenizer instance.
	/// @self    GPUTokenizer
	/// @returns {Undefined}
	#endregion
	static destroy = function() {
		if (surface_exists(surfSource))  surface_free(surfSource);
		if (surface_exists(surfOutput))  surface_free(surfOutput);
		if (surface_exists(surfCompile)) surface_free(surfCompile);
		if (surface_exists(surfLookup))  surface_free(surfLookup);
		buffer_delete(bufCompile);
		if (bufPad != -1) buffer_delete(bufPad);
	};
}