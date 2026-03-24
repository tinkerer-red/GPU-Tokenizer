# GPU Tokenizer

A GPU-based tokenizer for GameMaker.

GPU Tokenizer lets you define token rules in GML, compile those rules once, then tokenize input strings or buffers on the GPU. It is intended for projects that need fast, repeatable tokenization for things like source code, markup, or structured text.

## What it does

GPUTokenizer gives you a small rule system built around:

- patterns
- contexts
- delimiters
- ignored bytes
- unmatched-byte handling

Typical use cases include:

- source-code tokenization
- markup tokenization
- structured text splitting
- syntax highlighting
- preprocessing and import pipelines

## Basic workflow

1. Create a tokenizer.
2. Add rules.
3. Call `compile()`.
4. Call `tokenize()` or `tokenizeBuffer()`.
5. Read tokens from the returned buffer.
6. Destroy the tokenizer when finished.

## API

### `new GPUTokenizer()`

Creates a tokenizer instance.

### `addPattern(_regex)`

Adds a normal token rule.

Use this for things like:

- identifiers
- numbers
- operators
- punctuation
- plain text runs

Examples:

```gml
_tokenizer.addPattern(@'\w[\w\d]*');
_tokenizer.addPattern(@'\d+');
_tokenizer.addPattern(@'[+\-*/=<>!&|^~%?]+');
````

### `addContextPattern(_open, _close, _escape, [_keepOpen], [_keepClose], [_keepEscape])`

Adds a context rule.

Use this for tokens that begin with a known opener and continue until a matching closer.

Common uses:

* quoted strings
* block comments
* line comments
* raw text blocks

Examples:

```gml
_tokenizer.addContextPattern(@'"', @'"', @'\');
_tokenizer.addContextPattern("//", "\n", "");
_tokenizer.addContextPattern("/*", "*/", "");
```

### `addDelimiter(_chars)`

Adds delimiter bytes.

Delimiters split tokens and are not returned as tokens.

Examples:

```gml
_tokenizer.addDelimiter(@' \t');
_tokenizer.addDelimiter(@',');
_tokenizer.addDelimiter(@' \t\n\r');
```

### `addIgnore(_chars)`

Adds ignored bytes.

Ignored bytes are skipped completely.

Example:

```gml
_tokenizer.addIgnore(@'\r');
```

### `setUnmatchedRule(_mode)`

Controls what happens when input does not match any rule.

Modes:

```gml
GPU_TOKEN.OMIT
GPU_TOKEN.ISOLATE
GPU_TOKEN.CONCATENATE
```

### `compile()`

Finalizes the rule set and builds the internal GPU lookup data.

Call this after adding rules and before tokenizing.

### `tokenize(_input)`

Tokenizes a GameMaker string.

Returns a buffer of `buffer_string` entries.

### `tokenizeBuffer(_buffer, _byteLen)`

Tokenizes raw buffer input.

Use this when your source text is already in a buffer or when you want exact byte-length control.

### `destroy()`

Frees the tokenizer's internal resources.

Returned output buffers are still owned by the caller and must be deleted separately.

## Reading output

```gml
var _output_buffer = _tokenizer.tokenize(_input_text);

buffer_seek(_output_buffer, buffer_seek_start, 0);
while (buffer_tell(_output_buffer) < _tokenizer.outputLength) {
	var _token = buffer_read(_output_buffer, buffer_string);
	if (_token == "") {
		break;
	}
	show_debug_message(_token);
}

buffer_delete(_output_buffer);
```

## Example: GML

```gml
var _tokenizer = new GPUTokenizer();

_tokenizer.addPattern(@'\w[\w\d]*');
_tokenizer.addPattern(@'\d+\.\d+');
_tokenizer.addPattern(@'\d+');
_tokenizer.addPattern(@'[+\-*/=<>!&|^~%?]+');
_tokenizer.addPattern(@'[(){}\[\];,:.@#$]');

_tokenizer.addContextPattern(@'"', @'"', @'\');
_tokenizer.addContextPattern("//", "\n", "");
_tokenizer.addContextPattern("/*", "*/", "");

_tokenizer.addDelimiter(@' \t');
_tokenizer.addIgnore(@'\r');
_tokenizer.setUnmatchedRule(GPU_TOKEN.ISOLATE);

_tokenizer.compile();
```

Good for:

* GameMaker source
* syntax highlighters
* preprocessors
* compiler front-ends

## Example: BBCode

```gml
var _tokenizer = new GPUTokenizer();

_tokenizer.addPattern(@'\[[A-Za-z][A-Za-z0-9_]*\]');
_tokenizer.addPattern(@'\[[A-Za-z][A-Za-z0-9_]*=[^\]\n]+\]');
_tokenizer.addPattern(@'\[/[A-Za-z][A-Za-z0-9_]*\]');
_tokenizer.addPattern(@'[^\[\]\n]+');
_tokenizer.addPattern(@'[\[\]]');

_tokenizer.addDelimiter(@'\n\r');

_tokenizer.compile();
```

Good for:

* forum-style markup
* chat formatting
* rich text preprocessors

## Example: CSV-Like Split

```gml
var _tokenizer = new GPUTokenizer();

_tokenizer.addPattern(@'[^,\n]+');
_tokenizer.addDelimiter(",");
_tokenizer.addIgnore(@'\r');

_tokenizer.compile();
```

Good for:

* simple comma-separated data
* import tools
* line-based structured text

## Notes

* The intended workflow is compile once, tokenize many times.
* `outputLength` is the authoritative bound when reading the returned buffer.
* `tokenizeBuffer()` is preferred when your input already exists as raw bytes.
* Delimiters split tokens.
* Ignore rules remove bytes entirely.
* Context rules are best used for strings and comments.

## Credits

Special thanks to Terpatin / HannulaTero for inspiring this project through the GPUTF8 library:

[GPUTF8](https://github.com/HannulaTero/GPUTF8)
