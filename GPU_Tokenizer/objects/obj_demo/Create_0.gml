/// @desc Create Event - obj_gpu_tokenizer_test

// Helper: tokenize and return array of strings
function gpu_tok_to_array(_tokenizer, _input) {
    var _buf = _tokenizer.tokenize(_input);
    var _tokens = [];
    buffer_seek(_buf, buffer_seek_start, 0);
    while (buffer_tell(_buf) < _tokenizer.outputLength) {
        var _token = buffer_read(_buf, buffer_string);
        if (_token == "") break;
        array_push(_tokens, _token);
    }
    buffer_delete(_buf);
    return _tokens;
}

// Helper: run a single test with separate compile/tokenize timing
// _setupFunc receives a constructor function and must return a compiled tokenizer
function gpu_tok_test(_name, _setupFunc, _input, _expected) {
    var _iterations = 1000;
    var _compileTotal = 0;
    var _tokenizeTotal = 0;
    var _got, _tok;
    for (var _i = 0; _i < _iterations; _i++) {
        var _t0 = get_timer();
        _tok = _setupFunc();
        _compileTotal += get_timer() - _t0;
        var _t2 = get_timer();
        _got = gpu_tok_to_array(_tok, _input);
        _tokenizeTotal += get_timer() - _t2;
        _tok.destroy();
    }
    var _pass = array_equals(_got, _expected);
    show_debug_message((_pass ? "PASS - " : "FAIL - ") + _name
        + "  (compile: " + string(_compileTotal / _iterations) + "µs, tokenize: " + string(_tokenizeTotal / _iterations) + "µs)");
    show_debug_message("  Input:    " + string(_input));
    show_debug_message("  Expected: " + string(_expected));
    if (!_pass) show_debug_message("  Got:      " + string(_got));
}

var _frame = 3;

show_debug_message("===========================================");
show_debug_message("  GPU TOKENIZER TEST SUITE (MERGE vs NFA)");
show_debug_message("===========================================");


