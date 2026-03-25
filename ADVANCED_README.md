# GPUTokenizer - Advanced Notes

This document is for contributors and integrators who need to understand how the tokenizer is implemented internally. The system is built as a two-stage GPU pipeline: GML writes a compact binary rule stream into a grow buffer, the compile shader turns that stream into a lookup texture, and the tokenizer shader uses that lookup texture to walk source bytes and emit token strings. The constructor itself does not build large intermediate structs or maps for rule compilation; it writes bytes directly into `bufCompile`.

## High-level architecture

There are three main moving parts:

1. **Rule authoring in GML**

   * `addPattern`
   * `addContextPattern`
   * `addDelimiter`
   * `addIgnore`
   * `setUnmatchedRule`

2. **Compile pass**

   * uploads the raw compile buffer as a texture
   * runs `sh_gpu_compile`
   * produces a packed lookup texture

3. **Tokenize pass**

   * uploads source bytes to a source surface
   * runs `sh_gpu_tokenizer`
   * reads back the output surface as a string buffer

The intended runtime model is compile once, tokenize many times. Recompilation is only needed when rules change or when the lookup surface is lost.

## Rule compilation in GML

Each public `add*` call appends binary data directly into `bufCompile`. The format is byte-oriented and intentionally simple:

* `PATTERN`: `0x01 | numGroups(u8) | [repeats(u8) | membership(256 bytes)] x groups`
* `CONTEXT`: `0x02 | open\0 | close\0 | escape\0 | flags(u8)`
* `DELIMITER`: `0x03 | membership(256 bytes)`
* `IGNORE`: `0x04 | membership(256 bytes)`
* `END`: `0x00` 

For patterns, each group becomes a 256-byte membership table, one byte per possible byte value. Membership is stored as `0` or `255`. The parser in `addPattern` expands bracket expressions, negated sets, ranges, shorthand classes, dot, and repetition markers directly into those tables. Repetition is stored per group as a single byte before the 256-byte membership block.

Context rules are stored differently. They serialize three null-terminated strings - open, close, and escape - followed by a bitfield byte for `keepOpen`, `keepClose`, and `keepEscape`. Context bookkeeping is tracked separately through `ctxRuleCount`, `ctxDataBytes`, and later `ctxDataOffset`.

Delimiter and ignore rules are just one 256-byte membership table each. They use the same membership-writing helpers as pattern parsing, but without the group/repeat structure. 

## Why membership tables are 256 bytes

The whole implementation is byte-based. Every rule ultimately answers questions of the form:

* does this rule match byte `B`?
* can byte `A` merge into byte `B`?
* can a token that starts with byte `S` later include byte `C`?

Using a full 256-byte table per rule group makes those checks simple to evaluate in shaders. It is memory-heavy compared with compressed encodings, but it removes decode complexity in both compile and tokenize stages. 

## Lookup texture layout

The compile shader produces a single packed lookup texture with this layout:

* **Byte 0**: type map, 256 bytes
* **Byte 256**: merge table, 65536 bytes
* **Byte 65792**: start-merge table, 65536 bytes
* **Byte 131328**: context start map, 256 bytes
* **Byte 131584**: context index, `N x 4 bytes`
* **Variable tail**: context data strings 

The important design change in the current architecture is that merge logic operates on **raw byte values**, not on symbolic class IDs. That removed the older class/signature assignment model entirely. The type map now only needs four states: unmatched, delimiter, ignore, and pattern. 

## What each lookup region means

### Type map

The type map answers: what is this byte in the general tokenizer sense?

* `0` unmatched
* `1` delimiter
* `2` ignore
* `3` pattern byte 

The compile shader computes this by scanning the serialized rules in order. Ignore and delimiter can return immediately. Pattern membership marks the byte as pattern-matched. 

### Merge table

The merge table answers: can byte `A` be followed by byte `B` inside the same token?

This is computed by walking every pattern rule and checking:

* self-merge for repeating groups
* sequential merge between adjacent groups 

