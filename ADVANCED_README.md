# GPUTokenizer - Advanced Notes

This document describes the internal architecture of GPUTokenizer for developers who want to extend the tokenizer, debug it, or understand how the current implementation works.

The current design is a two-pass GPU tokenizer built around a Thompson-style NFA. Pattern rules are compiled on the CPU into a packed program buffer, uploaded to a GPU surface, then executed in two passes:

1. match-length generation
2. token assembly

This replaced the older merge-table approach. Pattern matching is now driven by explicit NFA simulation rather than byte-adjacency heuristics.

---

## Architecture Overview

The tokenizer is split into three major stages:

### 1) Rule authoring

The public API builds the tokenizer definition:

- `addPattern()`
- `addContextPattern()`
- `addDelimiter()`
- `addIgnore()`
- `setUnmatchedRule()`

Patterns are stored as regex strings and compiled later. Context rules, delimiter bytes, and ignore bytes are tracked separately so they can be packed into the compiled program image.

### 2) CPU-side compile

`compile()` performs the real compiler stage. It:

- parses pattern regexes
- builds Thompson-style NFA fragments
- combines them into a single executable NFA
- packs states, classes, type data, and context metadata into a single byte buffer
- uploads that buffer into the program surface

### 3) GPU runtime

Tokenization runs in two passes:

#### Pass 1 - Match lengths
For each source byte position, the GPU simulates the NFA forward and computes the best greedy match length starting at that position.

#### Pass 2 - Token assembly
The GPU scans the source again, consumes the match-length texture, applies delimiter/ignore/unmatched behavior, and emits final token bytes. Context rules are resolved here and take priority when they match.

The intended runtime model is still compile once, tokenize many times.

---

## Internal Data Model

The tokenizer maintains four main kinds of compiled data:

- NFA state table
- class tables
- type map
- context metadata

All of these are packed into a single program buffer and uploaded into the program surface for shader access.

### CPU-owned compile data

The important CPU-side structures are:

- a list of pattern regex strings
- serialized context data
- a byte classification table for delimiter / ignore behavior
- the final packed program buffer

### GPU runtime surfaces

The runtime uses separate surfaces for:

- source bytes
- compiled program bytes
- match lengths
- final token output

---

## Pattern Compilation

Pattern compilation is handled during `compile()`, not during `addPattern()`.

Each pattern is converted into a Thompson-style NFA fragment. Fragments are built from:

- a start state
- a list of unresolved outgoing edges to patch later

The implementation uses the following state opcodes:

- `MATCH`
- `CHAR`
- `CLASS`
- `ANY`
- `JUMP`
- `SPLIT`

These are enough to represent the current regex feature set cleanly in NFA form.

### Supported structural concepts

The pattern compiler is built around standard fragment construction for:

- literals
- character classes
- dot
- concatenation
- alternation
- `*`
- `+`
- `?`

The important architectural point is that pattern meaning is now represented as executable NFA states, not as merge tables or byte-pair compatibility data.

---

## Program Buffer Layout

The compiled program is packed into one byte-addressable buffer, then uploaded into a GPU surface.

The packed layout is:

1. header
2. state table
3. class tables
4. type map
5. context start map
6. context index
7. context data

### Header

The header stores the basic program metadata required by the shaders:

- number of states
- start state
- number of classes
- reserved / structural header space

The CPU side also tracks offsets for each major section so the shaders can fetch the correct regions directly.

### State table

Each NFA state occupies 4 bytes:

- opcode
- edge A
- edge B
- data

Field meaning depends on opcode:

- `CHAR`: `data` is the byte to match, `A` is the next state
- `CLASS`: `data` is the class id, `A` is the next state
- `ANY`: `A` is the next state
- `JUMP`: `A` is the jump target
- `SPLIT`: `A` and `B` are the branch targets
- `MATCH`: terminal state

### Class tables

Each character class is stored as a 256-byte membership table indexed directly by byte value.

A `CLASS` state references one of these tables by class id.

### Type map

The type map is a 256-byte classification table used during token assembly. Its current purpose is to identify bytes as:

- unmatched
- delimiter
- ignore

This map is not the main pattern engine. Pattern matching is handled by the NFA match pass.

### Context metadata

Context handling uses three packed regions:

- context start map
- context index
- context data

The context start map selects candidate rules by first byte.

The context index stores per-rule metadata:

- context data offset
- fallback rule index
- flags

The context data region stores null-terminated open, close, and escape strings.

---

## Match Pass

The first shader pass computes greedy match lengths.

For each source position, the match pass:

1. checks whether the start byte is ignorable or a delimiter
2. seeds the NFA with the compiled start state
3. computes epsilon closure
4. simulates the NFA forward byte by byte
5. tracks the furthest reachable `MATCH`
6. writes the best match length into the match texture

This pass exists to answer one question efficiently:

> starting at byte `i`, how many bytes does the NFA match?

That is the core replacement for the old merge-table logic.

