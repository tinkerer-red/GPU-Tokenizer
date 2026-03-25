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

Adds a normal token rule using a regex pattern.

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
```

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
GPU_TOKEN.OMIT          // unmatched bytes are dropped
GPU_TOKEN.ISOLATE       // each unmatched byte becomes its own token
GPU_TOKEN.CONCATENATE   // consecutive unmatched bytes merge into one token
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

## Supported Regex Syntax

Patterns passed to `addPattern()` use a subset of standard regex syntax. The tokenizer compiles each pattern into a Thompson NFA that runs on the GPU, giving exact greedy longest-match semantics with zero false positives.

### Literals

Any character that is not a metacharacter matches itself.

```
abc         matches the literal string "abc"
hello       matches the literal string "hello"
```

### Dot

`.` matches any single byte except newline (`0x0A`).

```
a.c         matches "abc", "a1c", "a-c", etc.
```

### Character Classes

Square brackets define a set of bytes. Any one byte in the set matches.

```
[abc]       matches "a", "b", or "c"
[0-9]       matches any digit
[a-zA-Z]    matches any letter
[a-zA-Z0-9_]  matches word characters
```

Negated classes match any byte not in the set:

```
[^abc]      matches anything except "a", "b", or "c"
[^0-9]      matches anything except digits
[^,\n]      matches anything except comma and newline
```

Ranges use `-` between two characters:

```
[a-z]       matches lowercase letters
[A-Z]       matches uppercase letters
[0-9]       matches digits
[a-f0-9]    matches hex digits
```

Literal `-` can appear at the start of a class or before `]`:

```
[-abc]      matches "-", "a", "b", or "c"
[abc-]      matches "a", "b", "c", or "-"
```

Escaped characters inside classes:

```
[\]]        matches literal "]"
[\[]        matches literal "["
[\-]        matches literal "-"
[\\]        matches literal "\"
[\d]        expands to digits (same as [0-9])
[\w]        expands to word characters
[\s]        expands to whitespace
```

### Shorthand Classes

Shorthand sequences expand to predefined character sets:

| Shorthand | Matches | Equivalent |
|-----------|---------|------------|
| `\d` | Digits | `[0-9]` |
| `\D` | Non-digits | `[^0-9]` |
| `\w` | Word characters | `[a-zA-Z_]` |
| `\W` | Non-word characters | `[^a-zA-Z_]` |
| `\s` | Whitespace | `[ \t\n\r]` |
| `\S` | Non-whitespace | `[^ \t\n\r]` |

### Escape Sequences

Backslash escapes produce literal bytes or special characters:

| Escape | Result |
|--------|--------|
| `\n` | Newline (0x0A) |
| `\r` | Carriage return (0x0D) |
| `\t` | Tab (0x09) |
| `\\` | Literal backslash |
| `\.` | Literal dot |
| `\*` | Literal asterisk |
| `\+` | Literal plus |
| `\?` | Literal question mark |
| `\|` | Literal pipe |
| `\(` | Literal open paren |
| `\)` | Literal close paren |
| `\{` | Literal open brace |
| `\}` | Literal close brace |
| `\[` | Literal open bracket |
| `\]` | Literal close bracket |
| `\-` | Literal hyphen |
| `\^` | Literal caret |
| `\$` | Literal dollar |

Any other escaped character produces the literal byte value of that character.

### Quantifiers

Quantifiers control how many times the preceding element repeats:

| Quantifier | Meaning |
|------------|---------|
| `*` | Zero or more (greedy) |
| `+` | One or more (greedy) |
| `?` | Zero or one (greedy) |

Examples:

```
\d+         one or more digits
\w*         zero or more word characters
[a-z]?      zero or one lowercase letter
```

### Counted Quantifiers

Counted quantifiers give explicit repeat bounds:

| Quantifier | Meaning |
|------------|---------|
| `{m}` | Exactly m times |
| `{m,}` | m or more times |
| `{m,n}` | Between m and n times (inclusive) |

Examples:

```
\d{4}       exactly 4 digits
\d{2,4}     2, 3, or 4 digits
\w{3,}      3 or more word characters
[a-f0-9]{6} exactly 6 hex digits
```

If `{` cannot be parsed as a valid quantifier, it is treated as a literal `{` character.

### Grouping

Parentheses group sub-expressions, affecting precedence and enabling quantifiers on sequences:

```
(ab)+       one or more repetitions of "ab"
(foo|bar)   matches "foo" or "bar"
(\d{2}\.){3}\d{2}   matches "12.34.56.78"
```

Groups are non-capturing. They affect matching structure only.

### Alternation

The pipe `|` separates alternatives. The match tries both sides and takes the longest:

```
foo|bar         matches "foo" or "bar"
cat|dog|fish    matches "cat", "dog", or "fish"
\d+|\w+         matches a run of digits or a run of word characters
```

Alternation has the lowest precedence:

```
ab|cd           matches "ab" or "cd" (not "a(b|c)d")
(ab|cd)ef       matches "abef" or "cdef"
```

### What is Not Supported

The following regex features are not available:

- Lazy quantifiers (`*?`, `+?`, `??`)
- Capturing groups and backreferences
- Lookahead and lookbehind (`(?=...)`, `(?!...)`, `(?<=...)`, `(?<!...)`)
- Non-capturing group syntax (`(?:...)`) — plain `()` groups are already non-capturing
- Anchors (`^`, `$`)
- Word boundaries (`\b`, `\B`)
- Unicode categories (`\p{...}`)
- Named classes (`[:alpha:]`)
- Flags or modifiers (`(?i)`, `(?m)`)

## Reading Output

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

## Example: Semver Versions

```gml
var _tokenizer = new GPUTokenizer();

_tokenizer.addPattern(@'\d+\.\d+\.\d+');
_tokenizer.addPattern(@'\w[\w\d\-]*');
_tokenizer.addDelimiter(@' \t\n');

_tokenizer.compile();
```

## Example: IP Addresses and Numbers

```gml
var _tokenizer = new GPUTokenizer();

_tokenizer.addPattern(@'(\d{1,3}\.){3}\d{1,3}');
_tokenizer.addPattern(@'\d+\.\d+');
_tokenizer.addPattern(@'\d+');
_tokenizer.addPattern(@'\w+');
_tokenizer.addDelimiter(@' \t\n');

_tokenizer.compile();
```

## Notes

* The intended workflow is compile once, tokenize many times.
* `outputLength` is the authoritative bound when reading the returned buffer.
* `tokenizeBuffer()` is preferred when your input already exists as raw bytes.
* Delimiters split tokens.
* Ignore rules remove bytes entirely.
* Context rules are best used for strings and comments.
* Multiple patterns are combined into one NFA. The tokenizer always takes the greedy longest match across all patterns at each position.
* Pattern matching uses a Thompson NFA with exact semantics. There are no false positives or ambiguous merges.

## Credits

Special thanks to Terpatin / HannulaTero for inspiring this project through the GPUTF8 library:

[GPUTF8](https://github.com/HannulaTero/GPUTF8)