When unmatched mode is `CONCATENATE`, the compile shader also marks unmatched-to-unmatched byte pairs as mergeable. 

### Start-merge table

The start-merge table answers: if a token starts with byte `S`, is byte `C` ever valid anywhere in that token's pattern?

This helps the tokenizer avoid invalid growth when later bytes would match a different rule shape but not the rule implied by the token start. In practice, the tokenizer checks both `canMerge(prev, cur)` and `canStartMerge(start, cur)` before extending a token.

### Context start map

This maps the first byte of an opener to the first context rule index that can start on that byte. If multiple context rules share the same first byte, the compile shader chooses the longest opener first and links shorter candidates through the context index chain. 

### Context index

Each context rule gets four bytes of metadata:

* context data offset low byte
* context data offset high byte
* next fallback rule index
* flags byte 

The fallback index is used when multiple context rules share the same first byte. The tokenizer tries the longest opener first, then falls through to shorter alternatives if the longer one does not match the actual input bytes. 

### Context data

This is the serialized concatenation of all context strings:

* open string + null
* close string + null
* escape string + null 

The tokenizer uses offsets from the context index to fetch opener/closer/escape bytes directly from this tail region. 

## Compile shader flow

The compile shader reads from the uploaded compile buffer texture using byte-addressed fetch helpers, then writes the packed lookup texture. Its internal helpers do four main jobs:

* `skipString`: walk a null-terminated string
* `skipRule`: skip a full serialized rule
* `computeType`
* `computeMerge`
* `computeStartMerge`
* `computeCtxStart`
* `computeCtxIndex`
* `computeCtxData` 

The shader works by reconstructing rule meaning directly from the serialized byte stream. There is no separate CPU-side preprocessing step that expands into large rich structures first. That keeps the CPU compiler path straightforward, but it means the compile shader does a lot of repeated scanning work. That tradeoff is acceptable because compile is meant to be much less frequent than tokenize.

## Tokenizer shader flow

The tokenizer shader receives:

* source texture dimensions
* output texture dimensions
* total source byte count
* unmatched mode
* lookup texture dimensions
* context data offset
* the compiled lookup texture bound as `u_texLookup`

Its main loop is output-driven. For each output byte position, it scans forward through the source stream until it determines what byte belongs at that output position. The core state machine tracks:

* current output position
* whether it is currently inside a token
* the previous byte
* the starting byte of the current token
* whether it is inside a context
* context close offset / length
* context escape offset / length
* keep-close / keep-escape behavior
* skip counts for matched opener/closer/escape sequences

In normal mode, the tokenizer:

1. checks whether the current byte begins a context
2. if not, fetches its type from the type map
3. ignores ignored bytes
4. uses delimiters to terminate tokens
5. applies unmatched-mode behavior
6. uses both merge tables to decide whether a token continues or ends

In context mode, the tokenizer:

1. checks escape first
2. checks close second
3. otherwise emits raw context bytes
4. respects `keepClose` and `keepEscape`
5. exits context when a closer is matched

## Why both merge tables exist

Using only adjacency merge would allow patterns to drift into shapes that match locally but not globally. The second table constrains token growth by the token's starting byte.

That combination is what lets patterns like identifiers, numeric forms, and multi-group operator classes behave more consistently without keeping full per-rule runtime state in the tokenizer shader. It is a space-for-simplicity tradeoff.

## CPU-side runtime path

After compilation, tokenization from GML is:

1. compute required source surface size from byte count
2. compute required output surface size from `byteLen * 2`
3. recreate source/output surfaces if dimensions changed
4. recreate/compile lookup if the lookup surface was lost
5. copy input bytes into a padded upload buffer
6. upload the source surface
7. run tokenizer shader
8. read back the output surface into a CPU buffer
9. set `outputLength = byteLen * 2` 

A few implementation choices matter here:

* source and output surfaces are sized to power-of-two-ish square textures derived from total pixels
* `bufPad` is reused for source upload
* the output buffer is newly created per tokenize call
* lookup recompilation is tied to surface loss detection