### State-set execution

The shader simulates the NFA using fixed-size current and next state sets. After seeding the start state, it repeatedly:

- expands epsilon transitions
- consumes one source byte
- computes next active states
- expands epsilon transitions again
- checks whether any active state is `MATCH`

If so, the current consumed length becomes the best length seen so far.

The final result for that source position is a single greedy match length.

---

## Token Assembly Pass

The second shader pass assembles the final token byte stream.

It consumes:

- source bytes
- compiled program data
- match lengths from pass 1

This pass does not re-run regex logic. It uses the results of pass 1 plus the context/type metadata to produce final output.

### Main flow

When not in context mode, the token assembly pass behaves like this:

1. check whether a context opener matches at the current source position
2. if so, enter context mode
3. otherwise skip ignore bytes
4. terminate tokens on delimiters
5. if a positive match length exists, begin an NFA token span
6. otherwise apply unmatched-mode behavior

The pass inserts zero bytes between token runs so the CPU can later read the output as consecutive `buffer_string` values.

### Context handling

Contexts are handled entirely in pass 2.

When a context opener matches:

- any currently active unmatched run or normal token is terminated
- the opener may be emitted depending on `keepOpen`
- close / escape data is loaded from the packed context region
- the tokenizer enters context mode

While in context mode:

- escape sequences are checked first
- close sequences are checked second
- otherwise raw bytes are emitted into the current token

When the closer is matched, the token is terminated and normal scanning resumes.

### Context priority

Contexts take priority over ordinary pattern scanning.

This is intentional. The engine is hybrid:

- NFA matching handles ordinary token patterns
- dedicated context logic handles strings, comments, and similar delimited regions

Contexts are not represented as part of the regex language itself.

---

## Output Format

The final output surface is read back into a CPU buffer.

That buffer is interpreted as a sequence of null-terminated strings. Public code reads tokens by repeatedly calling `buffer_read(..., buffer_string)` until `outputLength` is reached.

This works because the token assembly pass inserts zero bytes between tokens in the output stream.

---

## Limitations

These are the architectural limitations contributors should keep in mind.

### Byte-oriented engine

The tokenizer operates on bytes. States, classes, and tables are all indexed by byte value. The current design is not codepoint-aware and is not a Unicode text engine.

### Hybrid design

Contexts are not part of the NFA itself. They are a separate, higher-priority tokenization system handled during token assembly. This keeps strings and comments practical, but it means the overall tokenizer is intentionally hybrid.

### Two-pass runtime cost

The current design is more correct than the older merge-table approach, but it costs more at runtime:

- one pass to compute match lengths
- one pass to assemble tokens
- one intermediate surface for match results

### Compact packed fields

The packed program favors compact byte-oriented storage. That keeps the representation simple and cheap to upload, but it also imposes scaling ceilings on state counts, offsets, and metadata ranges.

---

## Current Hard Limits

These are the concrete implementation ceilings in the current build.

### 64 active shader states

The match shader uses fixed-size current and next state arrays of length 64. That is the current active-state budget for runtime NFA simulation.

### 16 epsilon-closure passes

Epsilon closure is iterated with a fixed 16-pass bound. Deep epsilon-heavy graphs can exceed this limit.

### 65535-step NFA scan bound

Per-start-position NFA stepping is bounded by a fixed maximum iteration count. This places a hard ceiling on how far a single match attempt can extend.

### 1024-byte context sequence bound

Context open, close, and escape checks use fixed loop bounds up to 1024 bytes. Very long delimiters are therefore not supported without widening those loops.

### Fixed-width match-length storage

Match lengths are stored in a packed intermediate format rather than as arbitrary unbounded integers. This places a hard ceiling on the maximum representable match span.

### Compact state and metadata references

Several packed references are stored in narrow fields. Extending total state count, context metadata size, or offset range may require widening the program format.

---

## Design Tradeoffs

The older design favored a simpler runtime based on byte-merge lookups. The current one makes the opposite trade:

- compile is more complex
- runtime is heavier
- pattern semantics are much better
- false positives from merge-style approximation are reduced
- contexts remain practical and explicit

This is the right trade if the goal is a more faithful tokenizer rather than the cheapest possible byte-merging system.

---

## Extension Guidelines

If you plan to extend the system, the most important things to preserve are:

- compile-once / tokenize-many workflow
- synchronization between CPU program packing and both shader readers
- separation between NFA matching and context handling
- explicit packed-layout versioning discipline if the program format changes

The most fragile areas are:

- state packing / unpacking
- class table indexing
- context metadata encoding
- match-length encoding
- fixed shader limits

Any change to the packed layout must be reflected everywhere consistently.

---

## Summary

The current tokenizer is best understood as:

- CPU-side compilation into a packed NFA program image
- GPU pass 1 for greedy match-length generation
- GPU pass 2 for token assembly and context handling

That is the model contributors should use when reasoning about the system or extending it.