// ===========================================
//  SECTION 1: BASIC REGEX PATTERNS
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 1: Basic Regex Patterns --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Simple identifiers and numbers", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[+\-*/=<>!&|^~%]+');
        _t.addPattern(@'[(){}\[\];,.]+');
        _t.addDelimiter(@' \t');
        _t.addIgnore(@'\r');
        _t.compile();
        return _t;
    },
    "var x = 42;",
    ["var", "x", "=", "42", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Identifiers with embedded digits", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[=;]+');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    "_example123 = foo_bar2;",
    ["_example123", "=", "foo_bar2", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Multi-char operators merge", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[+\-*/=<>!&|^~%?]+');
        _t.addPattern(@'[(){}\[\];,.]+');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    "a == b != c += d >> 2",
    ["a", "==", "b", "!=", "c", "+=", "d", ">>", "2"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Float numbers", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\d+\.\d+');
        _t.addPattern(@'\d+');
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    "x = 3.14 y = 42",
    ["x", "=", "3.14", "y", "=", "42"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Single character punctuation", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'[(){}\[\];]');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "( ) { } [ ] ;",
    ["(", ")", "{", "}", "[", "]", ";"]
    );
});


// ===========================================
//  SECTION 2: DIRECTION / START-MERGE
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 2: Direction / Start-Merge --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("abc123 stays merged", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "abc123",
    ["abc123"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("123abc splits", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "123abc",
    ["123", "abc"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Mixed: abc123 def 456ghi", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "abc123 def 456ghi",
    ["abc123", "def", "456", "ghi"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("_123 stays merged (underscore starts identifier)", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "_123",
    ["_123"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("3.14 stays, .5 splits", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\d+\.\d+');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.setUnmatchedRule(GPU_TOKEN.ISOLATE);
        _t.compile();
        return _t;
    },
    "3.14 .5",
    ["3.14", ".", "5"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("3..14 splits at second dot", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\d+\.\d+');
        _t.addPattern(@'\d+');
        _t.addDelimiter(@' ');
        _t.setUnmatchedRule(GPU_TOKEN.ISOLATE);
        _t.compile();
        return _t;
    },
    "3..14",
    ["3", ".", ".", "14"]
    );
});


// ===========================================
//  SECTION 3: UNMATCHED BYTE MODES
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 3: Unmatched Byte Modes --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("OMIT: unmatched disappear", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.setUnmatchedRule(GPU_TOKEN.OMIT);
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "abc ! def",
    ["abc", "def"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("ISOLATE: each unmatched is own token", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.setUnmatchedRule(GPU_TOKEN.ISOLATE);
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "a!b",
    ["a", "!", "b"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("CONCATENATE: consecutive unmatched merge", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.setUnmatchedRule(GPU_TOKEN.CONCATENATE);
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "a!!b",
    ["a", "!!", "b"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("ISOLATE: multiple different unmatched", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.setUnmatchedRule(GPU_TOKEN.ISOLATE);
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "a!@#b",
    ["a", "!", "@", "#", "b"]
    );
});


// ===========================================
//  SECTION 4: DELIMITER AND IGNORE
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 4: Delimiter and Ignore --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Ignore strips \\r, \\n delimits", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addDelimiter(@'\n');
        _t.addIgnore(@'\r');
        _t.compile();
        return _t;
    },
    "abc\r\ndef",
    ["abc", "def"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Multiple consecutive delimiters", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "abc     def",
    ["abc", "def"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Tab and space both delimit", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    "a\tb c",
    ["a", "b", "c"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("CSV: comma as delimiter", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'[^,\n]+');
        _t.addDelimiter(",");
        _t.compile();
        return _t;
    },
    "apple,banana,cherry",
    ["apple", "banana", "cherry"]
    );
});


// ===========================================
//  SECTION 5: CONTEXT PATTERNS
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 5: Context Patterns --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Double-quoted string with escape", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "hello \"world\"";',
    ["x", "=", @'"hello \"world\""', ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Line comment captures to newline", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern("//", "\n", "");
        _t.addDelimiter(@' \t');
        _t.addIgnore(@'\r');
        _t.compile();
        return _t;
    },
    "x = 5; // comment\ny = 10;",
    ["x", "=", "5", ";", "// comment\n", "y", "=", "10", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Block comment spans newlines", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern("/*", "*/", "");
        _t.addDelimiter(@' \t\n');
        _t.compile();
        return _t;
    },
    "a = /* block\ncomment */ b;",
    ["a", "=", "/* block\ncomment */", "b", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Triple-quote priority", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"""', @'"""', "");
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = """triple""" y = "single"',
    ["x", "=", @'"""triple"""', "y", "=", @'"single"']
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("HTML comment (4-byte opener)", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d\-]*');
        _t.addPattern(@'[<>/=]+');
        _t.addContextPattern("<!--", "-->", "");
        _t.addDelimiter(@' \t\n');
        _t.compile();
        return _t;
    },
    "<div><!-- hello --></div>",
    ["<", "div", ">", "<!-- hello -->", "</", "div", ">"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Chained context: // vs /*", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern("//", "\n", "");
        _t.addContextPattern("/*", "*/", "");
        _t.addDelimiter(@' \t');
        _t.addIgnore(@'\n\r');
        _t.compile();
        return _t;
    },
    "a = b; // line\nc = /* block */ d;",
    ["a", "=", "b", ";", "// line\n", "c", "=", "/* block */", "d", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Raw string @'...'", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@"@'", @"'", "");
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @"x = @'hello\nworld';",
    ["x", "=", @"@'hello\nworld'", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Empty string literal", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "";',
    ["x", "=", @'""', ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Escaped escape char inside string", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "a\\b";',
    ["x", "=", @'"a\\b"', ";"]
    );
});


// ===========================================
//  SECTION 6: KEEP FLAGS
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 6: Keep Flags --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("keepOpen=false, keepClose=false: content only", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\', false, false, true);
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "hello";',
    ["x", "=", "hello", ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("keepEscape=false: parsed string", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\', false, false, false);
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "hello \"world\"";',
    ["x", "=", @'hello "world"', ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("BBCode strip brackets", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d=]*');
        _t.addContextPattern("[", "]", "", false, false);
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "[size=2] hello [/size]",
    ["size=2", "hello", "/size"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Line comment keepClose=false: strip newline", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern("//", "\n", "", true, false);
        _t.addDelimiter(@' \t\n');
        _t.compile();
        return _t;
    },
    "x = 5; // comment\ny = 10;",
    ["x", "=", "5", ";", "// comment", "y", "=", "10", ";"]
    );
});


// ===========================================
//  SECTION 7: EDGE CASES
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 7: Edge Cases --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Empty input", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "",
    []
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Only delimiters", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    "   \t  \t  ",
    []
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Single character input", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    "x",
    ["x"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Unclosed context at end of input", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'hello "unclosed',
    ["hello", @'"unclosed']
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Adjacent context patterns", function() {
        var _t = new GPUTokenizer();
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'"abc""def"',
    [ @'"abc"', @'"def"']
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Context is entire input", function() {
        var _t = new GPUTokenizer();
        _t.addContextPattern(@'"', @'"', @'\');
        _t.compile();
        return _t;
    },
    @'"hello world"',
    [ @'"hello world"']
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Escaped char at end of string", function() {
        var _t = new GPUTokenizer();
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'"test\\"',
    [ @'"test\\"']
    );
});


// ===========================================
//  SECTION 8: UTF-8
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 8: UTF-8 --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("UTF-8 inside context pattern (string)", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'[=;]+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' \t');
        _t.compile();
        return _t;
    },
    @'x = "héllo wörld";',
    ["x", "=", @'"héllo wörld"', ";"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Emoji inside context pattern", function() {
        var _t = new GPUTokenizer();
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'"hello 🌍"',
    [ @'"hello 🌍"']
    );
});


// ===========================================
//  SECTION 9: COMPLEX / REAL-WORLD
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n-- SECTION 9: Complex / Real-world --");
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Full GML-style tokenizer", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w[\w\d]*');
        _t.addPattern(@'\d+\.\d+');
        _t.addPattern(@'\d+');
        _t.addPattern(@'[+\-*/=<>!&|^~%?]+');
        _t.addPattern(@'[(){}\[\];,:.#$@]');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addContextPattern("//", "\n", "");
        _t.addContextPattern("/*", "*/", "");
        _t.addDelimiter(@' \t');
        _t.addIgnore(@'\r');
        _t.setUnmatchedRule(GPU_TOKEN.ISOLATE);
        _t.compile();
        return _t;
    },
    "var _x = 3.14 + foo(); // done",
    ["var", "_x", "=", "3.14", "+", "foo", "(", ")", ";", "// done"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Block comment containing quotes", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addContextPattern("/*", "*/", "");
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'/* "not a string" */ hello',
    [ @'/* "not a string" */', "hello"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("String containing comment-like content", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addContextPattern("//", "\n", "");
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'"hello // world" foo',
    [ @'"hello // world"', "foo"]
    );
});

call_later(_frame++, time_source_units_frames, function() {
    gpu_tok_test("Multiple strings on one line", function() {
        var _t = new GPUTokenizer();
        _t.addPattern(@'\w+');
        _t.addPattern(@'[+]+');
        _t.addContextPattern(@'"', @'"', @'\');
        _t.addDelimiter(@' ');
        _t.compile();
        return _t;
    },
    @'"abc" + "def" + "ghi"',
    [ @'"abc"', "+", @'"def"', "+", @'"ghi"']
    );
});


// ===========================================
//  DONE
// ===========================================

call_later(_frame++, time_source_units_frames, function() {
    show_debug_message("\n===========================================");
    show_debug_message("  ALL TESTS COMPLETE");
    show_debug_message("===========================================");
});


// -- STRESS TEST - Bee Movie Script --
call_later(_frame++, time_source_units_frames, function() {
	var _input_text = @"NARRATOR:\n\n(Black screen with text; The sound of buzzing bees can be heard)\nAccording to all known laws\n\nof aviation,\n\n\nthere is no way a bee\nshould be able to fly.\n\n\nIts wings are too small to get\nits fat little body off the ground.\n\n\nThe bee, of course, flies anyway\n\n\nbecause bees don't care\n\nwhat humans think is impossible.\nBARRY BENSON:\n\n(Barry is picking out a shirt)\nYellow, black. Yellow, black.\nYellow, black. Yellow, black.\n\n\nOoh, black and yellow!\nLet's shake it up a little.\nJANET BENSON:\n\nBarry! Breakfast is ready!\nBARRY:\n\nComing!\n\n\nHang on a second.\n(Barry uses his antenna like a phone)\n\n\nHello?\nADAM FLAYMAN:\n\n\n(Through phone)\n\n- Barry?\n\nBARRY:\n\n- Adam?\n\nADAM:\n\n- Can you believe this is happening?\nBARRY:\n\n- | can't. I'll pick you up.\n\n(Barry flies down the stairs)\n\n\nMARTIN BENSON:\n\n\nLooking sharp.\n\nJANET:\n\nUse the stairs. Your father\npaid good money for those.\nBARRY:\n\nSorry. I'm excited.\n\nMARTIN:\n\nHere's the graduate.\n\nWe're very proud of you, son.\n\n\nA perfect report card, all B's.\nJANET:\n\nVery proud.\n\n(Rubs Barry's hair)\nBARRY=\n\nMa! | got a thing going here.\nJANET:\n\n- You got lint on your fuzz.\nBARRY:\n\n- Ow! That's me!\n\n\nJANET:\n\n- Wave to us! We'll be in row 118,000.\n- Bye!\n\n(Barry flies out the door)\n\nJANET:\n\nBarry, | told you,\n\nstop flying in the house!\n\n(Barry drives through the hive,and is waved at by Adam who is reading a\nnewspaper)\n\nBARRY==\n\n- Hey, Adam.\n\nADAM:\n\n- Hey, Barry.\n\n(Adam gets in Barry's car)\n\n\n- Is that fuzz gel?\n\nBARRY:\n\n-A little. Special day, graduation.\n\nADAM:\n\nNever thought I'd make it.\n\n(Barry pulls away from the house and continues driving)\nBARRY:\n\nThree days grade school,\n\n\nthree days high school...\n\nADAM:\n\nThose were awkward.\n\nBARRY:\n\nThree days college. I'm glad | took\n\na day and hitchhiked around the hive.\nADAM==\n\nYou did come back different.\n\n(Barry and Adam pass by Artie, who is jogging)\nARTIE:\n\n- Hi, Barry!\n\n\nBARRY:\n\n- Artie, growing a mustache? Looks good.\nADAM:\n\n- Hear about Frankie?\n\nBARRY:\n\n\n- You going to the funeral?\nBARRY:\n- No, I'm not going to his funeral.\n\n\nEverybody knows,\nsting someone, you die.\n\n\nDon't waste it on a squirrel.\n\nSuch a hothead.\n\nADAM:\n\n| guess he could have\n\njust gotten out of the way.\n\n(The car does a barrel roll on the loop-shaped bridge and lands on the\nhighway)\n\n\n| love this incorporating\n\nan amusement park into our regular day.\n\nBARRY:\n\n| guess that's why they say we don't need vacations.\n\n(Barry parallel parks the car and together they fly over the graduating\nstudents)\n\nBoy, quite a bit of pomp...\n\nunder the circumstances.\n\n(Barry and Adam sit down and put on their hats)\n\n\n- Well, Adam, today we are men.\n\n\nADAM:\n\n- We are!\n\nBARRY=\n\n- Bee-men.\n\n=ADAM=\n\n- Amen!\n\nBARRY AND ADAM:\n\nHallelujah!\n\n(Barry and Adam both have a happy spasm)\nANNOUNCER:\n\nStudents, faculty, distinguished bees,\n\n\nplease welcome Dean Buzzwell.\nDEAN BUZZWELL:\n\nWelcome, New Hive Oity\ngraduating class of...\n\n\n9!\nThat concludes our ceremonies.\n\n\nAnd begins your career\n\nat Honex Industries!\n\nADAM:\n\nWill we pick our job today?\n\n(Adam and Barry get into a tour bus)\nBARRY=\n\n| heard it's just orientation.\n\n(Tour buses rise out of the ground and the students are automatically\nloaded into the buses)\n\nTOUR GUIDE:\n\nHeads up! Here we go.\n\n\nANNOUNCER:\n\nKeep your hands and antennas\ninside the tram at all times.\nBARRY:\n\n- Wonder what it'll be like?\nADAM:\n\n- A little scary.\n\nTOUR GUIDE==\n\nWelcome to Honex,\n\n\na division of Honesco\n\n\nand a part of the Hexagon Group.\nBarry:\n\nThis is it!\n\nBARRY AND ADAM:\n\nWow.\n\nBARRY:\n\nWow.\n\n(The bus drives down a road an on either side are the Bee's massive\ncomplicated Honey-making machines)\nTOUR GUIDE:\n\nWe know that you, as a bee,\n\nhave worked your whole life\n\n\nto get to the point where you\ncan work for your whole life.\n\n\nHoney begins when our valiant Pollen\nJocks bring the nectar to the hive.\n\n\nOur top-secret formula\n\nig automatically color-corrected,\nscent-adjusted and bubble-contoured\nate this soothing sweet syrup\n\n\nwith its distinctive\n\ngolden glow you know as...\n\nEVERYONE ON BUS:\n\nHoney!\n\n(The guide has been collecting honey into a bottle and she throws it into\nthe crowd on the bus and it is caught by a girl in the back)\nADAM:\n\n- That girl was hot.\n\nBARRY:\n\n- She's my cousin!\n\nADAM==\n\n- She is?\n\nBARRY:\n\n- Yes, we're all cousins.\n\nADAM:\n\n\n- Right. You're right.\nTOUR GUIDE:\n- At Honex, we constantly strive\n\n\nto improve every aspect\nof bee existence.\n\n\nThese bees are stress-testing\n\na new helmet technology.\n\n(The bus passes by a Bee wearing a helmet who is being smashed into the\nground with fly-swatters, newspapers and boots. He lifts a thumbs up but\nyou can hear him groan)\n\n\nADAM==\n\n\n- What do you think he makes?\nBARRY:\n\n- Not enough.\n\nTOUR GUIDE:\n\nHere we have our latest advancement,\nthe Krelman.\n\n(They pass by a turning wheel with Bees standing on pegs, who are each\nwearing a finger-shaped hat)\n\nBarry:\n\n- Wow, What does that do?\n\nTOUR GUIDE:\n\n- Catches that little strand of honey\n\n\nthat hangs after you pour it.\n\nSaves us millions.\n\nADAM:\n\n(Intrigued)\n\nCan anyone work on the Krelman?\nTOUR GUIDE:\n\nOf course. Most bee jobs are\n\nsmall ones.\n\nBut bees know that every small job,\nif it's done well, means a lot.\n\n\nBut choose carefully\nbecause you'll stay in the job\n\n\nyou pick for the rest of your life.\n(Everyone claps except for Barry)\n\n\nBARRY:\n\nThe same job the rest of your life?\n| didn't know that.\n\nADAM:\n\n\nWhat's the difference?\n\nTOUR GUIDE:\n\nYou'll be happy to know that bees,\n\nas a species, haven't had one day off\n\n\nin 27 million years.\n\nBARRY:\n\n(Upset)\n\nSo you'll just work us to death?\n\n\nWe'll sure try.\n\n(Everyone on the bus laughs except Barry. Barry and Adam are walking back\nhome together)\n\nADAM:\n\nWow! That blew my mind!\n\nBARRY:\n\n''What's the difference?''\n\nHow can you say that?\n\n\nOne job forever?\n\nThat's an insane choice to have to make.\nADAM:\n\nI'm relieved. Now we only have\n\nto make one decision in life.\nBARRY:\n\nBut, Adam, how could they\n\nnever have told us that?\n\nADAM:\n\nWhy would you question anything?\nWe're bees.\n\n\nWe're the most perfectly\nfunctioning society on Earth.\n\n\nBARRY:\n\nYou ever think maybe things\n\nwork a little too well here?\n\nADAM:\n\nLike what? Give me one example.\n\n\n(Barry and Adam stop walking and it is revealed to the audience that\nhundreds of cars are speeding by and narrowly missing them in perfect\nunison)\n\nBARRY:\n\n| don't know. But you know\n\nwhat I'm talking about.\n\nANNOUNCER:\n\nPlease clear the gate.\n\nRoyal Nectar Force on approach.\n\nBARRY:\n\nWait a second. Check it out.\n\n(The Pollen jocks fly in, circle around and landing in line)\n\n\n- Hey, those are Pollen Jocks!\nADAM:\n- Wow.\n\n\nI've never seen them this close.\nBARRY:\n\nThey know what it's like\n\noutside the hive.\n\nADAM:\n\nYeah, but some don't come back.\nGIRL BEES:\n\n- Hey, Jocks!\n\n- Hi, Jocks!\n\n(The Pollen Jocks hook up their backpacks to machines that pump the nectar\nto trucks, which drive away)\n\n\nLOU LO DUVA:\nYou guys did great!\n\n\nYou're monsters!\n\nYou're sky freaks!\n\n| love it!\n\n(Punching the Pollen Jocks in joy)\n| love it!\n\nADAM:\n\n- | wonder where they were.\nBARRY:\n\n- | don't know.\n\n\nTheir day's not planned.\n\n\nOutside the hive, flying who knows\nwhere, doing who knows what.\n\n\nYou can't just decide to be a Pollen\n\nJock. You have to be bred for that.\n\nADAM==\n\nRight.\n\n(Barry and Adam are covered in some pollen that floated off of the Pollen\nJocks)\n\nBARRY:\n\nLook at that. That's more pollen\n\nthan you and | will see in a lifetime.\n\nADAM:\n\nIt's just a status symbol.\n\nBees make too much of it.\n\nBARRY:\n\nPerhaps. Unless you're wearing it\n\nand the ladies see you wearing it.\n\n(Barry waves at 2 girls standing a little away from them)\n\n\nADAM==\n\nThose ladies?\n\nAren't they our cousins too?\nBARRY:\n\nDistant. Distant.\n\nPOLLEN JOCK #1:\n\nLook at these two.\n\nPOLLEN JOCK #2:\n\n- Couple of Hive Harrys.\nPOLLEN JOCK #1:\n\n- Let's have fun with them.\nGIRL BEE #1:\n\nIt must be dangerous\n\nbeing a Pollen Jock.\nBARRY:\n\nYeah. Once a bear pinned me\nagainst a mushroom!\n\n\nHe had a paw on my throat,\n\nand with the other, he was slapping me!\n\n(Slaps Adam with his hand to represent his scenario)\nGIRL BEE #2:\n\n- Oh, my!\n\nBARRY:\n\n\n- | never thought I'd knock him out.\n\nGIRL BEE #1:\n\n(Looking at Adam)\n\nWhat were you doing during this?\n\nADAM:\n\nObviously | was trying to alert the authorities.\nBARRY:\n\n| can autograph that.\n\n\n(The pollen jocks walk up to Barry and Adam, they pretend that Barry and\nAdam really are pollen jocks.)\nPOLLEN JOCK #1:\n\nA little gusty out there today,\nwasn't it, comrades?\n\nBARRY:\n\nYeah. Gusty.\n\nPOLLEN JOCK #1:\n\nWe're hitting a sunflower patch\nsix miles from here tomorrow.\nBARRY:\n\n- Six miles, huh?\n\nADAM:\n\n- Barry!\n\nPOLLEN JOCK #2:\n\nA puddle jump for us,\n\nbut maybe you're not up for it.\nBARRY:\n\n- Maybe | am.\n\nADAM:\n\n- You are not!\n\nPOLLEN JOCK #1:\n\nWe're going 0900 at J-Gate.\n\n\nWhat do you think, buzzy-boy?\n\nAre you bee enough?\n\nBARRY:\n\n| might be. It all depends\n\non what 0900 means.\n\n(The scene cuts to Barry looking out on the hive-city from his balcony at\nnight)\n\nMARTIN:\n\n\nHey, Honex!\nBARRY:\n\n\nDad, you surprised me.\n\nMARTIN:\n\nYou decide what you're interested in?\nBARRY:\n\n- Well, there's a lot of choices.\n\n- But you only get one.\n\n\nDo you ever get bored\n\ndoing the same job every day?\nMARTIN:\n\nSon, let me tell you about stirring.\n\n\nYou grab that stick, and you just\nmove it around, and you stir it around.\n\n\nYou get yourself into a rhythm.\nIt's a beautiful thing.\n\nBARRY:\n\nYou know, Dad,\n\nthe more | think about it,\n\n\nmaybe the honey field\njust isn't right for me.\nMARTIN:\n\nYou were thinking of what,\nmaking balloon animals?\n\n\nThat's a bad job\nfor a guy with a stinger.\n\n\nJanet, your son's not sure\n\nhe wants to go into honey!\nJANET:\n\n- Barry, you are so funny sometimes.\nBARRY:\n\n- I'm not trying to be funny.\nMARTIN:\n\nYou're not funny! You're going\ninto honey. Our son, the stirrer!\nJANET:\n\n- You're gonna be a stirrer?\nBARRY:\n\n- No one's listening to me!\n\n\nMARTIN:\n\nWait till you see the sticks | have.\nBARRY:\n\n| could say anything right now.\n\nI'm gonna get an ant tattoo!\n\n(Barry's parents don't listen to him and continue to ramble on)\nMARTIN:\n\nLet's open some honey and celebrate!\nBARRY:\n\nMaybe I'll pierce my thorax.\n\nShave my antennae.\n\n\nShack up with a grasshopper. Get\n\na gold tooth and call everybody ''dawg''!\n\nJANET:\n\nI'm so proud.\n\n(The scene cuts to Barry and Adam waiting in line to get a job)\nADAM:\n\n- We're starting work today!\n\n\nBARRY:\n\n- Today's the day.\n\nADAM:\n\nCome on! All the good jobs\n\nwill be gone.\n\nBARRY:\n\nYeah, right.\n\nJOB LISTER:\n\nPollen counting, stunt bee, pouring,\nstirrer, front desk, hair removal...\nBEE IN FRONT OF LINE:\n\n- Is it still available?\n\nJOB LISTER:\n\n- Hang on. Two left!\n\n\nOne of them's yours! Congratulations!\nStep to the side.\n\nADAM:\n\n- What'd you get?\n\nBEE IN FRONT OF LINE:\n\n- Picking crud out. Stellar!\n\n(He walks away)\n\nADAM:\n\nWow!\n\n\nJOB LISTER:\n\nCouple of newbies?\n\nADAM:\n\nYes, sir! Our first day! We are ready!\n\nJOB LISTER:\n\nMake your choice.\n\n(Adam and Barry look up at the job board. There are hundreds of constantly\nchanging panels that contain available or unavailable jobs. It looks very\nconfusing)\n\n\nADAM:\n\n- You want to go first?\n\nBARRY:\n\n- No, you go.\n\nADAM:\n\nOh, my. What's available?\n\nJOB LISTER:\n\nRestroom attendant's open,\n\nnot for the reason you think.\n\nADAM:\n\n- Any chance of getting the Krelman?\n\nJOB LISTER:\n\n- Sure, you're on.\n\n(Puts the Krelman finger-hat on Adam's head)\n(Suddenly the sign for Krelman closes out)\n\n\nI'm sorry, the Krelman just closed out.\n(Takes Adam's hat off)\n\nWax monkey's always open.\n\nADAM:\n\nThe Krelman opened up again.\n\n\nWhat happened?\n\nJOB LISTER:\n\nA bee died. Makes an opening. See?\nHe's dead. Another dead one.\n\n\nDeady. Deadified. Two more dead.\n\n\nDead from the neck up.\nDead from the neck down. That's life!\n\n\nADAM:\nOh, this is so hard!\n\n\n(Barry remembers what the Pollen Jock offered him and he flies off)\nHeating, cooling,\nstunt bee, pourer, stirrer,\n\n\nhumming, inspector number seven,\nlint coordinator, stripe supervisor,\n\n\nmite wrangler. Barry, what\ndo you think | should... Barry?\n(Adam turns around and sees Barry flying away)\n\n\nBarry!\n\nPOLLEN JOCK:\n\nAll right, we've got the sunflower patch\nin quadrant nine...\n\nADAM:\n\n(Through phone)\n\nWhat happened to you?\nWhere are you?\n\nBARRY:\n\n- I'm going out.\n\nADAM:\n\n- Out? Out where?\n\nBARRY:\n\n- Out there.\n\nADAM:\n\n- Oh, no!\n\nBARRY:\n\n| have to, before | go\n\nto work for the rest of my life.\nADAM:\n\n\nYou're gonna die! You're crazy!\n(Barry hangs up)\n\nHello?\n\nPOLLEN JOCK #2:\n\nAnother call coming in.\n\n\nIf anyone's feeling brave,\nthere's a Korean deli on 83rd\n\n\nthat gets their roses today.\nBARRY:\nHey, guys.\n\n\nPOLLEN JOCK #1 ==\n\n- Look at that.\n\nPOLLEN JOCK #2:\n\n- Isn't that the kid we saw yesterday?\nLOU LO DUVA:\n\nHold it, son, flight deck's restricted.\nPOLLEN JOCK #1:\n\nIt's OK, Lou. We're gonna take him up.\n(Puts hand on Barry's shoulder)\n\nLOU LO DUVA:\n\n(To Barry) Really? Feeling lucky, are you?\nBEE WITH CLIPBOARD:\n\n(To Barry) Sign here, here. Just initial that.\n\n\n- Thank you.\nLOU LO DUVA:\n- OK.\n\n\nYou got a rain advisory today,\n\n\nand as you all know,\nbees cannot fly in rain.\n\n\nSo be careful. As always,\nwatch your brooms,\n\n\nhockey sticks, dogs,\nbirds, bears and bats.\n\n\nAlso, | got a couple of reports\nof root beer being poured on us.\n\n\nMurphy's in a home because of it,\nbabbling like a cicada!\n\nBARRY:\n\n- That's awful.\n\nLOU LO DUVA:\n\n(Still talking through megaphone)\n- And a reminder for you rookies,\n\n\nbee law number one,\nabsolutely no talking to humans!\n\n\nAll right, launch positions!\nPOLLEN JOCKS:\n(The Pollen Jocks run into formation)\n\n\nBuzz, buzz, buzz, buzz! Buzz, buzz,\nbuzz, buzz! Buzz, buzz, buzz, buzz!\nLOU LU DUVA:\n\nBlack and yellow!\n\nPOLLEN JOCKS:\n\n\nHello!\n\nPOLLEN JOCK #1:\n\n(To Barry)You ready for this, hot shot?\nBARRY:\n\nYeah. Yeah, bring it on.\n\nPOLLEN JOCK's:\n\nWind, check.\n\n\n- Antennae, check.\n- Nectar pack, check.\n\n\n- Wings, check.\n\n- Stinger, check.\n\nBARRY:\n\nScared out of my shorts, check.\nLOU LO DUVA:\n\nOK, ladies,\n\n\nlet's move it out!\n\n\nPound those petunias,\nyou striped stem-suckers!\n\n\nAll of you, drain those flowers!\n\n(The pollen jocks fly out of the hive)\nBARRY:\n\nWow! I'm out!\n\n\n| can't believe I'm out!\n\n\nSo blue.\n\n\n| feel so fast and free!\n\n\nBox kite!\n(Barry flies through the kite)\n\n\nWow!\n\n\nFlowers!\n\n(A pollen jock puts on some high tech goggles that shows flowers similar to\nheat sink goggles.)\n\nPOLLEN JOCK:\n\nThis is Blue Leader.\n\nWe have roses visual.\n\n\nBring it around 30 degrees and hold.\n\n\nRoses!\nPOLLEN JOCK #1:\n30 degrees, roger. Bringing it around.\n\n\nStand to the side, kid.\n\nIt's got a bit of a kick.\n\n(The pollen jock fires a high-tech gun at the flower, shooting tubes that\nsuck up the nectar from the flower and collects it into a pouch on the gun)\nBARRY:\n\nThat is one nectar collector!\n\nPOLLEN JOCK #1==\n\n- Ever see pollination up close?\n\nBARRY:\n\n- No, sir.\n\nPOLLEN JOCK #1:\n\n\n(Barry and the Pollen jock fly over the field, the pollen jock sprinkles\npollen as he goes)\n\n\n| pick up some pollen here, sprinkle it\nover here. Maybe a dash over there,\n\n\na pinch on that one.\n\nSee that? It's a little bit of magic.\nBARRY:\n\nThat's amazing. Why do we do that?\nPOLLEN JOCK #1:\n\nThat's pollen power. More pollen, more\nflowers, more nectar, more honey for us.\n\n\nBARRY:\n\nCool.\n\nPOLLEN JOCK #1:\n\nI'm picking up a lot of bright yellow.\ncould be daisies. Don't we need those?\nPOLLEN JOCK #2:\n\nCopy that visual.\n\n\nWait. One of these flowers\n\nseems to be on the move.\n\nPOLLEN JOCK #1:\n\nSay again? You're reporting\n\na moving flower?\n\nPOLLEN JOCK #2:\n\nAffirmative.\n\n(The Pollen jocks land near the ''flowers'' which, to the audience are\nobviously just tennis balls)\n\nKEN:\n\n(In the distance) That was on the line!\n\n\nPOLLEN JOCK #1:\n\nThis is the coolest. What is it?\nPOLLEN JOCK #2:\n\n| don't know, but I'm loving this color.\n\n\nIt smells good.\n\nNot like a flower, but | like it.\n\nPOLLEN JOCK #1:\n\nYeah, fuzzy.\n\n(Sticks his hand on the ball but it gets stuck)\n\nPOLLEN JOCK #3==\n\nChemical-y.\n\n(The pollen jock finally gets his hand free from the tennis ball)\nPOLLEN JOCK #1:\n\nCareful, guys. It's a little grabby.\n\n(The pollen jocks turn around and see Barry lying his entire body on top of\none of the tennis balls)\n\nPOLLEN JOCK #2:\n\nMy sweet lord of bees!\n\nPOLLEN JOCK #3:\n\nCandy-brain, get off there!\n\nPOLLEN JOCK #1:\n\n(Pointing upwards)\n\nProblem!\n\n\n(A human hand reaches down and grabs the tennis ball that Barry is stuck\nto)\n\nBARRY:\n\n- Guys!\n\nPOLLEN JOCK #2:\n\n- This could be bad.\n\nPOLLEN JOCK #3:\n\nAffirmative.\n\n(Vanessa Bloome starts bouncing the tennis ball, not knowing Barry is stick\nto it)\n\n\nBARRY==\nVery close.\n\n\nGonna hurt.\n\n\nMama's little boy.\n\n(Barry is being hit back and forth by two humans playing tennis. He is\nstill stuck to the ball)\n\nPOLLEN JOCK #1:\n\nYou are way out of position, rookie!\nKEN:\n\nComing in at you like a MISSILE!\n(Barry flies past the pollen jocks, still stuck to the ball)\nBARRY:\n\n(In slow motion)\n\nHelp me!\n\nPOLLEN JOCK #2:\n\n| don't think these are flowers.\nPOLLEN JOCK #3:\n\n- Should we tell him?\n\nPOLLEN JOCK #1:\n\n- | think he knows.\n\nBARRY:\n\nWhat is this?!\n\nKEN:\n\nMatch point!\n\n\nYou can start packing up, honey,\n\nbecause you're about to EAT IT!\n\n(A pollen jock coughs which confused Ken and he hits the ball the wrong way\nwith Barry stuck to it and it goes flying into the city)\n\nBARRY:\n\n\nYowser!\n\n(Barry bounces around town and gets stuck in the engine of a car. He flies\ninto the air conditioner and sees a bug that was frozen in there)\n\nBARRY:\n\nEw, gross.\n\n(The man driving the car turns on the air conditioner which blows Barry\ninto the car)\n\nGIRL IN CAR:\n\nThere's a bee in the car!\n\n\n- Do something!\n\nDAD DRIVING CAR:\n\n- I'm driving!\n\nBABY GIRL:\n\n(Waving at Barry)\n\n- Hi, bee.\n\n(Barry smiles and waves at the baby girl)\nGUY IN BACK OF CAR:\n\n- He's back here!\n\n\nHe's going to sting me!\n\nGIRL IN CAR:\n\nNobody move. If you don't move,\n\nhe won't sting you. Freeze!\n\n(Barry freezes as well, hovering in the middle of the car)\n\n\nGRANDMA IN CAR==\n\nHe blinked!\n\n(The grandma whips out some bee-spray and sprays everywhere in the car,\nclimbing into the front seat, still trying to spray Barry)\n\nGIRL IN CAR:\n\nSpray him, Granny!\n\nDAD DRIVING THE CAR:\n\nWhat are you doing?!\n\n(Barry escapes the car through the air conditioner and is flying high above\n\n\nthe ground, safe.)\n\nBARRY:\n\nWow... the tension level\n\nout here is unbelievable.\n\n(Barry sees that storm clouds are gathering and he can see rain clouds\nmoving into this direction)\n\n\n| gotta get home.\n\n\nCan't fly in rain.\n\n\nCan't fly in rain.\n(A rain drop hits Barry and one of his wings is damaged)\n\n\nCan't fly in rain.\n\n(A second rain drop hits Barry again and he spirals downwards)\nMayday! Mayday! Bee going down!\n\n(WW2 plane sound effects are played as he plummets, and he crash-lands on a\nplant inside an apartment near the window)\n\nVANESSA BLOOME:\n\nKen, could you close\n\nthe window please?\n\nKEN==\n\nHey, check out my new resume.\n\n| made it into a fold-out brochure.\n\n\nYou see?\n\n(Folds brochure resume out)\n\nFolds out.\n\n(Ken closes the window, trapping Barry inside)\n\nBARRY:\n\nOh, no. More humans. | don't need this.\n\n(Barry tries to fly away but smashes into the window and falls again)\n\n\nWhat was that?\n\n\n(Barry keeps trying to fly out the window but he keeps being knocked back\nbecause the window is closed)\n\nMaybe this time. This time. This time.\n\nThis time! This time! This...\n\n\nDrapes!\n\n(Barry taps the glass. He doesn't understand what it is)\nThat is diabolical.\n\nKEN:\n\nIt's fantastic. It's got all my special\n\nskills, even my top-ten favorite movies.\n\nANDY:\n\nWhat's number one? Star Wars?\n\nKEN:\n\nNah, | don't go for that...\n\n(Ken makes finger guns and makes ''pew pew pew'' sounds and then stops)\n\n\n...kind of stuff.\n\nBARRY:\n\nNo wonder we shouldn't talk to them.\nThey're out of their minds.\n\nKEN:\n\nWhen | leave a job interview, they're\nflabbergasted, can't believe what | say.\nBARRY:\n\n(Looking at the light on the ceiling)\nThere's the sun. Maybe that's a way out.\n(Starts flying towards the lightbulb)\n\n\n| don't remember the sun\n\nhaving a big 75 on it.\n\n(Barry hits the lightbulb and falls into the dip on the table that the\nhumans are sitting at)\n\nKEN:\n\n\n| predicted global warming.\n\n\n| could feel it getting hotter.\n\nAt first | thought it was just me.\n\n(Andy dips a chip into the bowl and scoops up some dip with Barry on it and\nis about to put it in his mouth)\n\n\nWait! Stop! Bee!\n(Andy drops the chip with Barry in fear and backs away. All the humans\nfreak out)\n\n\nStand back. These are winter boots.\n\n(Ken has winter boots on his hands and he is about to smash the bee but\nVanessa saves him last second)\n\nVANESSA:\n\nWait!\n\n\nDon't kill him!\n\n(Vanessa puts Barry in a glass to protect him)\nKEN:\n\nYou know I'm allergic to them!\n\nThis thing could kill me!\n\nVANESSA:\n\nWhy does his life have\n\nless value than yours?\n\n\nKEN:\n\nWhy does his life have any less value\n\nthan mine? Is that your statement?\n\nVANESSA:\n\nI'm just saying all life has value. You\n\ndon't know what he's capable of feeling.\n\n(Vanessa picks up Ken's brochure and puts it under the glass so she can\ncarry Barry back to the window. Barry looks at Vanessa in amazement)\nKEN:\n\n\nMy brochure!\n\nVANESSA:\n\nThere you go, little guy.\n\n(Vanessa opens the window and lets Barry out but Barry stays back and is\nstill shocked that a human saved his life)\nKEN:\n\nI'm not scared of him.\n\nIt's an allergic thing.\n\nVANESSA:\n\nPut that on your resume brochure.\n\nKEN:\n\nMy whole face could puff up.\n\nANDY:\n\nMake it one of your special skills.\n\nKEN:\n\nKnocking someone out\n\nis also a special skill.\n\n(Ken walks to the door)\n\nRight. Bye, Vanessa. Thanks.\n\n\n- Vanessa, next week? Yogurt night?\nVANESSA:\n- Sure, Ken. You know, whatever.\n\n\n(Vanessa tries to close door)\n\n\n- You could put carob chips on there.\nVANESSA:\n\n- Bye.\n\n(Closes door but Ken opens it again)\nKEN:\n\n- Supposed to be less calories.\n\n\nVANESSA:\n\n\n- Bye.\n\n(Closes door)\n\n(Fast forward to the next day, Barry is still inside the house. He flies\ninto the kitchen where Vanessa is doing dishes)\n\nBARRY==\n\n(Talking to himself)\n\n| gotta say something.\n\n\nShe saved my life.\n| gotta say something.\n\n\nAll right, here it goes.\n(Turns back)\n\nNah.\n\nWhat would | say?\n\n\n| could really get in trouble.\n\n\nIt's a bee law.\nYou're not supposed to talk to a human.\n\n\n| can't believe I'm doing this.\n\n\nI've got to.\n(Barry disguises himself as a character on a food can as Vanessa walks by\nagain)\n\n\nOh, | can't do it. Come on!\nNo. Yes. No.\n\n\nDo it. | can't.\n\n\nHow should | start it?\n\n(Barry strikes a pose and wiggles his eyebrows)\n''You like jazz?''\n\nNo, that's no good.\n\n(Vanessa is about to walk past Barry)\n\nHere she comes! Speak, you fool!\n\n\n..-Hi!\n(Vanessa gasps and drops the dishes in fright and notices Barry on the\n\n\ncounter)\n\n\nI'm sorry.\nVANESSA:\n\n- You're talking.\nBARRY:\n\n- Yes, | know.\nVANESSA:\n(Pointing at Barry)\nYou're talking!\nBARRY:\n\nI'm so sorry.\nVANESSA:\n\nNo, it's OK. It's fine.\n| know I'm dreaming.\n\n\nBut | don't recall going to bed.\nBARRY:\n\nWell, I'm sure this\n\nis very disconcerting.\nVANESSA:\n\nThis is a bit of a surprise to me.\n| mean, you're a bee!\n\n\nBARRY:\n\nlam. And I'm not supposed\n\nto be doing this,\n\n(Pointing to the living room where Ken tried to kill him last night)\nbut they were all trying to kill me.\n\n\nAnd if it wasn't for you...\n\n\n| had to thank you.\nIt's just how | was raised.\n(Vanessa stabs her hand with a fork to test whether she's dreaming or not)\n\n\nThat was a little weird.\nVANESSA:\n\n- I'm talking with a bee.\nBARRY:\n\n- Yeah.\n\nVANESSA:\n\nI'm talking to a bee.\n\nAnd the bee is talking to me!\n\n\nBARRY:\n\n| just want to say I'm grateful.\nI'll leave now.\n\n(Barry turns to leave)\nVANESSA:\n\n- Wait! How did you learn to do that?\nBARRY:\n\n(Flying back)\n\n- What?\n\nVANESSA:\n\nThe talking...thing.\n\nBARRY:\n\n\nSame way you did, | guess.\n\n''Mama, Dada, honey.'' You pick it up.\nVANESSA:\n\n- That's very funny.\n\nBARRY:\n\n- Yeah.\n\n\nBees are funny. If we didn't laugh,\nwe'd cry with what we have to deal with.\n\n\nAnyway...\nVANESSA:\nCan l...\n\n\n...get you something?\n\nBARRY:\n\n- Like what?\n\nVANESSA:\n\n| don't know. | mean...\n\n| don't know. Coffee?\n\nBARRY:\n\n| don't want to put you out.\nVANESSA:\n\nIt's no trouble. It takes two minutes.\n\n\n- It's just coffee.\n\nBARRY:\n\n- | hate to impose.\n\n(Vanessa starts making coffee)\nVANESSA:\n\n- Don't be ridiculous!\n\n\nBARRY:\n\n- Actually, | would love a cup.\nVANESSA:\n\nHey, you want rum cake?\nBARRY:\n\n- | shouldn't.\n\nVANESSA:\n\n- Have some.\n\nBARRY:\n\n- No, | can't.\n\nVANESSA:\n\n- Come on!\n\nBARRY:\n\nI'm trying to lose a couple micrograms.\nVANESSA:\n\n- Where?\n\nBARRY:\n\n- These stripes don't help.\nVANESSA:\n\nYou look great!\n\nBARRY:\n\n| don't know if you know\nanything about fashion.\n\n\nAre you all right?\n\nVANESSA:\n\n(Pouring coffee on the floor and missing the cup completely)\n\nNo.\n\n(Flash forward in time. Barry and Vanessa are sitting together at a table\non top of the apartment building drinking coffee)\n\n\nBARRY==\nHe's making the tie in the cab\nas they're flying up Madison.\n\n\nHe finally gets there.\n\n\nHe runs up the steps into the church.\nThe wedding is on.\n\n\nAnd he says, ''Watermelon?\n| thought you said Guatemalan.\n\n\nWhy would | marry a watermelon?''\n\n(Barry laughs but Vanessa looks confused)\nVANESSA:\n\nIs that a bee joke?\n\nBARRY:\n\nThat's the kind of stuff we do.\n\nVANESSA:\n\nYeah, different.\n\n\nSo, what are you gonna do, Barry?\n\n(Barry stands on top of a sugar cube floating in his coffee and paddles it\naround with a straw like it's a gondola)\n\nBARRY:\n\nAbout work? | don't know.\n\n\n| want to do my part for the hive,\nbut | can't do it the way they want.\nVANESSA:\n\n| know how you feel.\n\n\nBARRY:\n\n- You do?\nVANESSA:\n- Sure.\n\n\nMy parents wanted me to be a lawyer or\na doctor, but | wanted to be a florist.\nBARRY:\n\n- Really?\n\nVANESSA:\n\n- My only interest is flowers.\n\nBARRY:\n\nOur new queen was just elected\n\nwith that same campaign slogan.\n\n\nAnyway, if you look...\n(Barry points to a tree in the middle of Central Park)\n\n\nThere's my hive right there. See it?\nVANESSA:\n\nYou're in Sheep Meadow!\n\nBARRY:\n\nYes! I'm right off the Turtle Pond!\n\n\nVANESSA:\n\nNo way! | know that area.\n\n| lost a toe ring there once.\n\nBARRY:\n\n- Why do girls put rings on their toes?\nVANESSA:\n\n- Why not?\n\nBARRY:\n\n\n- It's like putting a hat on your knee.\n\nVANESSA:\n\n- Maybe I'll try that.\n\n(A custodian installing a lightbulb looks over at them but to his\nperspective it looks like Vanessa is talking to a cup of coffee on the\ntable)\n\nCUSTODIAN:\n\n- You all right, ma'am?\n\nVANESSA:\n\n- Oh, yeah. Fine.\n\n\nJust having two cups of coffee!\nBARRY:\n\nAnyway, this has been great.\nThanks for the coffee.\n\nVANESSA==\n\nYeah, it's no trouble.\n\nBARRY:\n\nSorry | couldn't finish it. If 1 did,\n\nI'd be up the rest of my life.\n\n(Barry points towards the rum cake)\n\n\nCan | take a piece of this with me?\nVANESSA:\n\nSure! Here, have a crumb.\n(Vanessa hands Barry a crumb but it is still pretty big for Barry)\nBARRY:\n\n- Thanks!\n\nVANESSA:\n\n- Yeah.\n\nBARRY:\n\nAll right. Well, then...\n\n| guess I'll see you around.\n\n\nOr not.\n\nVANESSA:\n\nOK, Barry...\n\nBARRY:\n\nAnd thank you\n\nso much again... for before.\n\nVANESSA:\n\nOh, that? That was nothing.\n\nBARRY:\n\nWell, not nothing, but... Anyway...\n\n(Vanessa and Barry hold hands, but Vanessa has to hold out a finger because\nher hands is to big and Barry holds that)\n\n(The custodian looks over again and it appears Vanessa is laughing at her\ncoffee again. The lightbulb that he was screwing in sparks and he falls off\nthe ladder)\n\n(Fast forward in time and we see two Bee Scientists testing out a parachute\nin a Honex wind tunnel)\n\nBEE SCIENTIST #1:\n\nThis can't possibly work.\n\nBEE SCIENTIST #2:\n\nHe's all set to go.\n\nWe may as well try it.\n\n\nOK, Dave, pull the chute.\n\n(Dave pulls the chute and the wind slams him against the wall and he falls\non his face. The camera pans over and we see Barry and Adam walking\ntogether)\n\nADAM:\n\n- Sounds amazing.\n\nBARRY:\n\n- It was amazing!\n\n\nIt was the scariest,\nhappiest moment of my life.\n\n\nADAM:\nHumans! | can't believe\nyou were with humans!\n\n\nGiant, scary humans!\n\nWhat were they like?\n\nBARRY:\n\nHuge and crazy. They talk crazy.\n\n\nThey eat crazy giant things.\n\nThey drive crazy.\n\nADAM:\n\n- Do they try and kill you, like on TV?\nBARRY:\n\n- Some of them. But some of them don't.\nADAM:\n\n- How'd you get back?\n\nBARRY:\n\n- Poodle.\n\nADAM:\n\nYou did it, and I'm glad. You saw\nwhatever you wanted to see.\n\n\nYou had your ''experience.'' Now you\ncan pick out your job and be normal.\nBARRY:\n\n- Well...\n\nADAM:\n\n- Well?\n\nBARRY:\n\nWell, | met someone.\n\n\nADAM:\nYou did? Was she Bee-ish?\n\n\n- A wasp?! Your parents will kill you!\nBARRY:\n\n- No, no, no, not a wasp.\n\nADAM:\n\n- Spider?\n\nBARRY:\n\n- I'm not attracted to spiders.\n\n\n| know, for everyone else, it's the hottest thing,\nwith the eight legs and all.\n\n\n| can't get by that face.\nADAM:\n\nSo who is she?\n\nBARRY:\n\nShe's... human.\n\nADAM:\n\nNo, no. That's a bee law.\n\n\nYou wouldn't break a bee law.\nBARRY:\n\n- Her name's Vanessa.\n\n(Adam puts his head in his hands)\nADAM:\n\n- Oh, boy.\n\nBARRY==\n\nShe's so nice. And she's a florist!\nADAM:\n\nOh, no! You're dating a human florist!\n\n\nBARRY:\n\nWe're not dating.\n\nADAM:\n\nYou're flying outside the hive, talking\nto humans that attack our homes\n\n\nwith power washers and M-80s!\nThat's one-eighth a stick of dynamite!\nBARRY:\n\nShe saved my life!\n\nAnd she understands me.\n\nADAM:\n\nThis is over!\n\nBARRY:\n\nEat this.\n\n(Barry gives Adam a piece of the crumb that he got from Vanessa. Adam eats\nit)\n\nADAM:\n\n(Adam's tone changes)\n\nThis is not over! What was that?\nBARRY:\n\n- They call it a crumb.\n\nADAM:\n\n- It was so stingin' stripey!\nBARRY:\n\nAnd that's not what they eat.\nThat's what falls off what they eat!\n\n\n- You know what a Cinnabon is?\n\nADAM:\n\n- No.\n\n(Adam opens a door behind him and he pulls Barry in)\n\n\nBARRY:\n\nIt's bread and cinnamon and frosting.\nADAM:\n\nBe quiet!\n\nBARRY:\n\nThey heat it up...\n\nADAM:\n\nSit down!\n\n(Adam forces Barry to sit down)\nBARRY:\n\n(Still rambling about Cinnabons)\n\n... really hot!\n\n(Adam grabs Barry by the shoulders)\nADAM:\n\n- Listen to me!\n\n\nWe are not them! We're us.\nThere's us and there's them!\nBARRY==\n\nYes, but who can deny\n\nthe heart that is yearning?\nADAM:\n\nThere's no yearning.\n\nStop yearning. Listen to me!\n\n\nYou have got to start thinking bee,\nmy friend. Thinking bee!\n\nBARRY:\n\n- Thinking bee.\n\nWORKER BEE:\n\n- Thinking bee.\n\nWORKER BEES AND ADAM:\nThinking bee! Thinking bee!\n\n\nThinking bee! Thinking bee!\n\n(Flash forward in time; Barry is laying on a raft in a pool full of honey.\nHe is wearing sunglasses)\n\nJANET:\n\nThere he is. He's in the pool.\n\nMARTIN:\n\nYou know what your problem is, Barry?\n\n(Barry pulls down his sunglasses and he looks annoyed)\n\nBARRY:\n\n(Sarcastic)\n\n\n| gotta start thinking bee?\n\nJANET:\n\nHow much longer will this go on?\nMARTIN:\n\nIt's been three days!\n\nWhy aren't you working?\n\n(Puts sunglasses back on)\n\nBARRY:\n\nI've got a lot of big life decisions\n\nto think about.\n\nMARTIN:\n\nWhat life? You have no life!\n\nYou have no job. You're barely a bee!\nJANET:\n\nWould it kill you\n\nto make a little honey?\n\n(Barry rolls off the raft and sinks into the honey pool)\n\n\nBarry, come out.\nYour father's talking to you.\n\n\nMartin, would you talk to him?\nMARTIN:\n\n\nBarry, I'm talking to you!\n\n(Barry keeps sinking into the honey until he is suddenly in Central Park\nhaving a picnic with Vanessa)\n\n(Barry has a cup of honey and he clinks his glass with Vanessas. Suddenly a\nmosquito lands on Vanessa and she slaps it, killing it. They both gasp but\nthen burst out laughing)\n\nVANESSA:\n\nYou coming?\n\n(The camera pans over and Vanessa is climbing into a small yellow airplane)\nBARRY:\n\nGot everything?\n\nVANESSA:\n\nAll set!\n\nBARRY:\n\nGo ahead. I'll catch up.\n\n(Vanessa lifts off and flies ahead)\n\nVANESSA:\n\nDon't be too long.\n\n(Barry catches up with Vanessa and he sticks out his arms like ana irplane.\nHe rolls from side to side, and Vanessa copies him with the airplane)\n\n\nVANESSA:\n\nWatch this!\n\n(Barry stays back and watches as Vanessa draws a heart in the air using\npink smoke from the plane, but on the last loop-the-loop she suddenly\ncrashes into a mountain and the plane explodes. The destroyed plane falls\ninto some rocks and explodes a second time)\n\nBARRY:\n\nVanessal\n\n(As Barry is yelling his mouth fills with honey and he wakes up,\ndiscovering that he was just day dreaming. He slowly sinks back into the\nhoney pool)\n\nMARTIN:\n\n- We're still here.\n\n\nJANET:\n- | told you not to yell at him.\n\n\nHe doesn't respond to yelling!\n\n\nMARTIN:\n\n- Then why yell at me?\nJANET:\n\n- Because you don't listen!\nMARTIN:\n\nI'm not listening to this.\nBARRY:\n\nSorry, I've gotta go.\nMARTIN:\n\n- Where are you going?\nBARRY:\n\n- I'm meeting a friend.\nJANET:\n\nA girl? Is this why you can't decide?\nBARRY:\n\nBye.\n\n\n(Barry flies out the door and Martin shakes his head)\n\n\nJANET==\n\n| just hope she's Bee-ish.\n\n(Fast forward in time and Barry is sitting on Vanessa's shoulder and she is\nclosing up her shop)\n\nBARRY:\n\nThey have a huge parade\n\nof flowers every year in Pasadena?\n\nVANESSA:\n\n\nTo be in the Tournament of Roses,\nthat's every florist's dream!\n\n\nUp on a float, surrounded\n\nby flowers, crowds cheering.\nBARRY:\n\nA tournament. Do the roses\ncompete in athletic events?\nVANESSA:\n\nNo. All right, I've got one.\n\nHow come you don't fly everywhere?\nBARRY:\n\nIt's exhausting. Why don't you\n\nrun everywhere? It's faster.\nVANESSA:\n\nYeah, OK, | see, | see.\n\nAll right, your turn.\n\nBARRY:\n\nTiVo. You can just freeze live TV?\nThat's insane!\n\nVANESSA:\n\nYou don't have that?\n\nBARRY:\n\nWe have Hivo, but it's a disease.\nIt's a horrible, horrible disease.\nVANESSA:\n\nOh, my.\n\n(A human walks by and Barry narrowly avoids him)\nPASSERBY:\n\nDumb bees!\n\nVANESSA:\n\nYou must want to sting all those jerks.\nBARRY:\n\nWe try not to sting.\n\n\nIt's usually fatal for us.\n\nVANESSA:\n\nSo you have to watch your temper\n(They walk into a store)\n\nBARRY:\n\nVery carefully.\n\nYou kick a wall, take a walk,\n\n\nwrite an angry letter and throw it out.\nWork through it like any emotion:\n\n\nAnger, jealousy, lust.\n\n(Suddenly an employee(Hector) hits Barry off of Vanessa's shoulder. Hector\nthinks he's saving Vanessa)\n\nVANESSA:\n\n(To Barry)\n\nOh, my goodness! Are you OK?\n\n(Barry is getting up off the floor)\n\nBARRY:\n\nYeah.\n\nVANESSA:\n\n(To Hector)\n\n- What is wrong with you?!\n\nHECTOR:\n\n(Confused)\n\n- It's a bug.\n\nVANESSA:\n\nHe's not bothering anybody.\n\nGet out of here, you creep!\n\n(Vanessa hits Hector across the face with the magazine he had and then hits\nhim in the head. Hector backs away covering his head)\nBarry:\n\nWhat was that? A Pic 'N' Save circular?\n\n(Vanessa sets Barry back on her shoulder)\n\n\nVANESSA:\n\nYeah, it was. How did you know?\n\nBARRY:\n\nIt felt like about 10 pages.\n\nSeventy-five is pretty much our limit.\n\nVANESSA:\n\nYou've really got that\n\ndown to a science.\n\nBARRY:\n\n- Oh, we have to. | lost a cousin to Italian Vogue.\nVANESSA:\n\n- I'll bet.\n\n(Barry looks to his right and notices there is honey for sale in the aisle)\nBARRY:\n\nWhat in the name\n\nof Mighty Hercules is this?\n\n(Barry looks at all the brands of honey, shocked)\n\n\nHow did this get here?\nCute Bee, Golden Blossom,\n\n\nRay Liotta Private Select?\n\n(Barry puts his hands up and slowly turns around, a look of disgust on his\nface)\n\nVANESSA:\n\n- Is he that actor?\n\nBARRY:\n\n- | never heard of him.\n\n\n- Why is this here?\nVANESSA:\n\n- For people. We eat it.\nBARRY:\n\n\nYou don't have\n\nenough food of your own?!\n(Hector looks back and notices that Vanessa is talking to Barry)\nVANESSA:\n\n- Well, yes.\n\nBARRY:\n\n- How do you get it?\nVANESSA:\n\n- Bees make it.\n\nBARRY:\n\n- | Know who makes it!\n\n\nAnd it's hard to make it!\n\n\nThere's heating, cooling, stirring.\nYou need a whole Krelman thing!\nVANESSA:\n\n- It's organic.\n\nBARRY:\n\n- It's our-ganic!\n\nVANESSA:\n\nIt's just honey, Barry.\n\nBARRY:\n\nJust what?!\n\n\nBees don't know about this!\nThis is stealing! A lot of stealing!\n\n\nYou've taken our homes, schools,\nhospitals! This is all we have!\n\n\nAnd it's on sale?!\nI'm getting to the bottom of this.\n\n\nI'm getting to the bottom\n\nof all of this!\n\n(Flash forward in time; Barry paints his face with black strikes like a\nsoldier and sneaks into the storage section of the store)\n\n(Two men, including Hector, are loading boxes into some trucks)\n\n\nSUPERMARKET EMPLOYEE==\nHey, Hector.\n\n\n- You almost done?\n\nHECTOR:\n\n- Almost.\n\n(Barry takes a step to peak around the corner)\n(Whispering)\n\nHe is here. | sense it.\n\n\nWell, | guess I'll go home now\n(Hector pretends to walk away by walking in place and speaking loudly)\n\n\nand just leave this nice honey out,\nwith no one around.\n\nBARRY:\n\nYou're busted, box boy!\nHECTOR:\n\n| knew | heard something!\n\nSo you can talk!\n\nBARRY:\n\nI can talk.\n\nAnd now you'll start talking!\n\n\nWhere you getting the sweet stuff?\n\n\nWho's your supplier?\nHECTOR:\n\n| don't understand.\n\n| thought we were friends.\n\n\nThe last thing we want\n\nto do is upset bees!\n\n(Hector takes a thumbtack out of the board behind him and sword-fights\nBarry. Barry is using his stinger like a sword)\n\n\nYou're too late! It's ours now!\n\nBARRY:\n\nYou, sir, have crossed\n\nthe wrong sword!\n\nHECTOR:\n\nYou, sir, will be lunch\n\nfor my iguana, Ignacio!\n\n(Barry hits the thumbtack out of Hectors hand and Hector surrenders)\nBarry:\n\nWhere is the honey coming from?\n\n\nTell me where!\n\nHECTOR:\n\n(Pointing to leaving truck)\n\nHoney Farms! It comes from Honey Farms!\n\n(Barry chases after the truck but it is getting away. He flies onto a\nbicyclists’ backpack and he catches up to the truck)\n\nCAR DRIVER:\n\n(To bicyclist)\n\nCrazy person!\n\n(Barry flies off and lands on the windshield of the Honey farms truck.\nBarry looks around and sees dead bugs splattered everywhere)\nBARRY:\n\nWhat horrible thing has happened here?\n\n\nThese faces, they never knew\nwhat hit them. And now\n\n\nthey're on the road to nowhere!\n\n(Barry hears a sudden whisper)\n\n(Barry looks up and sees Mooseblood, a mosquito playing dead)\nMOOSEBLOOD:\n\nJust keep still.\n\nBARRY:\n\nWhat? You're not dead?\n\nMOOSEBLOOD:\n\nDo | look dead? They will wipe anything\n\nthat moves. Where you headed?\n\n\nBARRY:\n\nTo Honey Farms.\n\n| am onto something huge here.\n\nMOOSEBLOOD:\n\nI'm going to Alaska. Moose blood,\n\ncrazy stuff. Blows your head off!\n\nANOTHER BUG PLAYING DEAD:\n\nI'm going to Tacoma.\n\n(Barry looks at another bug)\n\nBARRY:\n\n- And you?\n\nMOOSEBLOOD:\n\n- He really is dead.\n\nBARRY:\n\nAll right.\n\n(Another bug hits the windshield and the drivers notice. They activate the\nwindshield wipers)\n\nMOOSEBLOOD==\n\nUh-oh!\n\n(The windshield wipers are slowly sliding over the dead bugs and wiping\n\n\nthem off)\nBARRY:\n\n- What is that?!\nMOOSEBLOOD:\n- Oh, no!\n\n\n- A wiper! Triple blade!\n\nBARRY:\n\n- Triple blade?\n\nMOOSEBLOOD:\n\nJump on! It's your only chance, bee!\n\n(Mooseblood and Barry grab onto the wiper and they hold on as it wipes the\nwindshield)\n\nWhy does everything have\n\nto be so doggone clean?!\n\n\nHow much do you people need to see?!\n(Bangs on windshield)\n\n\nOpen your eyes!\n\nStick your head out the window!\nRADIO IN TRUCK:\n\nFrom NPR News in Washington,\n\n\nI'm Carl Kasell.\n\nMOOSEBLOOD:\n\nBut don't kill no more bugs!\n\n(Mooseblood and Barry are washed off by the wipr fluid)\nMOOSEBLOOD:\n\n- Bee!\n\nBARRY:\n\n- Moose blood guy!!\n\n(Barry starts screaming as he hangs onto the antenna)\n\n(Suddenly it is revealed that a water bug is also hanging on the antenna.\n\n\nThere is a pause and then Barry and the water bug both start screaming)\nTRUCK DRIVER:\n\n- You hear something?\n\nGUY IN TRUCK:\n\n- Like what?\n\nTRUCK DRIVER:\n\nLike tiny screaming.\n\nGUY IN TRUCK:\n\nTurn off the radio.\n\n(The antenna starts to lower until it gets to low and sinks into the truck.\nThe water bug flies off and Barry is forced to let go and he is blown away.\nHe luckily lands inside a horn on top of the truck where he finds\nMooseblood, who was blown into the same place)\n\nMOOSEBLOOD:\n\nWhassup, bee boy?\n\nBARRY:\n\nHey, Blood.\n\n(Fast forward in time and we see that Barry is deep in conversation with\nMooseblood. They have been sitting in this truck for a while)\n\nBARRY:\n\n... Just a row of honey jars,\n\nas far as the eye could see.\n\nMOOSEBLOOD:\n\nWow!\n\nBARRY:\n\n| assume wherever this truck goes\n\nis where they're getting it.\n\n\n| mean, that honey's ours.\nMOOSEBLOOD:\n\n- Bees hang tight.\nBARRY:\n\n\n- We're all jammed in.\n\n\nIt's a close community.\nMOOSEBLOOD:\n\nNot us, man. We on our own.\nEvery mosquito on his own.\nBARRY:\n\n- What if you get in trouble?\nMOOSEBLOOD:\n\n- You a mosquito, you in trouble.\n\n\nNobody likes us. They just smack.\nSee a mosquito, smack, smack!\nBARRY:\n\nAt least you're out in the world.\nYou must meet girls.\nMOOSEBLOOD:\n\nMosquito girls try to trade up,\n\nget with a moth, dragonfly.\n\n\nMosquito girl don't want no mosquito.\n(An ambulance passes by and it has a blood donation sign on it)\nYou got to be kidding me!\n\n\nMooseblood's about to leave\n\nthe building! So long, bee!\n\n(Mooseblood leaves and flies onto the window of the ambulance where there\nare other mosquito's hanging out)\n\n\n- Hey, guys!\nOTHER MOSQUITO:\n- Mooseblood!\n\n\nMOOSEBLOOD:\n\n| knew I'd catch y'all down here.\n\nDid you bring your crazy straw?\n(The truck goes out of view and Barry notices that the truck he's on is\npulling into a camp of some sort)\nTRUCK DRIVER:\n\nWe throw it in jars, slap a label on it,\nand it's pretty much pure profit.\n(Barry flies out)\n\nBARRY:\n\nWhat is this place?\n\n\nBEEKEEPER 1#:\n\nA bee's got a brain\nthe size of a pinhead.\nBEEKEEPER #2:\nThey are pinheads!\n\n\nPinhead.\n\n\n- Check out the new smoker.\nBEEKEEPER #1:\n- Oh, sweet. That's the one you want.\n\n\nThe Thomas 3000!\n\nBARRY:\n\nSmoker?\n\nBEEKEEPER #1:\n\nNinety puffs a minute, semi-automatic.\nTwice the nicotine, all the tar.\n\n\nA couple breaths of this\nknocks them right out.\n\n\nBEEKEEPER #2:\n\nThey make the honey,\n\nand we make the money.\n\nBARRY:\n\n''They make the honey,\n\nand we make the money''?\n\n(The Beekeeper sprays hundreds of cheap miniature apartments with the\nsmoker. The bees are fainting or passing out)\n\nOh, my!\n\n\nWhat's going on? Are you OK?\n\n(Barry flies into one of the apartment and helps a Bee couple get off the\nground. They are coughing and its hard for them to stand)\n\nBEE IN APARTMENT:\n\nYeah. It doesn't last too long.\n\nBARRY:\n\nDo you know you're\n\nin a fake hive with fake walls?\n\nBEE IN APPARTMENT:\n\nOur queen was moved here.\n\nWe had no choice.\n\n(The apartment room is completely empty except for a photo on the wall of\n\n\nthe ''queen'' who is obviously a man in women's clothes)\nBARRY:\n\nThis is your queen?\n\nThat's a man in women's clothes!\n\n\nThat's a drag queen!\n\n\nWhat is this?\n\n(Barry flies out and he discovers that there are hundreds of these\nstructures, each housing thousands of Bees)\n\nOh, no!\n\n\nThere's hundreds of them!\n(Barry takes out his camera and takes pictures of these Bee work camps. The\nbeekeepers look very evil in these depictions)\n\n\nBee honey.\n\n\nOur honey is being brazenly stolen\non a massive scale!\n\n\nThis is worse than anything bears\nhave done! | intend to do something.\n(Flash forward in time and Barry is showing these pictures to his parents)\nJANET:\n\nOh, Barry, stop.\n\nMARTIN:\n\nWho told you humans are taking\n\nour honey? That's a rumor.\n\nBARRY:\n\nDo these look like rumors?\n\n(Holds up the pictures)\n\nUNCLE CARL:\n\nThat's a conspiracy theory.\n\nThese are obviously doctored photos.\nJANET:\n\nHow did you get mixed up in this?\nADAM:\n\nHe's been talking to humans.\nJANET:\n\n- What?\n\nMARTIN:\n\n- Talking to humans?!\n\nADAM:\n\n\nHe has a human girlfriend.\nAnd they make out!\nJANET:\n\nMake out? Barry!\n\n\nBARRY:\n\nWe do not.\n\nADAM:\n\n- You wish you could.\n\nMARTIN:\n\n- Whose side are you on?\n\nBARRY:\n\nThe bees!\n\nUNCLE CARL:\n\n(He has been sitting in the back of the room this entire time)\n| dated a cricket once in San Antonio.\nThose crazy legs kept me up all night.\nJANET:\n\nBarry, this is what you want\n\nto do with your life?\n\nBARRY:\n\n| want to do it for all our lives.\n\nNobody works harder than bees!\n\n\nDad, | remember you\ncoming home so overworked\n\n\nyour hands were still stirring.\n\nYou couldn't stop.\n\nJANET:\n\n| remember that.\n\nBARRY:\n\nWhat right do they have to our honey?\n\n\nWe live on two cups a year. They put it\nin lip balm for no reason whatsoever!\n\n\nADAM:\n\nEven if it's true, what can one bee do?\nBARRY:\n\nSting them where it really hurts.\nMARTIN:\n\nIn the face! The eye!\n\n\n- That would hurt.\n\nBARRY:\n\n- No.\n\nMARTIN:\n\nUp the nose? That's a killer.\n\nBARRY:\n\nThere's only one place you can sting\nthe humans, one place where it matters.\n(Flash forward a bit in time and we are watching the Bee News)\nBEE NEWS NARRATOR:\n\nHive at Five, the hive's only\n\nfull-hour action news source.\n\nBEE PROTESTOR:\n\nNo more bee beards!\n\nBEE NEWS NARRATOR:\n\nWith Bob Bumble at the anchor desk.\n\n\nWeather with Storm Stinger.\nSports with Buzz Larvi.\n\n\nAnd Jeanette Chung.\n\nBOB BUMBLE:\n\n- Good evening. I'm Bob Bumble.\nJEANETTE CHUNG:\n\n\n- And I'm Jeanette Chung.\nBOB BUMBLE:\nA tri-county bee, Barry Benson,\n\n\nintends to sue the human race\nfor stealing our honey,\n\n\npackaging it and profiting\n\nfrom it illegally!\n\nJEANETTE CHUNG:\n\nTomorrow night on Bee Larry King,\n\n\nwe'll have three former queens here in\nour studio, discussing their new book,\n\n\nClassy Ladies,\nout this week on Hexagon.\n(The scene changes to an interview on the news with Bee version of Larry\n\n\nKing and Barry)\nBEE LARRY KING:\nTonight we're talking to Barry Benson.\n\n\nDid you ever think, ''I'm a kid\n\nfrom the hive. | can't do this''?\nBARRY:\n\nBees have never been afraid\nto change the world.\n\n\nWhat about Bee Columbus?\n\nBee Gandhi? Bejesus?\n\nBEE LARRY KING:\n\nWhere I'm from, we'd never sue humans.\n\n\nWe were thinking\n\nof stickball or candy stores.\nBARRY:\n\nHow old are you?\n\nBEE LARRY KING:\n\nThe bee community\n\nis supporting you in this case,\n\n\nwhich will be the trial\n\nof the bee century.\n\nBARRY:\n\nYou know, they have a Larry King\n\nin the human world too.\n\nBEE LARRY KING:\n\nIt's a common name. Next week...\nBARRY:\n\nHe looks like you and has a show\n\nand suspenders and colored dots...\nBEE LARRY KING:\n\nNext week...\n\nBARRY:\n\nGlasses, quotes on the bottom from the\nguest even though you just heard 'em.\nBEE LARRY KING:\n\nBear Week next week!\n\nThey're scary, hairy and here, live.\n(Bee Larry King gets annoyed and flies away offscreen)\nBARRY:\n\n\nAlways leans forward, pointy shoulders,\n\nsquinty eyes, very Jewish.\n\n(Flash forward in time. We see Vanessa enter and Ken enters behind her.\nThey are arguing)\n\n\nKEN:\n\nIn tennis, you attack\n\nat the point of weakness!\n\nVANESSA:\n\nIt was my grandmother, Ken. She's 81.\nKEN==\n\nHoney, her backhand's a joke!\n\nI'm not gonna take advantage of that?\nBARRY:\n\n(To Ken)\n\nQuiet, please.\n\nActual work going on here.\n\nKEN:\n\n(Pointing at Barry)\n\n- Is that that same bee?\n\nVANESSA:\n\n- Yes, it is!\n\n\nI'm helping him sue the human race.\nBARRY:\n\n- Hello.\n\nKEN:\n\n- Hello, bee.\n\nVANESSA:\n\nThis is Ken.\n\nBARRY:\n\n(Recalling the ''Winter Boots'' incident earlier)\nYeah, | remember you. Timberland, size\nten and a half. Vibram sole, | believe.\nKEN:\n\n(To Vanessa)\n\nWhy does he talk again?\n\nVANESSA:\n\n\nListen, you better go\n\n‘cause we're really busy working.\nKEN:\n\nBut it's our yogurt night!\nVANESSA:\n\n\n(Holding door open for Ken)\nBye-bye.\n\nKEN:\n\n(Yelling)\n\nWhy is yogurt night so difficult?!\n(Ken leaves and Vanessa walks over to Barry. His workplace is a mess)\nVANESSA:\n\nYou poor thing.\n\nYou two have been at this for hours!\nBARRY:\n\nYes, and Adam here\n\nhas been a huge help.\n\nADAM:\n\n- Frosting...\n\n- How many sugars?\n\n==BARRY==\n\nJust one. | try not\n\nto use the competition.\n\n\nSo why are you helping me?\nVANESSA:\nBees have good qualities.\n\n\nAnd it takes my mind off the shop.\n\n\nInstead of flowers, people\nare giving balloon bouquets now.\nBARRY:\n\n\nThose are great, if you're three.\nVANESSA:\n\nAnd artificial flowers.\n\nBARRY:\n\n- Oh, those just get me psychotic!\nVANESSA:\n\n- Yeah, me too.\n\n\nBARRY:\n\nBent stingers, pointless pollination.\nADAM:\n\nBees must hate those fake things!\n\n\nNothing worse\nthan a daffodil that's had work done.\n\n\nMaybe this could make up\n\nfor it a little bit.\n\nVANESSA:\n\n- This lawsuit's a pretty big deal.\nBARRY:\n\n- | guess.\n\nADAM:\n\nYou sure you want to go through with it?\nBARRY:\n\nAm | sure? When I'm done with\nthe humans, they won't be able\n\n\nto say, ''Honey, I'm home,''\nwithout paying a royalty!\n(Flash forward in time and we are watching the human news. The camera shows\n\n\na crowd outside a courthouse)\nNEWS REPORTER:\n\nIt's an incredible scene\n\nhere in downtown Manhattan,\n\n\nwhere the world anxiously waits,\nbecause for the first time in history,\n\n\nwe will hear for ourselves\n\nif a honeybee can actually speak.\n\n(We are no longer watching through a news camera)\nADAM:\n\nWhat have we gotten into here, Barry?\n\nBARRY:\n\nIt's pretty big, isn't it?\n\nADAM==\n\n(Looking at the hundreds of people around the courthouse)\n| can't believe how many humans\n\ndon't work during the day.\n\nBARRY:\n\nYou think billion-dollar multinational\n\nfood companies have good lawyers?\n\nSECURITY GUARD:\n\nEverybody needs to stay\n\nbehind the barricade.\n\n(A limousine drives up and a fat man,Layton Montgomery, a honey industry\nowner gets out and walks past Barry)\n\n\nADAM:\n\n- What's the matter?\n\nBARRY:\n\n- | don't know, | just got a chill.\n\n(Fast forward in time and everyone is in the court)\nMONTGOMERY:\n\nWell, if it isn't the bee team.\n\n\n(To Honey Industry lawyers)\nYou boys work on this?\nMAN:\n\nAll rise! The Honorable\nJudge Bumbleton presiding.\nJUDGE BUMBLETON:\n\nAll right. Case number 4475,\n\n\nSuperior Court of New York,\nBarry Bee Benson v. the Honey Industry\n\n\nis now in session.\n\n\nMr. Montgomery, you're representing\n\nthe five food companies collectively?\n\nMONTGOMERY:\n\nA privilege.\n\nJUDGE BUMBLETON:\n\nMr. Benson... you're representing\n\nall the bees of the world?\n\n(Everyone looks closely, they are waiting to see if a Bee can really talk)\n(Barry makes several buzzing sounds to sound like a Bee)\nBARRY:\n\nI'm kidding. Yes, Your Honor,\n\nwe're ready to proceed.\n\nJUDGE BUMBLBETON:\n\nMr. Montgomery,\n\nyour opening statement, please.\n\nMONTGOMERY:\n\nLadies and gentlemen of the jury,\n\n\nmy grandmother was a simple woman.\n\n\nBorn on a farm, she believed\nit was man's divine right\n\n\nto benefit from the bounty\nof nature God put before us.\n\n\nIf we lived in the topsy-turvy world\nMr. Benson imagines,\n\n\njust think of what would it mean.\n\n\n| would have to negotiate\nwith the silkworm\n\n\nfor the elastic in my britches!\n\n\nTalking bee!\n(Montgomery walks over and looks closely at Barry)\n\n\nHow do we know this isn't some sort of\n\n\nholographic motion-picture-capture\nHollywood wizardry?\n\n\nThey could be using laser beams!\n\n\nRobotics! Ventriloquism!\nCloning! For all we know,\n\n\nhe could be on steroids!\nJUDGE BUMBLETON:\nMr. Benson?\n\n\nBARRY:\nLadies and gentlemen,\nthere's no trickery here.\n\n\nI'm just an ordinary bee.\nHoney's pretty important to me.\n\n\nIt's important to all bees.\nWe invented it!\n\n\nWe make it. And we protect it\nwith our lives.\n\n\nUnfortunately, there are\nsome people in this room\n\n\nwho think they can take it from us\n\n\n‘cause we're the little guys!\nI'm hoping that, after this is all over,\n\n\nyou'll see how, by taking our honey,\nyou not only take everything we have\n\n\nbut everything we are!\nJANET==\n\n(To Martin)\n\n| wish he'd dress like that\n\nall the time. So nice!\n\nJUDGE BUMBLETON:\n\nCall your first witness.\nBARRY:\n\nSo, Mr. Klauss Vanderhayden\n\n\nof Honey Farms, big company you have.\nKLAUSS VANDERHAYDEN:\n| suppose so.\n\nBARRY:\n\n| see you also own\nHoneyburton and Honron!\nKLAUSS:\n\nYes, they provide beekeepers\nfor our farms.\n\nBARRY:\n\nBeekeeper. | find that\n\nto be a very disturbing term.\n\n\n| don't imagine you employ\nany bee-free-ers, do you?\nKLAUSS:\n\n(Quietly)\n\n- No.\n\nBARRY:\n\n- | couldn't hear you.\nKLAUSS:\n\n- No.\n\nBARRY:\n\n\n- No.\n\n\nBecause you don't free bees.\nYou keep bees. Not only that,\n\n\nit seems you thought a bear would be\nan appropriate image for a jar of honey.\nKLAUSS:\n\nThey're very lovable creatures.\n\n\nYogi Bear, Fozzie Bear, Build-A-Bear.\n\nBARRY:\n\nYou mean like this?\n\n(The bear from Over The Hedge barges in through the back door and it is\nroaring and standing on its hind legs. It is thrashing its claws and people\nare screaming. It is being held back by a guard who has the bear on a\nchain)\n\n\n(Pointing to the roaring bear)\nBears kill bees!\n\n\nHow'd you like his head crashing\nthrough your living room?!\n\n\nBiting into your couch!\n\nSpitting out your throw pillows!\n\nJUDGE BUMBLETON:\n\nOK, that's enough. Take him away.\n\n(The bear stops roaring and thrashing and walks out)\nBARRY:\n\nSo, Mr. Sting, thank you for being here.\n\nYour name intrigues me.\n\n\n- Where have | heard it before?\n\nMR. STING:\n\n- | was with a band called The Police.\nBARRY:\n\nBut you've never been\n\na police officer, have you?\n\nSTING:\n\nNo, | haven't.\n\nBARRY:\n\n\nNo, you haven't. And so here\nwe have yet another example\n\n\nof bee culture casually\nstolen by a human\n\n\nfor nothing more than\n\na prance-about stage name.\n\nSTING:\n\nOh, please.\n\nBARRY:\n\nHave you ever been stung, Mr. Sting?\n\n\nBecause I'm feeling\na little stung, Sting.\n\n\nOr should | say... Mr. Gordon M. Sumner!\nMONTGOMERY:\n\nThat's not his real name?! You idiots!\nBARRY:\n\nMr. Liotta, first,\n\nbelated congratulations on\n\n\nyour Emmy win for a guest spot\non ER in 2005.\n\nRAY LIOTTA:\n\nThank you. Thank you.\n\nBARRY:\n\n| see from your resume\n\nthat you're devilishly handsome\n\n\nwith a churning inner turmoil\n\n\nthat's ready to blow.\n\nRAY LIOTTA:\n\n| enjoy what | do. Is that a crime?\nBARRY:\n\nNot yet it isn't. But is this\n\nwhat it's come to for you?\n\n\nExploiting tiny, helpless bees\nso you don't\n\n\nhave to rehearse\n\n\nyour part and learn your lines, sir?\nRAY LIOTTA:\n\nWatch it, Benson!\n\n| could blow right now!\n\nBARRY:\n\nThis isn't a goodfella.\n\nThis is a badfella!\n\n(Ray Liotta looses it and tries to grab Barry)\nRAY LIOTTA:\n\nWhy doesn't someone just step on\nthis creep, and we can all go home?!\nJUDGE BUMBLETON:\n\n- Order in this court!\n\nRAY LIOTTA:\n\n- You're all thinking it!\n\n(Judge Bumbleton starts banging her gavel)\nJUDGE BUMBLETON:\n\nOrder! Order, | say!\n\nRAY LIOTTA:\n\n- Say it!\n\nMAN:\n\n\n- Mr. Liotta, please sit down!\n\n(We see a montage of magazines which feature the court case)\n(Flash forward in time and Barry is back home with Vanessa)\nBARRY:\n\n| think it was awfully nice\n\nof that bear to pitch in like that.\n\nVANESSA:\n\n| think the jury's on our side.\n\nBARRY:\n\nAre we doing everything right,you know, legally?\n\nVANESSA:\n\nI'm a florist.\n\nBARRY:\n\nRight. Well, here's to a great team.\n\nVANESSA:\n\nTo a great team!\n\n(Ken walks in from work. He sees Barry and he looks upset when he sees\nBarry clinking his glass with Vanessa)\n\nKEN:\n\nWell, hello.\n\nVANESSA:\n\n- Oh, Ken!\n\n\nBARRY:\n\n- Hello!\n\nVANESSA:\n\n| didn't think you were coming.\n\n\nNo, | was just late.\n\n| tried to call, but...\n\n(Ken holds up his phone and flips it open. The phone has no charge)\n...the battery...\n\nVANESSA:\n\n\n| didn't want all this to go to waste,\n\nso | called Barry. Luckily, he was free.\nKEN:\n\nOh, that was lucky.\n\n(Ken sits down at the table across from Barry and Vanessa leaves the room)\nVANESSA:\n\nThere's a little left.\n\n| could heat it up.\n\nKEN:\n\n(Not taking his eyes off Barry)\n\nYeah, heat it up, sure, whatever.\nBARRY:\n\nSo | hear you're quite a tennis player.\n\n\nI'm not much for the game myself.\n\nThe ball's a little grabby.\n\nKEN:\n\nThat's where | usually sit.\n\nRight...\n\n(Points to where Barry is sitting)\n\nthere.\n\nVANESSA:\n\n(Calling from other room)\n\nKen, Barry was looking at your resume,\n\n\nand he agreed with me that eating with\nchopsticks isn't really a special skill.\nKEN:\n\n(To Barry)\n\nYou think | don't see what you're doing?\nBARRY:\n\n| know how hard it is to find\n\nthe right job. We have that in common.\n\n\nKEN:\n\nDo we?\n\nBARRY:\n\nBees have 100 percent employment,\n\nbut we do jobs like taking the crud out.\n\nKEN:\n\n(Menacingly)\n\nThat's just what\n\n| was thinking about doing.\n\n(Ken reaches for a fork on the table but knocks if on the floor. He goes to\npick it up)\n\nVANESSA:\n\nKen, | let Barry borrow your razor\n\nfor his fuzz. | hope that was all right.\n\n(Ken quickly rises back up after hearing this but hits his head on the\ntable and yells)\n\nBARRY:\n\nI'm going to drain the old stinger.\n\nKEN:\n\nYeah, you do that.\n\n(Barry flies past Ken to get to the bathroom and Ken freaks out, splashing\nsome of the wine he was using to cool his head in his eyes. He yells in\nanger)\n\n(Barry looks at the magazines featuring his victories in court)\n\nBARRY:\n\nLook at that.\n\n(Barry flies into the bathroom)\n\n(He puts his hand on his head but this makes hurts him and makes him even\nmadder. He yells again)\n\n(Barry is washing his hands in the sink but then Ken walks in)\n\nKEN:\n\nYou know, you know I've just about had it\n\n(Closes bathroom door behind him)\n\nwith your little mind games.\n\n(Ken is menacingly rolling up a magazine)\n\nBARRY:\n\n\n(Backing away)\n\n- What's that?\n\nKEN:\n\n- Italian Vogue.\n\nBARRY:\n\nMamma mia, that's a lot of pages.\n\n\nKEN:\n\nIt's a lot of ads.\n\nBARRY:\n\nRemember what Van said, why is\n\nyour life more valuable than mine?\n\nKEN:\n\nThat's funny, | just can't seem to recall that!\n\n(Ken smashes everything off the sink with the magazine and Barry narrowly\nescapes)\n\n(Ken follows Barry around and tries to hit him with the magazine but he\nkeeps missing)\n\n(Ken gets a spray bottle)\n\n\n| think something stinks in here!\n\nBARRY:\n\n(Enjoying the spray)\n\n| love the smell of flowers.\n\n(Ken holds a lighter in front of the spray bottle)\n\nKEN:\n\nHow do you like the smell of flames?!\n\nBARRY:\n\nNot as much.\n\n(Ken fires his make-shift flamethrower but misses Barry, burning the\nbathroom. He torches the whole room but looses his footing and falls into\nthe bathtub. After getting hit in the head by falling objects 3 times he\npicks up the shower head, revealing a Water bug hiding under it)\nWATER BUG:\n\nWater bug! Not taking sides!\n\n\n(Barry gets up out of a pile of bathroom supplies and he is wearing a\nchapstick hat)\n\nBARRY:\n\nKen, I'm wearing a Chapstick hat!\n\nThis is pathetic!\n\n(Ken switches the shower head to lethal)\n\nKEN:\n\nI've got issues!\n\n(Ken sprays Barry with the shower head and he crash lands into the toilet)\n(Ken menacingly looks down into the toilet at Barry)\n\nWell, well, well, a royal flush!\n\nBARRY:\n\n- You're bluffing.\n\nKEN:\n\n- Am |?\n\n\n(flushes toilet)\n\n(Barry grabs a chapstick from the toilet seat and uses it to surf in the\nflushing toilet)\n\nBARRY:\n\nSurf's up, dude!\n\n(Barry flies out of the toilet on the chapstick and sprays Ken's face with\nthe toilet water)\n\n\nEW,Poo water!\n\nBARRY:\n\nThat bowl is gnarly.\n\nKEN:\n\n(Aiming a toilet cleaner at Barry)\n\nExcept for those dirty yellow rings!\n\n(Barry cowers and covers his head and Vanessa runs in and takes the toilet\ncleaner from Ken just before he hits Barry)\nVANESSA:\n\nKenneth! What are you doing?!\n\nKEN==\n\n(Leaning towards Barry)\n\n\nYou know, | don't even like honey!\n\n| don't eat it!\n\nVANESSA:\n\nWe need to talk!\n\n(Vanessa pulls Ken out of the bathroom)\n\n\nHe's just a little bee!\n\n\nAnd he happens to be\n\nthe nicest bee I've met in a long time!\nKEN:\n\nLong time? What are you talking about?!\nAre there other bugs in your life?\nVANESSA:\n\nNo, but there are other things bugging\nme in life. And you're one of them!\n\nKEN:\n\nFine! Talking bees, no yogurt night...\n\n\nMy nerves are fried from riding\non this emotional roller coaster!\nVANESSA:\n\nGoodbye, Ken.\n\n\n(Ken huffs and walks out and slams the door. But suddenly he walks back in\nand stares at Barry)\n\n\nAnd for your information,\n\n| prefer sugar-free, artificial\n\nsweeteners MADE BY MAN!\n\n(Ken leaves again and Vanessa leans in towards Barry)\nVANESSA:\n\nI'm sorry about all that.\n\n(Ken walks back in again)\n\n\nKEN:\n\n| know it's got\n\nan aftertaste! | LIKE IT!\n\n(Ken leaves for the last time)\nVANESSA:\n\n| always felt there was some kind\nof barrier between Ken and me.\n\n\n| couldn't overcome it.\nOh, well.\n\n\nAre you OK for the trial?\n\nBARRY:\n\n| believe Mr. Montgomery\n\nis about out of ideas.\n\n(Flash forward in time and Barry, Adam, and Vanessa are back in court)\nMONTGOMERY--\n\nWe would like to call\n\nMr. Barry Benson Bee to the stand.\nADAM:\n\nGood idea! You can really see why he's\nconsidered one of the best lawyers...\n(Barry stares at Adam)\n\n... Yeah.\n\nLAWYER:\n\nLayton, you've\n\ngotta weave some magic\n\nwith this jury,\n\nor it's gonna be all over.\nMONTGOMERY:\n\nDon't worry. The only thing | have\n\nto do to turn this jury around\n\n\nis to remind them\nof what they don't like about bees.\n(To lawyer)\n\n\n- You got the tweezers?\nLAWYER:\n\n- Are you allergic?\nMONTGOMERY:\n\nOnly to losing, son. Only to losing.\n\n\nMr. Benson Bee, I'll ask you\nwhat | think we'd all like to know.\n\n\nWhat exactly is your relationship\n(Points to Vanessa)\n\n\nto that woman?\nBARRY:\n\nWe're friends.\nMONTGOMERY:\n- Good friends?\nBARRY:\n\n- Yes.\nMONTGOMERY:\nHow good? Do you live together?\nADAM:\n\nWait a minute...\n\n\nMONTGOMERY:\nAre you her little...\n\n\n...bedbug?\n\n(Adam's stinger starts vibrating. He is agitated)\nI've seen a bee documentary or two.\n\nFrom what | understand,\n\n\ndoesn't your queen give birth\n\nto all the bee children?\n\nBARRY:\n\n- Yeah, but...\n\nMONTGOMERY:\n\n(Pointing at Janet and Martin)\n\n- So those aren't your real parents!\n\n\nJANET:\n\n- Oh, Barry...\n\nBARRY:\n\n- Yes, they are!\n\nADAM:\n\nHold me back!\n\n(Vanessa tries to hold Adam back. He wants to sting Montgomery)\nMONTGOMERY:\n\nYou're an illegitimate bee,\n\naren't you, Benson?\n\nADAM:\n\nHe's denouncing bees!\n\nMONTGOMERY:\n\nDon't y'all date your cousins?\n\n(Montgomery leans over on the jury stand and stares at Adam)\nVANESSA:\n\n- Objection!\n\n(Vanessa raises her hand to object but Adam gets free. He flies straight at\nMontgomery)\n\n=ADAM:\n\n- I'm going to pincushion this guy!\n\nBARRY:\n\nAdam, don't! It's what he wants!\n\n(Adam stings Montgomery in the butt and he starts thrashing around)\n\n\nMONTGOMERY:\nOh, I'm hit!!\n\n\nOh, lordy, | am hit!\n\nJUDGE BUMBLETON:\n(Banging gavel)\n\nOrder! Order!\nMONTGOMERY:\n(Overreacting)\n\nThe venom! The venom\n\nis coursing through my veins!\n\n\n| have been felled\nby a winged beast of destruction!\n\n\nYou see? You can't treat them\nlike equals! They're striped savages!\n\n\nStinging's the only thing\n\n\nthey know! It's their way!\n\nBARRY:\n\n- Adam, stay with me.\n\nADAM:\n\n- | can't feel my legs.\n\nMONTGOMERY:\n\n(Overreacting and throwing his body around the room)\nWhat angel of mercy\n\nwill come forward to suck the poison\n\n\nfrom my heaving buttocks?\nJUDGE BUMLBETON:\n| will have order in this court. Order!\n\n\nOrder, please!\n\n(Flash forward in time and we see a human news reporter)\nNEWS REPORTER:\n\nThe case of the honeybees\n\nversus the human race\n\n\ntook a pointed turn against the bees\n\n\nyesterday when one of their legal\nteam stung Layton T. Montgomery.\n(Adam is laying in a hospital bed and Barry flies in to see him)\nBARRY:\n\n- Hey, buddy.\n\nADAM:\n\n- Hey.\n\nBARRY:\n\n- Is there much pain?\n\nADAM:\n\n- Yeah.\n\n\n| blew the whole case, didn't I?\n\nBARRY:\n\nIt doesn't matter. What matters is\n\nyou're alive. You could have died.\n\nADAM:\n\nI'd be better off dead. Look at me.\n\n(A small plastic sword is replaced as Adam's stinger)\n\n\nThey got it from the cafeteria\ndownstairs, in a tuna sandwich.\n\n\nLook, there's\n\na little celery still on it.\n\n(Flicks off the celery and sighs)\nBARRY:\n\nWhat was it like to sting someone?\nADAM:\n\nI can't explain it. It was all...\n\n\nAll adrenaline and then...\nand then ecstasy!\nBARRY:\n\n.-All right.\n\nADAM:\n\nYou think it was all a trap?\nBARRY:\n\nOf course. I'm sorry.\n\n| flew us right into this.\n\n\nWhat were we thinking? Look at us. We're\njust a couple of bugs in this world.\nADAM:\n\nWhat will the humans do to us\n\nif they win?\n\nBARRY:\n\n| don't know.\n\nADAM:\n\n| hear they put the roaches in motels.\nThat doesn't sound so bad.\n\nBARRY:\n\nAdam, they check in,\n\nbut they don't check out!\n\n\nADAM:\n\nOh, my.\n\n(Coughs)\n\nCould you get a nurse\nto close that window?\nBARRY:\n\n- Why?\n\nADAM:\n\n\n- The smoke.\n(We can see that two humans are smoking cigarettes outside)\n\n\nBees don't smoke.\nBARRY:\nRight. Bees don't smoke.\n\n\nBees don't smoke!\nBut some bees are smoking.\n\n\nThat's it! That's our case!\n\nADAM:\n\nIt is? It's not over?\n\nBARRY:\n\nGet dressed. I've gotta go somewhere.\n\n\nGet back to the court and stall.\n\nStall any way you can.\n\n(Flash forward in time and Adam is making a paper boat in the courtroom)\nADAM:\n\nAnd assuming you've done step 29 correctly, you're ready for the tub!\n\n(We see that the jury have each made their own paper boats after being\ntaught how by Adam. They all look confused)\n\nJUDGE BUMBLETON:\n\n\nMr. Flayman.\n\nADAM:\n\nYes? Yes, Your Honor!\n\nJUDGE BUMBLETON:\n\nWhere is the rest of your team?\nADAM:\n\n(Continues stalling)\n\nWell, Your Honor, it's interesting.\n\n\nBees are trained to fly haphazardly,\n\n\nand as a result,\nwe don't make very good time.\n\n\n| actually heard a funny story about...\nMONTGOMERY:\n\nYour Honor,\n\nhaven't these ridiculous bugs\n\n\ntaken up enough\nof this court's valuable time?\n\n\nHow much longer will we allow\nthese absurd shenanigans to go on?\n\n\nThey have presented no compelling\nevidence to support their charges\n\n\nagainst my clients,\nwho run legitimate businesses.\n\n\n| move for a complete dismissal\n\n\nof this entire case!\nJUDGE BUMBLETON:\nMr. Flayman, I'm afraid I'm going\n\n\nto have to consider\n\nMr. Montgomery's motion.\n\nADAM:\n\nBut you can't! We have a terrific case.\nMONTGOMERY:\n\nWhere is your proof?\n\nWhere is the evidence?\n\n\nShow me the smoking gun!\nBARRY:\n\n(Barry flies in through the door)\nHold it, Your Honor!\n\nYou want a smoking gun?\n\n\nHere is your smoking gun.\n(Vanessa walks in holding a bee smoker. She sets it down on the Judge's\npodium)\n\nJUDGE BUMBLETON:\n\nWhat is that?\n\nBARRY:\n\nIt's a bee smoker!\nMONTGOMERY:\n\n(Picks up smoker)\n\nWhat, this?\n\nThis harmless little contraption?\n\n\nThis couldn't hurt a fly,\nlet alone a bee.\n(Montgomery accidentally fires it at the bees in the crowd and they faint\n\n\nand cough)\n\n(Dozens of reporters start taking pictures of the suffering bees)\nBARRY:\n\nLook at what has happened\n\n\nto bees who have never been asked,\n''Smoking or non?''\n\n\nIs this what nature intended for us?\n\n\nTo be forcibly addicted\nto smoke machines\n\n\nand man-made wooden slat work camps?\n\n\nLiving out our lives as honey slaves\n\nto the white man?\n\n(Barry points to the honey industry owners. One of them is an African\nAmerican so he awkwardly separates himself from the others)\nLAWYER:\n\n- What are we gonna do?\n\n- He's playing the species card.\n\nBARRY:\n\nLadies and gentlemen, please,\n\nfree these bees!\n\nADAM AND VANESSA:\n\nFree the bees! Free the bees!\n\nBEES IN CROWD:\n\nFree the bees!\n\nHUMAN JURY:\n\nFree the bees! Free the bees!\n\nJUDGE BUMBLETON:\n\nThe court finds in favor of the bees!\n\n\nBARRY:\n\nVanessa, we won!\n\nVANESSA:\n\n| knew you could do it! High-five!\n\n(Vanessa hits Barry hard because her hand is too big)\n\n\nSorry.\n\nBARRY:\n\n(Overjoyed)\n\nI'm OK! You know what this means?\n\n\nAll the honey\nwill finally belong to the bees.\n\n\nNow we won't have\n\nto work so hard all the time.\nMONTGOMERY:\n\nThis is an unholy perversion\n\nof the balance of nature, Benson.\n\n\nYou'll regret this.\n\n(Montgomery leaves and Barry goes outside the courtroom. Several reporters\nstart asking Barry questions)\nREPORTER 1#:\n\nBarry, how much honey is out there?\nBARRY:\n\nAll right. One at a time.\n\nREPORTER 2#:\n\nBarry, who are you wearing?\nBARRY:\n\nMy sweater is Ralph Lauren,\n\nand | have no pants.\n\n\n(Barry flies outside with the paparazzi and Adam and Vanessa stay back)\nADAM:\n\n(To Vanessa)\n\n- What if Montgomery's right?\n\nVanessa:\n\n- What do you mean?\n\nADAM:\n\nWe've been living the bee way\n\na long time, 27 million years.\n\n(Flash forward in time and Barry is talking to a man)\n\nBUSINESS MAN:\n\nCongratulations on your victory.\n\nWhat will you demand as a settlement?\n\nBARRY:\n\nFirst, we'll demand a complete shutdown\n\nof all bee work camps.\n\n(As Barry is talking we see a montage of men putting ''closed'' tape over the\n\n\nwork camps and freeing the bees in the crappy apartments)\nThen we want back the honey\nthat was ours to begin with,\n\n\nevery last drop.\n\n(Men in suits are pushing all the honey of the aisle and into carts)\n\nWe demand an end to the glorification\n\nof the bear as anything more\n\n(We see a statue of a bear-shaped honey container being pulled down by\nbees)\n\nthan a filthy, smelly,\n\nbad-breath stink machine.\n\n\nWe're all aware\n\nof what they do in the woods.\n\n(We see Winnie the Pooh sharing his honey with Piglet in the cross-hairs of\na high-tech sniper rifle)\n\nBARRY:\n\n(Looking through binoculars)\n\n\nWait for my signal.\n\n\nTake him out.\n\n(Winnie gets hit by a tranquilizer dart and dramatically falls off the log\nhe was standing on, his tongue hanging out. Piglet looks at Pooh in fear\nand the Sniper takes the honey.)\n\nSNIPER:\n\nHe'll have nausea\n\nfor a few hours, then he'll be fine.\n\n(Flash forward in time)\n\nBARRY:\n\nAnd we will no longer tolerate\n\nbee-negative nicknames...\n\n(Mr. Sting is sitting at home until he is taken out of his house by the men\nin suits)\n\nSTING:\n\nBut it's just a prance-about stage name!\n\nBARRY:\n\n...unnecessary inclusion of honey\n\nin bogus health products\n\n\nand la-dee-da human\ntea-time snack garnishments.\n(An old lady is mixing honey into her tea but suddenly men in suits smash\n\n\nher face down on the table and take the honey)\nOLD LADY:\n\nCan't breathe.\n\n(A honey truck pulls up to Barry's hive)\nWORKER:\n\nBring it in, boys!\n\n\nHold it right there! Good.\nTap it.\n\n\n(Tons of honey is being pumped into the hive's storage)\nBEE WORKER 1#:\n\n(Honey overflows from the cup)\n\nMr. Buzzwell, we just passed three cups,\n\nand there's gallons more coming!\n\n\n- | think we need to shut down!\n=BEE WORKER #2=\n- Shut down? We've never shut down.\n\n\nShut down honey production!\n\nDEAN BUZZWELL:\n\nStop making honey!\n\n(The bees all leave their stations. Two bees run into a room and they put\nthe keys into a machine)\n\nTurn your key, sir!\n\n(Two worker bees dramatically turn their keys, which opens the button which\nthey press, shutting down the honey-making machines. This is the first time\nthis has ever happened)\n\nBEE:\n\n... What do we do now?\n\n(Flash forward in time and a Bee is about to jump into a pool full of\n\nhoney)\n\nCannonball!\n\n(The bee gets stuck in the honey and we get a short montage of Bees leaving\nwork)\n\n(We see the Pollen Jocks flying but one of them gets a call on his antenna)\nLOU LU DUVA:\n\n(Through ''phone'')\n\nWe're shutting honey production!\n\n\nMission abort.\nPOLLEN JOCK #1:\n\n\nAborting pollination and nectar detail.\nReturning to base.\n(The Pollen Jocks fly back to the hive)\n\n\n(We get a time lapse of Central Park slowly wilting away as the bees all\nrelax)\n\nBARRY:\n\nAdam, you wouldn't believe\n\nhow much honey was out there.\n\nADAM:\n\nOh, yeah?\n\nBARRY:\n\nWhat's going on? Where is everybody?\n\n(The entire street is deserted)\n\n\n- Are they out celebrating?\nADAM:\n- They're home.\n\n\nThey don't know what to do.\nLaying out, sleeping in.\n\n\n| heard your Uncle Carl was on his way\nto San Antonio with a cricket.\n\nBARRY:\n\nAt least we got our honey back.\n\nADAM:\n\nSometimes | think, so what if humans\nliked our honey? Who wouldn't?\n\n\nIt's the greatest thing in the world!\n| was excited to be part of making it.\n\n\nThis was my new desk. This was my\nnew job. | wanted to do it really well.\n\n\nAnd now...\n\n\nNow | can't.\n\n(Flash forward in time and Barry is talking to Vanessa)\nBARRY:\n\n| don't understand\n\nwhy they're not happy.\n\n\n| thought their lives would be better!\n\n\nThey're doing nothing. It's amazing.\n\nHoney really changes people.\n\nVANESSA:\n\nYou don't have any idea\n\nwhat's going on, do you?\n\nBARRY:\n\n- What did you want to show me?\n\n(Vanessa takes Barry to the rooftop where they first had coffee and points\nto her store)\n\nVANESSA:\n\n- This.\n\n(Points at her flowers. They are all grey and wilting)\n\nBARRY:\n\nWhat happened here?\n\nVANESSA:\n\nThat is not the half of it.\n\n(Small flash forward in time and Vanessa and Barry are on the roof of her\nstore and she points to Central Park)\n\n(We see that Central Park is no longer green and colorful, rather it is\ngrey, brown, and dead-like. It is very depressing to look at)\n\nBARRY:\n\nOh, no. Oh, my.\n\n\nThey're all wilting.\n\nVANESSA:\n\nDoesn't look very good, does it?\nBARRY:\n\nNo.\n\nVANESSA:\n\nAnd whose fault do you think that is?\nBARRY:\n\nYou know, I'm gonna guess bees.\nVANESSA==\n\n(Staring at Barry)\n\nBees?\n\nBARRY:\n\nSpecifically, me.\n\n\n| didn't think bees not needing to make\nhoney would affect all these things.\n\n\nVANESSA:\n\nIt's not just flowers.\n\nFruits, vegetables, they all need bees.\nBARRY:\n\nThat's our whole SAT test right there.\nVANESSA:\n\nTake away produce, that affects\n\nthe entire animal kingdom.\n\n\nAnd then, of course...\nBARRY:\nThe human species?\n\n\nSo if there's no more pollination,\n\n\nit could all just go south here,\ncouldn't it?\n\nVANESSA:\n\n| know this is also partly my fault.\nBARRY:\n\nHow about a suicide pact?\nVANESSA:\n\nHow do we do it?\n\nBARRY:\n\n- I'll sting you, you step on me.\nVANESSA:\n\n- That just kills you twice.\nBARRY:\n\nRight, right.\n\nVANESSA:\n\nListen, Barry...\n\nsorry, but | gotta get going.\n(Vanessa leaves)\n\nBARRY:\n\n(To himself)\n\n| had to open my mouth and talk.\n\n\nVanessa?\n\n\nVanessa? Why are you leaving?\nWhere are you going?\n\n(Vanessa is getting into a taxi)\nVANESSA:\n\n\nTo the final Tournament of Roses parade\nin Pasadena.\n\n\nThey've moved it to this weekend\nbecause all the flowers are dying.\n\n\nIt's the last chance\n\nI'll ever have to see it.\n\nBARRY:\n\nVanessa, | just wanna say I'm sorry.\n| never meant it to turn out like this.\nVANESSA:\n\n| know. Me neither.\n\n(The taxi starts to drive away)\nBARRY:\n\nTournament of Roses.\n\nRoses can't do sports.\n\n\nWait a minute. Roses. Roses?\nRoses!\n\n\nVanessa!\n\n(Barry flies after the Taxi)\nVANESSA:\n\nRoses?!\n\n\nBarry?\n\n(Barry is flying outside the window of the taxi)\nBARRY:\n\n- Roses are flowers!\n\nVANESSA:\n\n- Yes, they are.\n\nBARRY:\n\nFlowers, bees, pollen!\n\n\nVANESSA:\n\nI know.\n\nThat's why this is the last parade.\nBARRY:\n\nMaybe not.\n\nCould you ask him to slow down?\nVANESSA:\n\n\nCould you slow down?\n(The taxi driver screeches to a stop and Barry keeps flying forward)\n\n\nBarry!\n\n(Barry flies back to the window)\nBARRY:\n\nOK, | made a huge mistake.\n\nThis is a total disaster, all my fault.\nVANESSA:\n\nYes, it kind of is.\n\nBARRY:\n\nI've ruined the planet.\n\n| wanted to help you\n\n\nwith the flower shop.\n\nI've made it worse.\n\nVANESSA:\n\nActually, it's completely closed down.\nBARRY:\n\n| thought maybe you were remodeling.\n\n\nBut | have another idea, and it's\n\ngreater than my previous ideas combined.\nVANESSA:\n\n| don't want to hear it!\n\n\nBARRY:\nAll right, they have the roses,\nthe roses have the pollen.\n\n\n| know every bee, plant\nand flower bud in this park.\n\n\nAll we gotta do is get what they've got\nback here with what we've got.\n\n\n- Bees.\nVANESSA:\n- Park.\nBARRY:\n\n- Pollen!\nVANESSA:\n- Flowers.\nBARRY:\n\n\n- Re-pollination!\nVANESSA:\n- Across the nation!\n\n\nTournament of Roses,\nPasadena, California.\n\n\nThey've got nothing\nbut flowers, floats and cotton candy.\n\n\nSecurity will be tight.\nBARRY:\n| have an idea.\n\n\n(Flash forward in time. Vanessa is about to board a plane which has all the\nRoses on board.\n\nVANESSA:\n\nVanessa Bloome, FTD.\n\n(Holds out badge)\n\n\nOfficial floral business. It's real.\n\nSECURITY GUARD:\n\nSorry, ma'am. Nice brooch.\n\n=VANESSA==\n\nThank you. It was a gift.\n\n(Barry is revealed to be hiding inside the brooch)\n(Flash back in time and Barry and Vanessa are discussing their plan)\nBARRY:\n\nOnce inside,\n\nwe just pick the right float.\n\nVANESSA:\n\nHow about The Princess and the Pea?\n\n\n| could be the princess,\nand you could be the pea!\nBARRY:\n\nYes, | got it.\n\n\n- Where should | sit?\nGUARD:\n\n- What are you?\nBARRY:\n\n- | believe I'm the pea.\nGUARD:\n\n\n- The pea?\nVANESSA:\n\n\nIt goes under the mattresses.\nGUARD:\n\n- Not in this fairy tale, sweetheart.\n- I'm getting the marshal.\nVANESSA:\n\nYou do that!\n\nThis whole parade is a fiasco!\n\n\nLet's see what this baby'll do.\n\n(Vanessa drives the float through traffic)\nGUARD:\n\nHey, what are you doing?!\n\nBARRY==\n\nThen all we do\n\nis blend in with traffic...\n\n\n...without arousing suspicion.\n\n\nOnce at the airport,\n\nthere's no stopping us.\n\n(Flash forward in time and Barry and Vanessa are about to get on a plane)\nSECURITY GUARD:\n\nStop! Security.\n\n\n- You and your insect pack your float?\nVANESSA:\n\n- Yes.\n\nSECURITY GUARD:\n\nHas it been\n\nin your possession the entire time?\nVANESSA:\n\n- Yes.\n\n\nSECURITY GUARD:\n\nWould you remove your shoes?\n(To Barry)\n\n- Remove your stinger.\n\nBARRY:\n\n- It's part of me.\n\nSECURITY GUARD:\n\n| know. Just having some fun.\n\n\nEnjoy your flight.\n\n(Barry plotting with Vanessa)\n\nBARRY:\n\nThen if we're lucky, we'll have\n\njust enough pollen to do the job.\n\n(Flash forward in time and Barry and Vanessa are flying on the plane)\nCan you believe how lucky we are? We\nhave just enough pollen to do the job!\nVANESSA:\n\n| think this is gonna work.\n\nBARRY:\n\nIt's got to work.\n\nCAPTAIN SCOTT:\n\n(On intercom)\n\nAttention, passengers,\n\nthis is Captain Scott.\n\n\nWe have a bit of bad weather\nin New York.\n\n\nIt looks like we'll experience\n\na couple hours delay.\n\nVANESSA:\n\nBarry, these are cut flowers\n\nwith no water. They'll never make it.\nBARRY:\n\n\n| gotta get up there\n\nand talk to them.\n\nVANESSA==\n\nBe careful.\n\n(Barry flies right outside the cockpit door)\nBARRY:\n\nCan | get help\n\nwith the Sky Mall magazine?\n\nI'd like to order the talking\n\ninflatable nose and ear hair trimmer.\n(The flight attendant opens the door and walks out and Barry flies into the\ncockpit unseen)\n\nBARRY:\n\nCaptain, I'm in a real situation.\n\nCAPTAIN SCOTT:\n\n- What'd you say, Hal?\n\nCO-PILOT HAL:\n\n\n- Nothing.\n\n(Scott notices Barry and freaks out)\n\nCAPTAIN SCOTT:\n\nBee!\n\nBARRY:\n\nNo,no,no, Don't freak out! My entire species...\n\n(Captain Scott gets out of his seat and tries to suck Barry into a handheld\nvacuum)\n\nHAL:\n\n(To Scott)\n\nWhat are you doing?\n\n(Barry lands on Hals hair but Scott sees him. He tries to suck up Barry but\ninstead he sucks up Hals toupee)\n\nCAPTAIN SCOTT:\n\nUh-oh.\n\nBARRY:\n\n- Wait a minute! I'm an attorney!\n\n\nHAL:\n\n(Hal doesn't know Barry is on his head)\n\n- Who's an attorney?\n\nCAPTAIN SCOTT:\n\nDon't move.\n\n(Scott hits Hal in the face with the vacuum in an attempt to hit Barry. Hal\nis knocked out and he falls on the life raft button which launches an\ninfalatable boat into Scott, who gets knocked out and falls to the floor.\nThey are both uncounscious. )\n\nBARRY:\n\n(To himself)\n\nOh, Barry.\n\nBARRY:\n\n(On intercom, with a Southern accent)\n\nGood afternoon, passengers.\n\nThis is your captain.\n\n\nWould a Miss Vanessa Bloome in 24B\n\nplease report to the cockpit?\n\n(Vanessa looks confused)\n\n(Normal accent)\n\n...And please hurry!\n\n(Vanessa opens the door and sees the life raft and the uncounscious pilots)\nVANESSA:\n\nWhat happened here?\n\nBARRY:\n\n\n| tried to talk to them, but\nthen there was a DustBuster,\na toupee, a life raft exploded.\n\n\nNow one's bald, one's in a boat,\nand they're both unconscious!\nVANESSA:\n\n..Is that another bee joke?\nBARRY:\n\n\n- No!\n\n\nNo one's flying the plane!\n\nBUD DITCHWATER:\n\n(Through radio on plane)\n\nThis is JFK control tower, Flight 356.\nWhat's your status?\n\nVANESSA:\n\nThis is Vanessa Bloome.\n\nI'm a florist from New York.\nBUD:\n\nWhere's the pilot?\n\nVANESSA:\n\nHe's unconscious,\n\nand so is the copilot.\n\nBUD:\n\nNot good. Does anyone onboard\nhave flight experience?\n\nBARRY:\n\nAs a matter of fact, there is.\nBUD:\n\n- Who's that?\n\nBARRY:\n\n- Barry Benson.\n\nBUD:\n\nFrom the honey trial?! Oh, great.\nBARRY:\n\nVanessa, this is nothing more\nthan a big metal bee.\n\n\nIt's got giant wings, huge engines.\n\n\nVANESSA:\n| can't fly a plane.\n\n\nBARRY:\n\n- Why not? Isn't John Travolta a pilot?\n\nVANESSA:\n\n- Yes.\n\nBARRY:\n\nHow hard could it be?\n\n(Vanessa sits down and flies for a little bit but we see lightning clouds\noutside the window)\n\nVANESSA:\n\nWait, Barry!\n\nWe're headed into some lightning.\n\n(An ominous lightning storm looms in front of the plane)\n(We are now watching the Bee News)\n\nBOB BUMBLE:\n\nThis is Bob Bumble. We have some\n\nlate-breaking news from JFK Airport,\n\n\nwhere a suspenseful scene\nis developing.\n\n\nBarry Benson,\n\nfresh from his legal victory...\nADAM:\n\nThat's Barry!\n\nBOB BUMBLE:\n\n...1S attempting to land a plane,\nloaded with people, flowers\n\n\nand an incapacitated flight crew.\n\nJANET, MARTIN, UNCLE CAR AND ADAM:\nFlowers?!\n\n(The scene switches to the human news)\n\n\nREPORTER:\n\n(Talking with Bob Bumble)\n\nWe have a storm in the area\n\nand two individuals at the controls\n\n\nwith absolutely no flight experience.\nBOB BUMBLE:\n\nJust a minute.\n\nThere's a bee on that plane.\n\nBUD:\n\nI'm quite familiar with Mr. Benson\n\n\nand his no-account compadres.\n\n\nThey've done enough damage.\nREPORTER:\n\nBut isn't he your only hope?\nBUD:\n\nTechnically, a bee\n\nshouldn't be able to fly at all.\n\n\nTheir wings are too small...\n\nBARRY:\n\n(Through radio)\n\nHaven't we heard this a million times?\n\n\n''The surface area of the wings\nand body mass make no sense.''...\nBOB BUMBLE:\n\n- Get this on the air!\n\nBEE:\n\n- Got it.\n\n\nBEE NEWS CREW:\n\n- Stand by.\n\nBEE NEWS CREW:\n\n- We're going live!\n\nBARRY:\n\n(Through radio on TV)\n\n... lhe way we work may be a mystery to you.\n\n\nMaking honey takes a lot of bees\ndoing a lot of small jobs.\n\n\nBut let me tell you about a small job.\n\n\nIf you do it well,\nit makes a big difference.\n\n\nMore than we realized.\nTo us, to everyone.\n\n\nThat's why | want to get bees\nback to working together.\n\n\nThat's the bee way!\n\n\nWe're not made of Jell-O.\nWe get behind a fellow.\n\n\n- Black and yellow!\n\nBEES:\n\n- Hello!\n\n(The scene switches and Barry is teaching Vanessa how to fly)\nBARRY:\n\n\nLeft, right, down, hover.\n\nVANESSA:\n\n- Hover?\n\nBARRY:\n\n- Forget hover.\n\nVANESSA:\n\nThis isn't so hard.\n\n(Pretending to honk the horn)\n\nBeep-beep! Beep-beep!\n\n(A Lightning bolt hits the plane and autopilot turns off)\nBarry, what happened?!\n\nBARRY:\n\nWait, | think we were\n\non autopilot the whole time.\n\nVANESSA:\n\n- That may have been helping me.\n\nBARRY:\n\n- And now we're not!\n\nVANESSA:\n\nSo it turns out | cannot fly a plane.\n\n(The plane plummets but we see Lou Lu Duva and the Pollen Jocks, along with\nmultiple other bees flying towards the plane)\nLou Lu DUva:\n\nAll of you, let's get\n\nbehind this fellow! Move it out!\n\n\nMove out!\n\n(The scene switches back to Vanessa and Barry in the plane)\n\nBARRY:\n\nOur only chance is if | do what I'd do,\n\nyou copy me with the wings of the plane!\n\n(Barry sticks out his arms like an airplane and flys in front of Vanessa's\nface)\n\n\nVANESSA:\n\nDon't have to yell.\n\nBARRY:\n\nI'm not yelling!\n\nWe're in a lot of trouble.\nVANESSA:\n\nIt's very hard to concentrate\nwith that panicky tone in your voice!\nBARRY:\n\nIt's not a tone. I'm panicking!\nVANESSA:\n\n| can't do this!\n\n(Barry slaps Vanessa)\nBARRY:\n\nVanessa, pull yourself together.\nYou have to snap out of it!\nVANESSA:\n\n(Slaps Barry)\n\nYou snap out of it.\n\nBARRY:\n\n(Slaps Vanessa)\n\n\nYou snap out of it.\n\nVANESSA:\n\n- You snap out of it!\n\nBARRY:\n\n- You snap out of it!\n\n(We see that all the Pollen Jocks are flying under the plane)\nVANESSA:\n\n- You snap out of it!\n\nBARRY:\n\n- You snap out of it!\n\n\nVANESSA:\n\n- You snap out of it!\n\nBARRY:\n\n- You snap out of it!\nVANESSA:\n\n- Hold it!\n\nBARRY:\n\n- Why? Come on, it's my turn.\nVANESSA:\n\nHow is the plane flying?\n\n(The plane is now safely flying)\n\n\nVANESSA:\n\n| don't know.\n\n(Barry's antennae rings like a phone. Barry picks up)\nBARRY:\n\nHello?\n\nLOU LU DUVA:\n\n(Through ''phone'')\n\nBenson, got any flowers\n\nfor a happy occasion in there?\n\n(All of the Pollen Jocks are carrying the plane)\nBARRY:\n\nThe Pollen Jocks!\n\n\nThey do get behind a fellow.\nLOU LU DUVA:\n\n- Black and yellow.\n\nPOLLEN JOCKS:\n\n- Hello.\n\nLOU LU DUVA:\n\nAll right, let's drop this tin can\n\n\non the blacktop.\n\nBARRY:\n\nWhere? | can't see anything. Can you?\nVANESSA:\n\nNo, nothing. It's all cloudy.\n\n\nCome on. You got to think bee, Barry.\nBARRY:\n\n- Thinking bee.\n\n- Thinking bee.\n\n(On the runway there are millions of bees laying on their backs)\nBEES:\n\nThinking bee!\n\nThinking bee! Thinking bee!\n\nBARRY:\n\nWait a minute.\n\n| think I'm feeling something.\nVANESSA:\n\n- What?\n\nBARRY:\n\n- | don't know. It's strong, pulling me.\n\n\nLike a 27-million-year-old instinct.\n\n\nBring the nose down.\n\nBEES:\n\nThinking bee!\n\nThinking bee! Thinking bee!\nCONTROL TOWER OPERATOR:\n\n- What in the world is on the tarmac?\nBUD:\n\n- Get some lights on that!\n\n\n(It is revealed that all the bees are organized into a giant pulsating\nflower formation)\n\nBEES:\n\nThinking bee!\n\nThinking bee! Thinking bee!\nBARRY:\n\n- Vanessa, aim for the flower.\nVANESSA:\n\n- OK.\n\nBARRY:\n\nOut the engines. We're going in\non bee power. Ready, boys?\nLOU LU DUVA:\n\nAffirmative!\n\nBARRY:\n\nGood. Good. Easy, now. That's it.\n\n\nLand on that flower!\nReady? Full reverse!\n\n\nSpin it around!\n\n(The plane's nose is pointed at a flower painted on a nearby plane)\n- Not that flower! The other one!\n\nVANESSA:\n\n- Which one?\n\nBARRY:\n\n- That flower.\n\n(The plane is now pointed at a fat guy in a flowered shirt. He freaks out\nand tries to take a picture of the plane)\n\nVANESSA:\n\n- I'm aiming at the flower!\n\n\nBARRY:\n\n\nThat's a fat guy in a flowered shirt.\n\nI mean the giant pulsating flower\nmade of millions of bees!\n\n(The plane hovers over the bee-flower)\n\n\nPull forward. Nose down. Tail up.\n\n\nRotate around it.\n\nVANESSA:\n\n- This is insane, Barry!\n\nBARRY:\n\n- This's the only way | know how to fly.\nBUD:\n\nAm | koo-koo-kachoo, or is this plane\nflying in an insect-like pattern?\n\n(The plane is unrealistically hovering and spinning over the bee-flower)\nBARRY:\n\nGet your nose in there. Don't be afraid.\nSmell it. Full reverse!\n\n\nJust drop it. Be a part of it.\nAim for the center!\nNow drop it in! Drop it in, woman!\n\n\nCome on, already.\n\n(The bees scatter and the plane safely lands)\nVANESSA:\n\nBarry, we did it!\n\nYou taught me how to fly!\n\n\nBARRY:\n\n- Yes!\n\n(Vanessa is about to high-five Barry)\nNo high-five!\n\nVANESSA:\n\n- Right.\n\nADAM:\n\nBarry, it worked!\n\nDid you see the giant flower?\nBARRY:\n\nWhat giant flower? Where? Of course\n| saw the flower! That was genius!\n\n\nADAM:\n\n- Thank you.\n\nBARRY:\n\n- But we're not done yet.\n\n\nListen, everyone!\n\n\nThis runway is covered\nwith the last pollen\n\n\nfrom the last flowers\navailable anywhere on Earth.\n\n\nThat means this is our last chance.\n\n\nWe're the only ones who make honey,\npollinate flowers and dress like this.\n\n\nIf we're gonna survive as a species,\nthis is our moment! What do you say?\n\n\nAre we going to be bees, or just\nMuseum of Natural History keychains?\nBEES:\n\nWe're bees!\n\nBEE WHO LIKES KEYCHAINS:\nKeychain!\n\nBARRY:\n\nThen follow me! Except Keychain.\nPOLLEN JOCK #1:\n\nHold on, Barry. Here.\n\n\nYou've earned this.\nBARRY:\nYeah!\n\n\nI'm a Pollen Jock! And it's a perfect\n\nfit. All | gotta do are the sleeves.\n\n(The Pollen Jocks throw Barry a nectar-collecting gun. Barry catches it)\nOh, yeah.\n\nJANET:\n\nThat's our Barry.\n\n(Barry and the Pollen Jocks get pollen from the flowers on the plane)\n\n\n(Flash forward in time and the Pollen Jocks are flying over NYC)\n\n\n(Barry pollinates the flowers in Vanessa's shop and then heads to Central\nPark)\n\nBOY IN PARK:\n\nMom! The bees are back!\n\nADAM:\n\n(Putting on his Krelman hat)\n\nIf anybody needs\n\n\nto make a call, now's the time.\n\n\n| got a feeling we'll be\n\nworking late tonight!\n\n(The bee honey factories are back up and running)\n(Meanwhile at Vanessa's shop)\n\nVANESSA:\n\n(To customer)\n\nHere's your change. Have a great\n\nafternoon! Can | help who's next?\n\n\nWould you like some honey with that?\n\nIt is bee-approved. Don't forget these.\n\n(There is a room in the shop where Barry does legal work for other animals.\nHe is currently talking with a Cow)\n\nCOW:\n\nMilk, cream, cheese, it's all me.\n\nAnd | don't see a nickel!\n\n\nSometimes | just feel\n\nlike a piece of meat!\nBARRY:\n\n| had no idea.\nVANESSA:\n\nBarry, I'm sorry.\n\nHave you got a moment?\nBARRY:\n\nWould you excuse me?\nMy mosquito associate will help you.\nMOOSEBLOOD:\n\nSorry I'm late.\n\nCOW:\n\nHe's a lawyer too?\n\n\nMOOSEBLOOD:\n\nMa'am, | was already a blood-sucking parasite.\nAll | needed was a briefcase.\n\nVANESSA:\n\nHave a great afternoon!\n\n\nBarry, | just got this huge tulip order,\nand | can't get them anywhere.\nBARRY:\n\nNo problem, Vannie.\n\nJust leave it to me.\n\nVANESSA:\n\nYou're a lifesaver, Barry.\n\nCan | help who's next?\n\nBARRY:\n\nAll right, scramble, jocks!\n\nIt's time to fly.\n\nVANESSA:\n\nThank you, Barry!\n\n(Ken walks by on the sidewalk and sees the ''bee-approved honey'' in\nVanessa's shop)\n\nKEN:\n\nThat bee is living my life!!\nANDY:\n\nLet it go, Kenny.\n\nKEN:\n\n- When will this nightmare end?!\nANDY:\n\n- Let it all go.\n\nBARRY:\n\n- Beautiful day to fly.\n\nPOLLEN JOCK:\n\n\n- Sure is.\n\nBARRY:\n\nBetween you and me,\n\n| was dying to get out of that office.\n\n(Barry recreates the scene near the beginning of the movie where he flies\nthrough the box kite. The movie fades to black and the credits being)\n[--after credits; No scene can be seen but the characters can be heard\ntalking over the credits--]\n\nYou have got\n\nto start thinking bee, my friend!\n\n\n- Thinking bee!\n\n- Me?\n\nBARRY:\n\n(Talking over singer)\n\nHold it. Let's just stop\nfor a second. Hold it.\n\n\nI'm sorry. I'm sorry, everyone.\n\nCan we stop here?\n\nSINGER:\n\nOh, BarryBARRY:\n\nI'm not making a major life decision\nduring a production number!\nSINGER:\n\nAll right. Take ten, everybody.\nWrap it up, guys.\n\nBARRY:\n\n| had virtually no rehearsal for that.";
	
	var _timer_start_compile = get_timer();
	
	var _tokenizer = new GPUTokenizer();
	_tokenizer.addPattern(@'[^ \t\n\r]+');
	_tokenizer.addDelimiter(@' \t\n\r');
	_tokenizer.compile();

	var _timer_end_compile = get_timer();

	var _timer_start_tokenize = get_timer();

	var _output_buffer = _tokenizer.tokenize(_input_text);
	var _token_count = 0;

	buffer_seek(_output_buffer, buffer_seek_start, 0);
	while (buffer_tell(_output_buffer) < _tokenizer.outputLength) {
		var _token_text = buffer_read(_output_buffer, buffer_string);
		if (_token_text == "") {
			break;
		}
		_token_count++;
	}

	var _timer_end_tokenize = get_timer();

	var _compile_us = _timer_end_compile - _timer_start_compile;
	var _tokenize_us = _timer_end_tokenize - _timer_start_tokenize;

	show_debug_message("STRESS TEST - Bee Movie Script");
	show_debug_message("  Input bytes:    " + string(string_byte_length(_input_text)));
	show_debug_message("  Token count:    " + string(_token_count));
	show_debug_message("  Compile time:   " + string(_compile_us) + "µs");
	show_debug_message("  Tokenize time:  " + string(_tokenize_us/1000) + "ms");

	buffer_delete(_output_buffer);
	_tokenizer.destroy();
});