## Output format

The tokenizer shader writes bytes into the output surface. After readback, the caller interprets the result as consecutive `buffer_string` values and reads until `outputLength`. In practice, token boundaries are represented by zero bytes between token runs, which is why the public reader loop can repeatedly call `buffer_read(..., buffer_string)`.

## Limitations

These are the main implementation limits currently visible in the architecture.

### 1) Input size is bounded by shader loop ceilings

The tokenizer shader uses bounded nested loops. The implementation notes call out a practical ceiling of about `65535 x 256`, roughly 16 MB of input per tokenize call. This is a loop-structure constraint, not just a buffer-size preference. 

### 2) Context strings are bounded

Context open, close, and escape sequences are effectively bounded by the fixed 1024-iteration loops used in shader-side string walking and matching. Very long delimiters are therefore not supported. 

### 3) Context data offset is effectively 16-bit

The context index stores the data offset as two bytes, low and high. That caps total serialized context data at 65535 bytes unless the index format changes. 

### 4) Compile shader rule count is bounded

Several compile-shader scans use loop bounds of 256 rules. That places a practical cap on the number of serialized rules in the compile buffer. 

### 5) Pattern group count is bounded

Pattern scanning in the compile shader uses a fixed loop bound of 32 groups. Larger patterns would need wider shader bounds or a different representation. 

### 6) Surface volatility is part of the design

Because lookup, source, output, and compile all rely on surfaces, surface loss has to be handled. The current implementation recompiles the lookup when needed, but this is still a runtime concern, not an abstract possibility.

### 7) The system is strictly byte-oriented

Everything is framed around 256 possible byte values, fixed membership tables, and raw byte adjacency. That keeps shader logic simple, but it also means the tokenizer is not operating on higher-level Unicode code points internally. 

## Tradeoffs that shaped the implementation

### Raw byte merge tables replaced class/signature IDs

The current system explicitly moved away from class/signature assignment and toward raw byte-level merge tables. This costs space - two 65536-byte tables - but it substantially simplifies the tokenizer runtime and avoids a whole extra indirection layer. 

### Compile cost is accepted to simplify tokenize cost

The compile shader does repeated rule scanning and builds a fairly large lookup texture, but tokenize then becomes a mostly table-driven walk. That is the right trade when rule sets are relatively stable and tokenization is frequent.

### CPU rule writing stays simple

The GML layer writes bytes directly into `bufCompile` rather than constructing more elaborate intermediate data. That keeps the CPU side easy to reason about and easy to serialize into the compile shader's expected input format.

## Known pain points during development

The current architecture exposes a few areas that are functionally fine but were clearly costly or awkward during development:

* pattern parsing in `addPattern` is string-heavy and uses repeated `string_char_at` plus many `buffer_poke` calls
* the lookup texture is large because both merge tables are full byte-by-byte grids
* context support is powerful enough for strings and comments, but its metadata model is intentionally narrow
* the tokenize path still pays for GPU upload and GPU-to-CPU readback on every call

Those are not accidental leftovers. They are direct consequences of favoring a simple byte-addressed GPU runtime over a denser but more complicated model. 

## When to change the architecture

The current design is a good fit when:

* rules are relatively stable
* inputs are large enough to justify GPU work
* byte-oriented tokenization is sufficient
* contexts are simple opener/closer/escape forms

You would likely need a different architecture if you need:

* deeper Unicode semantics
* more than 256 rules
* more than 32 groups per pattern
* much larger context metadata
* nested context grammars
* parser-grade state rather than tokenizer-grade state

## Summary

The core idea is straightforward:

* serialize rules into a byte buffer
* compile them into a dense GPU lookup texture
* tokenize by table lookups and context matching rather than by re-evaluating rules directly at runtime

Most of the implementation details - 256-byte membership tables, dual merge tables, compact context index entries, and shader loop bounds - come from that one design decision. The result is a tokenizer that is simple to feed from GML, predictable to execute on the GPU, and bounded by a set of very concrete architectural limits.
