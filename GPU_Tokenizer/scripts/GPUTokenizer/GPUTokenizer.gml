enum GPU_TOKEN {
	OMIT = 0,
	ISOLATE = 1,
	CONCATENATE = 2,
}

function GPUTokenizer() constructor {

    // =============== INTERNALS ===============

    surfSource   = -1;
    surfOutput   = -1;
    surfMatch    = -1;   // match length texture (pass 1 output)
    surfProgram  = -1;   // NFA program texture
    srcTexW = 0;  srcTexH = 0;
    outTexW = 0;  outTexH = 0;
    matchW  = 0;  matchH  = 0;
    progW   = 0;  progH   = 0;

    // NFA build state (used during compile, then discarded)
    patternRegexes = [];   // raw regex strings - parsed during compile

    // Context rules - written to buffer during addContextPattern
    bufCtx = buffer_create(256, buffer_grow, 1);
    ctxRuleCount = 0;
    ctxDataBytes = 0;

    // Type map membership
    bufTypeMap = buffer_create(256, buffer_fixed, 1);
    buffer_fill(bufTypeMap, 0, buffer_u8, 0, 256);

    unmatchedMode = GPU_TOKEN.OMIT;
    outputLength  = 0;

    // Program buffer - built during compile
    bufProgram   = -1;
    programBytes = 0;

    // Offsets into program texture
    stateTableOff = 4;
    classTableOff = 0;
    typeMapOff    = 0;
    ctxStartOff   = 0;
    ctxIndexOff   = 0;
    ctxDataOff    = 0;
    numStates     = 0;
    startState    = 0;
    numClasses    = 0;

    // Reusable pad buffer
    bufPad     = -1;
    bufPadSize = 0;

    // Shader handles - static, resolved once
    // Match shader
    static mLoc_srcSize      = shader_get_uniform(sh_gpu_match, "u_srcSize");
    static mLoc_matchSize    = shader_get_uniform(sh_gpu_match, "u_matchSize");
    static mLoc_progSize     = shader_get_uniform(sh_gpu_match, "u_progSize");
    static mLoc_totalBytes   = shader_get_uniform(sh_gpu_match, "u_totalBytes");
    static mLoc_numStates    = shader_get_uniform(sh_gpu_match, "u_numStates");
    static mLoc_startState   = shader_get_uniform(sh_gpu_match, "u_startState");
    static mLoc_numClasses   = shader_get_uniform(sh_gpu_match, "u_numClasses");
    static mLoc_stateTableOff = shader_get_uniform(sh_gpu_match, "u_stateTableOff");
    static mLoc_classTableOff = shader_get_uniform(sh_gpu_match, "u_classTableOff");
    static mLoc_typeMapOff   = shader_get_uniform(sh_gpu_match, "u_typeMapOff");
    static mIdx_program      = shader_get_sampler_index(sh_gpu_match, "u_texProgram");

    // Tokenize shader
    static tLoc_srcSize      = shader_get_uniform(sh_gpu_tokenize, "u_srcSize");
    static tLoc_outSize      = shader_get_uniform(sh_gpu_tokenize, "u_outSize");
    static tLoc_matchSize    = shader_get_uniform(sh_gpu_tokenize, "u_matchSize");
    static tLoc_progSize     = shader_get_uniform(sh_gpu_tokenize, "u_progSize");
    static tLoc_totalBytes   = shader_get_uniform(sh_gpu_tokenize, "u_totalBytes");
    static tLoc_unmatchedMode = shader_get_uniform(sh_gpu_tokenize, "u_unmatchedMode");
    static tLoc_typeMapOff   = shader_get_uniform(sh_gpu_tokenize, "u_typeMapOff");
    static tLoc_ctxStartOff  = shader_get_uniform(sh_gpu_tokenize, "u_ctxStartOff");
    static tLoc_ctxIndexOff  = shader_get_uniform(sh_gpu_tokenize, "u_ctxIndexOff");
    static tLoc_ctxDataOff   = shader_get_uniform(sh_gpu_tokenize, "u_ctxDataOff");
    static tIdx_match        = shader_get_sampler_index(sh_gpu_tokenize, "u_texMatch");
    static tIdx_program      = shader_get_sampler_index(sh_gpu_tokenize, "u_texProgram");


    // =============== PUBLIC API ===============

	#region jsDoc
	/// @func    addPattern(_regex)
	/// @desc    Adds a pattern regex to the tokenizer. Patterns are stored and later compiled into the internal NFA program during `compile()`.
	/// @self    GPUTokenizer
	/// @param   {String} regex_value : The pattern regex to add.
	/// @returns {Struct.GPUTokenizer}
	#endregion
    static addPattern = function(_regex) {
        array_push(patternRegexes, _regex);
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
        buffer_write(bufCtx, buffer_string, _open);
        buffer_write(bufCtx, buffer_string, _close);
        buffer_write(bufCtx, buffer_string, _escape);
        var _flags = (_keepOpen ? 1 : 0) | (_keepClose ? 2 : 0) | (_keepEscape ? 4 : 0);
        buffer_write(bufCtx, buffer_u8, _flags);
        ctxRuleCount++;
        ctxDataBytes += string_byte_length(_open) + 1 + string_byte_length(_close) + 1 + string_byte_length(_escape) + 1;
        return self;
    };

	#region jsDoc
	/// @func    addDelimiter(_chars)
	/// @desc    Marks the provided character set as delimiters in the internal type map. Delimiters split tokens and are not returned as token output.
	/// @self    GPUTokenizer
	/// @param   {String} chars_value : The character set or shorthand sequence to treat as delimiters.
	/// @returns {Struct.GPUTokenizer}
	#endregion
    static addDelimiter = function(_chars) {
        pokeMembership(bufTypeMap, 0, _chars, 1);
        return self;
    };

	#region jsDoc
	/// @func    addIgnore(_chars)
	/// @desc    Marks the provided character set as ignored in the internal type map. Ignored bytes are skipped entirely during tokenization.
	/// @self    GPUTokenizer
	/// @param   {String} chars_value : The character set or shorthand sequence to ignore during tokenization.
	/// @returns {Struct.GPUTokenizer}
	#endregion
    static addIgnore = function(_chars) {
        pokeMembership(bufTypeMap, 0, _chars, 2);
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
	/// @desc    Compiles all current patterns, type data, and context data into the internal GPU program buffer and uploads it to the program surface for tokenization.
	/// @self    GPUTokenizer
	/// @returns {Struct.GPUTokenizer}
	#endregion
    static compile = function() {
        // -- Step 1: Build combined Thompson NFA from all patterns --
        // NFA arrays (used temporarily during construction)
        var _op = [], _a = [], _b = [], _data = [];
        var _cls_mem = [];  // array of 256-byte membership buffers
        var _nStates = 0;
        var _nClasses = 0;

        // Emit helper
        static __emit = function(_opArr, _aArr, _bArr, _dArr, _opcode, _ea, _eb, _d) {
            var _idx = array_length(_opArr);
            array_push(_opArr, _opcode);
            array_push(_aArr, _ea);
            array_push(_bArr, _eb);
            array_push(_dArr, _d);
            return _idx;
        };

        // Build NFA for each pattern, collect fragments
        var _fragments = [];  // array of { start, outs }

        for (var _p = 0; _p < array_length(patternRegexes); _p++) {
            var _frag = buildPatternNFA(_op, _a, _b, _data, _cls_mem, patternRegexes[_p], __emit);
            array_push(_fragments, _frag);
        }

        _nStates = array_length(_op);
        _nClasses = array_length(_cls_mem);

        // Combine all patterns with SPLIT alternation
        var _masterStart = 0;
        if (array_length(_fragments) == 0) {
            // No patterns - just a MATCH state (nothing will match)
            var _matchState = __emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.MATCH, -1, -1, 0);
            _masterStart = _matchState;
            _nStates = array_length(_op);
        } else if (array_length(_fragments) == 1) {
            _masterStart = _fragments[0].start;

            var _matchState = __emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.MATCH, -1, -1, 0);
            _nStates = array_length(_op);

            for (var _p = 0; _p < array_length(_fragments); _p++) {
                var _outs = _fragments[_p].outs;
                for (var _o = 0; _o < array_length(_outs); _o++) {
                    var _ref = _outs[_o];
                    var _stateIdx = _ref div 2;
                    var _edge = _ref mod 2;
                    if (_edge == 0) _a[_stateIdx] = _matchState;
                    else _b[_stateIdx] = _matchState;
                }
            }
        } else {
            // Chain SPLITs: split -> frag0 | (split -> frag1 | (split -> frag2 | ...))
            _masterStart = _fragments[array_length(_fragments) - 1].start;
            for (var _p = array_length(_fragments) - 2; _p >= 0; _p--) {
                var _splitIdx = __emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.SPLIT, _fragments[_p].start, _masterStart, 0);
                _masterStart = _splitIdx;
            }
            _nStates = array_length(_op);

            var _matchState = __emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.MATCH, -1, -1, 0);
            _nStates = array_length(_op);

            for (var _p = 0; _p < array_length(_fragments); _p++) {
                var _outs = _fragments[_p].outs;
                for (var _o = 0; _o < array_length(_outs); _o++) {
                    var _ref = _outs[_o];
                    var _stateIdx = _ref div 2;
                    var _edge = _ref mod 2;
                    if (_edge == 0) _a[_stateIdx] = _matchState;
                    else _b[_stateIdx] = _matchState;
                }
            }
        }

        numStates = _nStates;
        startState = _masterStart;
        numClasses = _nClasses;

        // -- Step 2: Build context start map and index --
        var _ctxStartMap = array_create(256, 0);
        var _ctxIndex = [];  // array of { offset, nextRule, flags }

        // Parse context rules from bufCtx
        buffer_seek(bufCtx, buffer_seek_start, 0);
        var _ctxTotal = buffer_tell(bufCtx);
        buffer_seek(bufCtx, buffer_seek_start, 0);

        var _ctxRuleData = [];  // { open, openLen, dataOffset, flags }
        var _dataOff = 0;
        for (var _r = 0; _r < ctxRuleCount; _r++) {
            var _openStr = buffer_read(bufCtx, buffer_string);
            var _closeStr = buffer_read(bufCtx, buffer_string);
            var _escStr = buffer_read(bufCtx, buffer_string);
            var _flags = buffer_read(bufCtx, buffer_u8);
            var _openLen = string_byte_length(_openStr);
            var _firstByte = string_ord_at(_openStr, 1);
            array_push(_ctxRuleData, {
                firstByte: _firstByte,
                openLen: _openLen,
                dataOffset: _dataOff,
                nextRule: 0,
                flags: _flags,
            });
            _dataOff += string_byte_length(_openStr) + 1 + string_byte_length(_closeStr) + 1 + string_byte_length(_escStr) + 1;
        }

        // Build chained start map (longest first)
        var _groups = {};
        for (var _r = 0; _r < ctxRuleCount; _r++) {
            var _key = string(_ctxRuleData[_r].firstByte);
            if (!struct_exists(_groups, _key)) _groups[$ _key] = [];
            array_push(_groups[$ _key], _r);
        }
        var _keys = struct_get_names(_groups);
        for (var _k = 0; _k < array_length(_keys); _k++) {
            var _indices = _groups[$ _keys[_k]];
            // Sort by openLen descending
            for (var _aa = 1; _aa < array_length(_indices); _aa++) {
                var _val = _indices[_aa];
                var _bb = _aa - 1;
                while (_bb >= 0 && _ctxRuleData[_indices[_bb]].openLen < _ctxRuleData[_val].openLen) {
                    _indices[_bb + 1] = _indices[_bb]; _bb--;
                }
                _indices[_bb + 1] = _val;
            }
            for (var _j = 0; _j < array_length(_indices) - 1; _j++)
                _ctxRuleData[_indices[_j]].nextRule = _indices[_j + 1] + 1;
            _ctxStartMap[real(_keys[_k])] = _indices[0] + 1;
        }

        // -- Step 3: Pack everything into program buffer --
        stateTableOff = 4;
        classTableOff = stateTableOff + _nStates * 4;
        typeMapOff = classTableOff + _nClasses * 256;
        ctxStartOff = typeMapOff + 256;
        ctxIndexOff = ctxStartOff + 256;
        ctxDataOff = ctxIndexOff + ctxRuleCount * 4;
        programBytes = ctxDataOff + ctxDataBytes;

        var _totalPx = ceil(programBytes / 4);
        progW = 1; while (progW * progW < _totalPx) progW *= 2;
        progH = 1; while (progH < ceil(_totalPx / progW)) progH *= 2;

        var _bufSz = progW * progH * 4;
        if (bufProgram != -1) buffer_delete(bufProgram);
        bufProgram = buffer_create(_bufSz, buffer_fixed, 1);
        buffer_fill(bufProgram, 0, buffer_u8, 0, _bufSz);

        // Header
        buffer_poke(bufProgram, GPU_TOK_PROGRAM_OFFSETS.HEADER_NUM_STATES_LO, buffer_u8, _nStates);
        buffer_poke(bufProgram, GPU_TOK_PROGRAM_OFFSETS.HEADER_START_STATE, buffer_u8, _masterStart);
        buffer_poke(bufProgram, GPU_TOK_PROGRAM_OFFSETS.HEADER_NUM_CLASSES, buffer_u8, _nClasses);

        // State table
        for (var _s = 0; _s < _nStates; _s++) {
            var _off = stateTableOff + _s * 4;
            buffer_poke(bufProgram, _off + 0, buffer_u8, _op[_s]);
            buffer_poke(bufProgram, _off + 1, buffer_u8, _a[_s] == -1 ? GPU_TOK_LIMITS.NULL_INDEX : _a[_s]);
            buffer_poke(bufProgram, _off + 2, buffer_u8, _b[_s] == -1 ? GPU_TOK_LIMITS.NULL_INDEX : _b[_s]);
            buffer_poke(bufProgram, _off + 3, buffer_u8, _data[_s]);
        }

        // Class bitmasks
        for (var _c = 0; _c < _nClasses; _c++) {
            var _clsBuf = _cls_mem[_c];
            buffer_copy(_clsBuf, 0, 256, bufProgram, classTableOff + _c * 256);
        }

        // Type map
        buffer_copy(bufTypeMap, 0, 256, bufProgram, typeMapOff);

        // Context start map
        buffer_seek(bufProgram, buffer_seek_start, ctxStartOff);
        for (var _i = 0; _i < 256; _i++)
            buffer_poke(bufProgram, ctxStartOff + _i, buffer_u8, _ctxStartMap[_i]);

        // Context index
        for (var _r = 0; _r < ctxRuleCount; _r++) {
            var _off = ctxIndexOff + _r * 4;
            var _rd = _ctxRuleData[_r];
            buffer_poke(bufProgram, _off + 0, buffer_u8, _rd.dataOffset mod 256);
            buffer_poke(bufProgram, _off + 1, buffer_u8, _rd.dataOffset div 256);
            buffer_poke(bufProgram, _off + 2, buffer_u8, _rd.nextRule);
            buffer_poke(bufProgram, _off + 3, buffer_u8, _rd.flags);
        }

        // Context data (copy from bufCtx, skipping the flags bytes)
        buffer_seek(bufCtx, buffer_seek_start, 0);
        var _writePos = ctxDataOff;
        for (var _r = 0; _r < ctxRuleCount; _r++) {
            var _openStr = buffer_read(bufCtx, buffer_string);
            var _closeStr = buffer_read(bufCtx, buffer_string);
            var _escStr = buffer_read(bufCtx, buffer_string);
            buffer_read(bufCtx, buffer_u8);  // skip flags

            // Write open\0close\0escape\0
            var _tmpBuf = buffer_create(1024, buffer_grow, 1);
            buffer_write(_tmpBuf, buffer_string, _openStr);
            buffer_write(_tmpBuf, buffer_string, _closeStr);
            buffer_write(_tmpBuf, buffer_string, _escStr);
            var _tmpLen = buffer_tell(_tmpBuf);
            buffer_copy(_tmpBuf, 0, _tmpLen, bufProgram, _writePos);
            _writePos += _tmpLen;
            buffer_delete(_tmpBuf);
        }

        // Upload program texture
        if (surface_exists(surfProgram)) surface_free(surfProgram);
        surfProgram = surface_create(progW, progH);
        buffer_set_surface(bufProgram, surfProgram, 0);

        // Clean up class membership buffers
        for (var _c = 0; _c < _nClasses; _c++)
            buffer_delete(_cls_mem[_c]);

        return self;
    };


    // =============== TOKENIZE ===============

	#region jsDoc
	/// @func    tokenize(_input)
	/// @desc    Tokenizes a source string by uploading it to the source surface, running the GPU match and tokenize passes, and reading back the produced token buffer.
	/// @self    GPUTokenizer
	/// @param   {String} input_value : The input text to tokenize.
	/// @returns {Buffer}
	#endregion
    static tokenize = function(_input) {
        var _byteLen = string_byte_length(_input);
        if (_byteLen == 0) {
            outputLength = 0;
            var _b = buffer_create(1, buffer_fixed, 1);
            buffer_poke(_b, 0, buffer_u8, 0);
            return _b;
        }
        var _srcBuf = buffer_create(_byteLen, buffer_fixed, 1);
        buffer_write(_srcBuf, buffer_text, _input);
        var _result = tokenizeBuffer(_srcBuf, _byteLen);
        buffer_delete(_srcBuf);
        return _result;
    };

	#region jsDoc
	/// @func    tokenizeBuffer(_buffer, _byteLen)
	/// @desc    Tokenizes a prebuilt byte buffer by uploading it to the source surface, running the GPU match and tokenize passes, and reading back the produced token buffer.
	/// @self    GPUTokenizer
	/// @param   {Buffer} buffer_value : The source buffer containing input bytes.
	/// @param   {Real} byte_length : The number of bytes from the source buffer to tokenize.
	/// @returns {Buffer}
	#endregion
    static tokenizeBuffer = function(_buffer, _byteLen) {
        if (_byteLen == 0) {
            outputLength = 0;
            var _b = buffer_create(1, buffer_fixed, 1);
            buffer_poke(_b, 0, buffer_u8, 0);
            return _b;
        }
		
		if (_byteLen > GPU_TOK_LIMITS.MAX_INPUT_BYTES) {
			show_error("GPUTokenizer: Input size (" + string(_byteLen) + " bytes) exceeds maximum supported size ("
				+ string(GPU_TOK_LIMITS.MAX_INPUT_BYTES) + " bytes). Results would be incorrect.", true);
		}
		
        // Source surface
        var _srcPx = ceil(_byteLen / 4);
        var _sw = 1; while (_sw * _sw < _srcPx) _sw *= 2;
        var _sh = 1; while (_sh < ceil(_srcPx / _sw)) _sh *= 2;

        // Output surface (2x input)
        var _outBytes = _byteLen * 2;
        var _outPx = ceil(_outBytes / 4);
        var _ow = 1; while (_ow * _ow < _outPx) _ow *= 2;
        var _oh = 1; while (_oh < ceil(_outPx / _ow)) _oh *= 2;

        // Match surface (2 bytes per position -> 2 positions per pixel)
        var _matchPx = ceil(_byteLen / 2);
        var _mw = 1; while (_mw * _mw < _matchPx) _mw *= 2;
        var _mh = 1; while (_mh < ceil(_matchPx / _mw)) _mh *= 2;

        // Allocate/reuse surfaces
        if (_sw != srcTexW || _sh != srcTexH || !surface_exists(surfSource)) {
            if (surface_exists(surfSource)) surface_free(surfSource);
            surfSource = surface_create(_sw, _sh);
            srcTexW = _sw; srcTexH = _sh;
        }
        if (_ow != outTexW || _oh != outTexH || !surface_exists(surfOutput)) {
            if (surface_exists(surfOutput)) surface_free(surfOutput);
            surfOutput = surface_create(_ow, _oh);
            outTexW = _ow; outTexH = _oh;
        }
        if (_mw != matchW || _mh != matchH || !surface_exists(surfMatch)) {
            if (surface_exists(surfMatch)) surface_free(surfMatch);
            surfMatch = surface_create(_mw, _mh);
            matchW = _mw; matchH = _mh;
        }
        if (!surface_exists(surfProgram)) {
            surfProgram = surface_create(progW, progH);
            buffer_set_surface(bufProgram, surfProgram, 0);
        }

        // Upload source
        var _srcTexSz = _sw * _sh * 4;
        if (_srcTexSz != bufPadSize) {
            if (bufPad != -1) buffer_delete(bufPad);
            bufPad = buffer_create(_srcTexSz, buffer_fixed, 1);
            bufPadSize = _srcTexSz;
        }
        buffer_copy(_buffer, 0, min(_byteLen, _srcTexSz), bufPad, 0);
        if (_byteLen < _srcTexSz) buffer_fill(bufPad, _byteLen, buffer_u8, 0, _srcTexSz - _byteLen);
        buffer_set_surface(bufPad, surfSource, 0);

        // -- PASS 1: Match lengths --
        surface_set_target(surfMatch);
        draw_clear_alpha(c_black, 0);
        gpu_set_blendenable(false);
        gpu_set_tex_filter(false);
        shader_set(sh_gpu_match);

        texture_set_stage(mIdx_program, surface_get_texture(surfProgram));
        gpu_set_tex_filter_ext(mIdx_program, false);

        shader_set_uniform_f(mLoc_srcSize, _sw, _sh);
        shader_set_uniform_f(mLoc_matchSize, _mw, _mh);
        shader_set_uniform_f(mLoc_progSize, progW, progH);
        shader_set_uniform_f(mLoc_totalBytes, _byteLen);
        shader_set_uniform_f(mLoc_numStates, numStates);
        shader_set_uniform_f(mLoc_startState, startState);
        shader_set_uniform_f(mLoc_numClasses, numClasses);
        shader_set_uniform_f(mLoc_stateTableOff, stateTableOff);
        shader_set_uniform_f(mLoc_classTableOff, classTableOff);
        shader_set_uniform_f(mLoc_typeMapOff, typeMapOff);

        draw_surface_stretched(surfSource, 0, 0, _mw, _mh);

        shader_reset();
        surface_reset_target();

        // -- PASS 2: Token assembly --
        surface_set_target(surfOutput);
        draw_clear_alpha(c_black, 0);
        shader_set(sh_gpu_tokenize);

        texture_set_stage(tIdx_match, surface_get_texture(surfMatch));
        gpu_set_tex_filter_ext(tIdx_match, false);
        texture_set_stage(tIdx_program, surface_get_texture(surfProgram));
        gpu_set_tex_filter_ext(tIdx_program, false);

        shader_set_uniform_f(tLoc_srcSize, _sw, _sh);
        shader_set_uniform_f(tLoc_outSize, _ow, _oh);
        shader_set_uniform_f(tLoc_matchSize, _mw, _mh);
        shader_set_uniform_f(tLoc_progSize, progW, progH);
        shader_set_uniform_f(tLoc_totalBytes, _byteLen);
        shader_set_uniform_f(tLoc_unmatchedMode, unmatchedMode);
        shader_set_uniform_f(tLoc_typeMapOff, typeMapOff);
        shader_set_uniform_f(tLoc_ctxStartOff, ctxStartOff);
        shader_set_uniform_f(tLoc_ctxIndexOff, ctxIndexOff);
        shader_set_uniform_f(tLoc_ctxDataOff, ctxDataOff);

        draw_surface_stretched(surfSource, 0, 0, _ow, _oh);

        shader_reset();
        surface_reset_target();
        gpu_set_blendenable(true);
        gpu_set_tex_filter(true);

        // Read back
        var _outTexSz = _ow * _oh * 4;
        var _outBuf = buffer_create(_outTexSz, buffer_fixed, 1);
        buffer_get_surface(_outBuf, surfOutput, 0);

        outputLength = _outBytes;
        return _outBuf;
    };


    // =============== NFA BUILDER ===============

	#region jsDoc
	/// @func    buildPatternNFA(_op, _a, _b, _data, _cls_mem, _regex, _emit)
	/// @desc    Parses a regex pattern and builds a Thompson-style NFA fragment for it, returning the fragment start state and unresolved outgoing edges.
	/// @self    GPUTokenizer
	/// @param   {Array<Real>} op_array : The state opcode array to append emitted NFA states into.
	/// @param   {Array<Real>} edge_a_array : The primary outgoing edge array for emitted states.
	/// @param   {Array<Real>} edge_b_array : The secondary outgoing edge array for emitted split states.
	/// @param   {Array<Real>} data_array : The per-state payload array used for bytes, class ids, or other opcode data.
	/// @param   {Array<Buffer>} class_membership_array : The array of 256-byte class membership buffers referenced by class states.
	/// @param   {String} regex_value : The regex pattern to parse into an NFA fragment.
	/// @param   {Function} emit_function : A callback that emits a new state and returns its state index.
	/// @returns {Struct} A fragment struct in the form `{ start, outs }`, where `start` is the fragment entry state and `outs` is an array of unresolved edge references to patch later.
	#endregion
	static buildPatternNFA = function(_op, _a, _b, _data, _cls_mem, _regex, _emit) {
        var _len = string_length(_regex);
        var _pos = 1;

        var _outStack = [];
        var _opStack = [];
        var _needConcat = false;

        // Track group boundaries for counted quantifiers on groups
        var _groupPosStack = [];        // regex string positions of '('
        var _groupOutStartStack = [];   // outStack length at each '('
        var _lastGroupOpenPos = -1;     // regex pos of last closed group's '('
        var _lastGroupClosePos = -1;    // regex pos of last closed group's ')'
        var _lastGroupOutStart = -1;    // outStack index where last group started
		
		static __prec = function(_kind) {
	        if (_kind == GPU_TOK_REGEX_KIND.ALT) return 1;
	        if (_kind == GPU_TOK_REGEX_KIND.CONCAT) return 2;
	        return 0;
	    };

	    static __pushOp = function(_outStack, _opStack, _kind, _precFunc) {
	        while (array_length(_opStack) > 0) {
	            var _top = _opStack[array_length(_opStack) - 1];
	            if (_top == GPU_TOK_REGEX_KIND.ATOM) break;
	            if (_precFunc(_top) < _precFunc(_kind)) break;
	            array_pop(_opStack);
	            array_push(_outStack, { kind: _top, type: 0, data: 0 });
	        }
	        array_push(_opStack, _kind);
	    };
		
        while (_pos <= _len) {
            var _ch = string_char_at(_regex, _pos);

            // -- Quantifiers (* + ?) --
            if (_ch == "*" || _ch == "+" || _ch == "?") {
                if (_ch == "*") array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.STAR, type: 0, data: 0 });
                else if (_ch == "+") array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.PLUS, type: 0, data: 0 });
                else array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.QUEST, type: 0, data: 0 });
                _needConcat = true;
                _pos++; continue;
            }

            // -- Counted quantifier {m}, {m,}, {m,n} --
            if (_ch == "{") {
                var _savePos = _pos;
                _pos++;
                var _minn = 0; var _gotMin = false;
                while (_pos <= _len && ord(string_char_at(_regex, _pos)) >= 48 && ord(string_char_at(_regex, _pos)) <= 57) {
                    _minn = _minn * 10 + (ord(string_char_at(_regex, _pos)) - 48);
                    _gotMin = true; _pos++;
                }
                if (!_gotMin || _pos > _len) {
                    _pos = _savePos;
                    if (_needConcat) __pushOp(_outStack, _opStack, GPU_TOK_REGEX_KIND.CONCAT, __prec);
                    var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CHAR, -1, -1, ord("{"));
                    array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                    _needConcat = true; _pos++; continue;
                }

                var _maxx = _minn;
                if (_pos <= _len && string_char_at(_regex, _pos) == ",") {
                    _pos++;
                    _maxx = -1;
                    var _gotMax = false;
                    while (_pos <= _len && ord(string_char_at(_regex, _pos)) >= 48 && ord(string_char_at(_regex, _pos)) <= 57) {
                        if (!_gotMax) { _maxx = 0; _gotMax = true; }
                        _maxx = _maxx * 10 + (ord(string_char_at(_regex, _pos)) - 48);
                        _pos++;
                    }
                }

                if (_pos > _len || string_char_at(_regex, _pos) != "}") {
                    _pos = _savePos;
                    if (_needConcat) __pushOp(_outStack, _opStack, GPU_TOK_REGEX_KIND.CONCAT, __prec);
                    var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CHAR, -1, -1, ord("{"));
                    array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                    _needConcat = true; _pos++; continue;
                }
                _pos++;

                // Check if preceding element is a simple atom or a group
                var _lastItem = _outStack[array_length(_outStack) - 1];
                var _isSimpleAtom = (is_struct(_lastItem) && _lastItem.kind == GPU_TOK_REGEX_KIND.ATOM);

                if (_minn == 0 && _maxx == 0) {
                    // {0} - discard preceding element
                    if (_isSimpleAtom) {
                        array_pop(_outStack);
                    } else {
                        // Discard entire group content
                        array_resize(_outStack, _lastGroupOutStart);
                    }
                    var _jmp = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.JUMP, -1, -1, 0);
                    array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _jmp, outs: [_jmp * 2] } });
                } else if (_isSimpleAtom) {
                    // Simple atom - clone with __cloneAtomFragment
                    var _atomItem = _lastItem;
                    for (var _rep = 1; _rep < _minn; _rep++) {
                        var _clonedAtom = __cloneAtomFragment(_op, _a, _b, _data, _cls_mem, _emit, _atomItem);
                        array_push(_outStack, _clonedAtom);
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                    }
                    if (_maxx < 0) {
                        var _clonedAtom = __cloneAtomFragment(_op, _a, _b, _data, _cls_mem, _emit, _atomItem);
                        array_push(_outStack, _clonedAtom);
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.STAR, type: 0, data: 0 });
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                    } else if (_maxx > _minn) {
                        for (var _rep = 0; _rep < _maxx - _minn; _rep++) {
                            var _clonedAtom = __cloneAtomFragment(_op, _a, _b, _data, _cls_mem, _emit, _atomItem);
                            array_push(_outStack, _clonedAtom);
                            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.QUEST, type: 0, data: 0 });
                            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                        }
                    }
                } else {
                    // Group - re-parse the group substring for each additional copy
                    var _groupRegex = string_copy(_regex, _lastGroupOpenPos, _lastGroupClosePos - _lastGroupOpenPos + 1);
                    for (var _rep = 1; _rep < _minn; _rep++) {
                        var _frag = buildPatternNFA(_op, _a, _b, _data, _cls_mem, _groupRegex, _emit);
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: _frag });
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                    }
                    if (_maxx < 0) {
                        var _frag = buildPatternNFA(_op, _a, _b, _data, _cls_mem, _groupRegex, _emit);
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: _frag });
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.STAR, type: 0, data: 0 });
                        array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                    } else if (_maxx > _minn) {
                        for (var _rep = 0; _rep < _maxx - _minn; _rep++) {
                            var _frag = buildPatternNFA(_op, _a, _b, _data, _cls_mem, _groupRegex, _emit);
                            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: _frag });
                            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.QUEST, type: 0, data: 0 });
                            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.CONCAT, type: 0, data: 0 });
                        }
                    }
                }

                _needConcat = true;
                continue;
            }

            // -- Grouping ( ) --
            if (_ch == "(") {
                if (_needConcat) __pushOp(_outStack, _opStack, GPU_TOK_REGEX_KIND.CONCAT, __prec);
                array_push(_opStack, GPU_TOK_REGEX_KIND.ATOM);
                array_push(_groupPosStack, _pos);
                array_push(_groupOutStartStack, array_length(_outStack));
                _needConcat = false;
                _pos++; continue;
            }

            if (_ch == ")") {
                while (array_length(_opStack) > 0) {
                    var _top = _opStack[array_length(_opStack) - 1];
                    if (_top == GPU_TOK_REGEX_KIND.ATOM) { array_pop(_opStack); break; }
                    array_pop(_opStack);
                    array_push(_outStack, { kind: _top, type: 0, data: 0 });
                }
                _lastGroupOpenPos = array_pop(_groupPosStack);
                _lastGroupClosePos = _pos;
                _lastGroupOutStart = array_pop(_groupOutStartStack);
                _needConcat = true;
                _pos++; continue;
            }

            // -- Alternation | --
            if (_ch == "|") {
                __pushOp(_outStack, _opStack, GPU_TOK_REGEX_KIND.ALT, __prec);
                _needConcat = false;
                _pos++; continue;
            }

            // Push concat if needed (for atoms)
            if (_needConcat) __pushOp(_outStack, _opStack, GPU_TOK_REGEX_KIND.CONCAT, __prec);

            // -- Character class [...] --
            if (_ch == "[") {
                _pos++;
                var _negate = false;
                if (_pos <= _len && string_char_at(_regex, _pos) == "^") { _negate = true; _pos++; }

                var _clsBuf = buffer_create(256, buffer_fixed, 1);
                buffer_fill(_clsBuf, 0, buffer_u8, 0, 256);

                while (_pos <= _len) {
                    var _bch = string_char_at(_regex, _pos);
                    if (_bch == "]") { _pos++; break; }
                    if (_bch == "\\" && _pos + 1 <= _len) {
                        _pos++;
                        var _ech = string_char_at(_regex, _pos);
                        if (_ech == "]" || _ech == "[" || _ech == "-" || _ech == "\\") {
                            buffer_poke(_clsBuf, ord(_ech), buffer_u8, 255);
                        } else {
                            pokeShorthand(_clsBuf, 0, _ech, 255);
                        }
                        _pos++; continue;
                    }
                    if (_bch == "-" && (_pos == 1 || (_pos + 1 <= _len && string_char_at(_regex, _pos+1) == "]"))) {
                        buffer_poke(_clsBuf, ord("-"), buffer_u8, 255);
                        _pos++; continue;
                    }
                    if (_pos + 2 <= _len && string_char_at(_regex, _pos+1) == "-" && string_char_at(_regex, _pos+2) != "]") {
                        var _from = ord(_bch);
                        var _to = ord(string_char_at(_regex, _pos+2));
                        for (var _c = _from; _c <= _to; _c++)
                            buffer_poke(_clsBuf, _c, buffer_u8, 255);
                        _pos += 3; continue;
                    }
                    buffer_poke(_clsBuf, ord(_bch), buffer_u8, 255);
                    _pos++;
                }

                if (_negate) {
                    for (var _c = 0; _c < 256; _c++) {
                        var _v = buffer_peek(_clsBuf, _c, buffer_u8);
                        buffer_poke(_clsBuf, _c, buffer_u8, _v > 0 ? 0 : 255);
                    }
                }

                var _classId = array_length(_cls_mem);
                array_push(_cls_mem, _clsBuf);
                var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CLASS, -1, -1, _classId);
                array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                _needConcat = true;
                continue;
            }

            // -- Escape --
            if (_ch == "\\" && _pos + 1 <= _len) {
                _pos++;
                var _ech = string_char_at(_regex, _pos);
                _pos++;

                if (_ech == "d" || _ech == "D" || _ech == "w" || _ech == "W" || _ech == "s" || _ech == "S") {
                    var _clsBuf = buffer_create(256, buffer_fixed, 1);
                    buffer_fill(_clsBuf, 0, buffer_u8, 0, 256);
                    pokeShorthand(_clsBuf, 0, _ech, 255);
                    var _classId = array_length(_cls_mem);
                    array_push(_cls_mem, _clsBuf);
                    var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CLASS, -1, -1, _classId);
                    array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                } else {
                    var _byte = ord(_ech);
                    if (_ech == "n") _byte = 0x0A;
                    else if (_ech == "r") _byte = 0x0D;
                    else if (_ech == "t") _byte = 0x09;
                    var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CHAR, -1, -1, _byte);
                    array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                }
                _needConcat = true;
                continue;
            }

			// -- Dot --
            if (_ch == ".") {
                var _clsBuf = buffer_create(256, buffer_fixed, 1);
                buffer_fill(_clsBuf, 0, buffer_u8, 255, 256);
                buffer_poke(_clsBuf, 0x0A, buffer_u8, 0);  // exclude newline
                var _classId = array_length(_cls_mem);
                array_push(_cls_mem, _clsBuf);
                var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CLASS, -1, -1, _classId);
                array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
                _needConcat = true;
                _pos++; continue;
            }
			
            // -- Literal char --
            var _s = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.CHAR, -1, -1, ord(_ch));
            array_push(_outStack, { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } });
            _needConcat = true;
            _pos++;
        }

        // Flush remaining ops
        while (array_length(_opStack) > 0) {
            var _top = array_pop(_opStack);
            if (_top == GPU_TOK_REGEX_KIND.ATOM) continue;
            array_push(_outStack, { kind: _top, type: 0, data: 0 });
        }

        // -- Evaluate postfix into NFA fragments --
        var _fragStack = [];

        for (var _i = 0; _i < array_length(_outStack); _i++) {
            var _item = _outStack[_i];

            if (_item.kind == GPU_TOK_REGEX_KIND.ATOM) {
                array_push(_fragStack, _item.data);
                continue;
            }

            if (_item.kind == GPU_TOK_REGEX_KIND.CONCAT) {
                var _right = array_pop(_fragStack);
                var _left = array_pop(_fragStack);
                for (var _o = 0; _o < array_length(_left.outs); _o++) {
                    var _ref = _left.outs[_o];
                    var _si = _ref div 2;
                    var _edge = _ref mod 2;
                    if (_edge == 0) _a[_si] = _right.start;
                    else _b[_si] = _right.start;
                }
                array_push(_fragStack, { start: _left.start, outs: _right.outs });
                continue;
            }

            if (_item.kind == GPU_TOK_REGEX_KIND.ALT) {
                var _right = array_pop(_fragStack);
                var _left = array_pop(_fragStack);
                var _split = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.SPLIT, _left.start, _right.start, 0);
                var _outs = [];
                for (var _o = 0; _o < array_length(_left.outs); _o++) array_push(_outs, _left.outs[_o]);
                for (var _o = 0; _o < array_length(_right.outs); _o++) array_push(_outs, _right.outs[_o]);
                array_push(_fragStack, { start: _split, outs: _outs });
                continue;
            }

            if (_item.kind == GPU_TOK_REGEX_KIND.STAR) {
                var _sub = array_pop(_fragStack);
                var _split = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.SPLIT, _sub.start, -1, 0);
                for (var _o = 0; _o < array_length(_sub.outs); _o++) {
                    var _ref = _sub.outs[_o];
                    var _si = _ref div 2;
                    var _edge = _ref mod 2;
                    if (_edge == 0) _a[_si] = _split;
                    else _b[_si] = _split;
                }
                array_push(_fragStack, { start: _split, outs: [_split * 2 + 1] });
                continue;
            }

            if (_item.kind == GPU_TOK_REGEX_KIND.PLUS) {
                var _sub = array_pop(_fragStack);
                var _split = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.SPLIT, _sub.start, -1, 0);
                for (var _o = 0; _o < array_length(_sub.outs); _o++) {
                    var _ref = _sub.outs[_o];
                    var _si = _ref div 2;
                    var _edge = _ref mod 2;
                    if (_edge == 0) _a[_si] = _split;
                    else _b[_si] = _split;
                }
                array_push(_fragStack, { start: _sub.start, outs: [_split * 2 + 1] });
                continue;
            }

            if (_item.kind == GPU_TOK_REGEX_KIND.QUEST) {
                var _sub = array_pop(_fragStack);
                var _split = _emit(_op, _a, _b, _data, GPU_TOK_STATE_OP.SPLIT, _sub.start, -1, 0);
                var _outs = [];
                for (var _o = 0; _o < array_length(_sub.outs); _o++)
                    array_push(_outs, _sub.outs[_o]);
                array_push(_outs, _split * 2 + 1);
                array_push(_fragStack, { start: _split, outs: _outs });
                continue;
            }
        }

        return array_pop(_fragStack);
    };
	
	#region jsDoc
	/// @func    __cloneAtomFragment(_op, _a, _b, _data, _cls_mem, _emit, _atomItem)
	/// @desc    Clones an atom fragment by emitting a fresh copy of its start state and returning a new atom item that owns the new fragment.
	/// @desc    If the atom item does not contain a valid fragment struct, the original item is returned unchanged.
	/// @self    GPUTokenizer
	/// @param   {Array<Real>} op_array : The emitted NFA state opcode array.
	/// @param   {Array<Real>} edge_a_array : The emitted NFA primary edge array.
	/// @param   {Array<Real>} edge_b_array : The emitted NFA secondary edge array.
	/// @param   {Array<Real>} data_array : The emitted NFA per-state data array.
	/// @param   {Array<Buffer>} class_membership_array : The emitted class membership table array.
	/// @param   {Function} emit_function : Callback used to emit a new NFA state and return its index.
	/// @param   {Struct} atom_item : The atom item to clone.
	/// @returns {Struct} A new atom item with a freshly emitted fragment, or the original item if it does not contain cloneable fragment data.
	#endregion
	static __cloneAtomFragment = function(_op, _a, _b, _data, _cls_mem, _emit, _atomItem) {
		var _origData = _atomItem.data;
		if (!is_struct(_origData)) return _atomItem;
		
		// Single-state atom (CHAR, CLASS, ANY) - most common case
		var _origStart = _origData.start;
		var _origOp = _op[_origStart];
		var _origD = _data[_origStart];
		
		var _s = _emit(_op, _a, _b, _data, _origOp, -1, -1, _origD);
		return { kind: GPU_TOK_REGEX_KIND.ATOM, type: 0, data: { start: _s, outs: [_s * 2] } };
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
    static pokeMembership = function(_buf, _memStart, _chars, _val) {
        var _len = string_length(_chars);
        var _pos = 1;
        while (_pos <= _len) {
            var _ch = string_char_at(_chars, _pos);
            if (_ch == "\\" && _pos + 1 <= _len) {
                _pos++;
                pokeShorthand(_buf, _memStart, string_char_at(_chars, _pos), _val);
            } else {
                buffer_poke(_buf, _memStart + ord(_ch), buffer_u8, _val);
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
        if (surface_exists(surfMatch))   surface_free(surfMatch);
        if (surface_exists(surfProgram)) surface_free(surfProgram);
        if (bufProgram != -1) buffer_delete(bufProgram);
        if (bufPad != -1) buffer_delete(bufPad);
        buffer_delete(bufCtx);
        buffer_delete(bufTypeMap);
    };
	
}

#region Private

enum GPU_TOK_REGEX_KIND {
	ATOM = 1,
	CONCAT = 2,
	ALT = 3,
	STAR = 4,
	PLUS = 5,
	QUEST = 6,
}

enum GPU_TOK_STATE_OP {
	MATCH = 0,
	CHAR = 1,
	CLASS = 2,
	ANY = 3,
	JUMP = 4,
	SPLIT = 5,
}

enum GPU_TOK_PROGRAM_OFFSETS {
	HEADER_NUM_STATES_LO = 0,
	HEADER_NUM_STATES_HI = 1,
	HEADER_START_STATE = 2,
	HEADER_NUM_CLASSES = 3,
	STATES = 4,
}

enum GPU_TOK_LIMITS {
	NULL_INDEX = 255,
	MAX_SHADER_STATES = 512,
	MAX_EPSILON_PASSES = 16,
	MAX_CTX_SEQUENCE_BYTES = 1024,
	
	// GPU_TOK_MAX_MATCH_MB in sh_gpu_match.fsh controls max single token (default 1 MB)
	// GPU_TOK_MAX_INPUT_MB in sh_gpu_tokenize.fsh controls max input file (default 1 MB)
	MAX_INPUT_MB = 1,
	
	// Each is MB × 1024 × 1024 total iterations. Each loop level must stay under 65535.
	MAX_INPUT_BYTES = GPU_TOK_LIMITS.MAX_INPUT_MB * 1024 * 1024,
}

#endregion