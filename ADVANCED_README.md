# GPUTokenizer - Advanced Notes

This document is for developers who want to extend the tokenizer, debug its behavior, or understand how the internals are laid out. The current implementation is no longer the older merge-table compiler design. Patterns are now compiled on the CPU into a Thompson-style NFA program, uploaded as a packed program texture, and then consumed by a two-pass GPU runtime: a match-length pass and a token assembly pass. 

## High-level architecture

There are now three main stages:

1. Rule authoring in GML
2. CPU-side compile into a packed program buffer
3. Two GPU runtime passes:
	- `sh_gpu_match`
	- `sh_gpu_tokenize` 

At a high level, the flow is:

- `addPattern()` stores raw regex strings in `patternRegexes`
- `addContextPattern()` serializes context metadata into `bufCtx`
- delimiter and ignore rules are recorded into `bufTypeMap`
- `compile()` builds a Thompson-style NFA for all patterns, packs states/classes/type/context data into `bufProgram`, then uploads that as `surfProgram`
- pass 1 computes the best pattern match length starting at each source byte
- pass 2 assembles final token bytes using the match-length texture plus context, delimiter, ignore, and unmatched handling 

The intended runtime model is still compile once, tokenize many times. The difference is that compile is now CPU-side NFA construction rather than a shader pass that derives merge tables. 

## Internal state on the GML side

The constructor now owns a different set of core resources than the older design. The important ones are:

- `surfSource`
- `surfMatch`
- `surfOutput`
- `surfProgram`
- `bufCtx`
- `bufTypeMap`
- `bufProgram`
- `patternRegexes`
- offset fields such as `stateTableOff`, `classTableOff`, `typeMapOff`, `ctxStartOff`, `ctxIndexOff`, and `ctxDataOff` :contentReference[oaicite:4]{index=4}

A useful mental model is:

- `patternRegexes` holds pattern source text
- `bufCtx` holds serialized context rules
- `bufTypeMap` holds byte classification for delimiter / ignore
- `bufProgram` is the final compiled program image that both shaders consume 

## Rule authoring model

### Patterns

Patterns are no longer flattened directly into a common compile byte stream during `addPattern()`. Instead, the raw regex text is stored and deferred until `compile()`, where `buildPatternNFA()` turns each pattern into an NFA fragment. 

This is the most important architectural change from the old system.

### Contexts

Contexts are still serialized immediately into `bufCtx` during `addContextPattern()`. Each context stores:

- open string
- close string
- escape string
- a flags byte for `keepOpen`, `keepClose`, and `keepEscape` :contentReference[oaicite:7]{index=7}

Contexts are later packed into the compiled program buffer as:

- context start map
- context index
- context data tail 

### Delimiters and ignores

Delimiter and ignore rules are recorded into `bufTypeMap`, which is a 256-byte byte-classification table. The current code writes delimiter membership with value `1` and ignore membership with value `2`. Pattern bytes are classified separately during program packing and shader-side matching. 

## CPU compile stage

`compile()` now performs several jobs in sequence.

### 1) Build per-pattern NFA fragments

For each regex in `patternRegexes`, `compile()` calls `buildPatternNFA()` and collects the resulting fragments. These fragments are later combined into a master start graph. If there are no patterns, compile emits a trivial `MATCH` state so that the program remains structurally valid. If there are multiple patterns, they are combined through explicit branching. :contentReference[oaicite:10]{index=10}

### 2) Build class tables

Character classes are stored separately from the state table. The compile step collects the 256-byte class membership buffers produced while building pattern NFAs and writes them into the program buffer after the state table. :contentReference[oaicite:11]{index=11}

### 3) Pack the program buffer

After NFA construction, the compiler packs everything into `bufProgram`. The code tracks and stores:

- header bytes
- state table
- class table
- type map
- context start map
- context index
- context data 

### 4) Upload the program texture

Once `bufProgram` is complete, compile calculates the required power-of-two-ish texture dimensions, creates or recreates `surfProgram`, and uploads the packed bytes into that surface. Runtime passes then sample this surface as a byte-addressed program texture. 

## Thompson NFA representation

The current implementation is structurally closer to Thompson construction than the old group/merge-table system. `buildPatternNFA()` emits fragments with:

- a `start` state
- an `outs` list of unresolved outgoing edges to patch later :contentReference[oaicite:14]{index=14}

The runtime and compiler currently use six opcodes:

- `MATCH`
- `CHAR`
- `CLASS`
- `ANY`
- `JUMP`
- `SPLIT` 

In packed form, each state occupies four bytes:

- opcode
- edge A
- edge B
- data 

The meaning of those fields depends on opcode:

- `CHAR` uses `data` as the byte to match and `A` as the next state
- `CLASS` uses `data` as the class index and `A` as the next state
- `ANY` uses `A` as the next state
- `JUMP` uses `A` as the jump target
- `SPLIT` uses `A` and `B` as branch targets
- `MATCH` is terminal 

## Packed program layout

The current program texture is not the old lookup texture. It is a packed program image.

At a high level the layout is:

1. Header
2. State table
3. Class table
4. Type map
5. Context start map
6. Context index
7. Context data 

### Header

The first four bytes store:

- `numStates` low byte
- `numStates` high byte
- `startState`
- `numClasses` 

### State table

Immediately after the header comes the packed NFA state table. Each state is 4 bytes wide. The match shader reads these entries through `readState()`. :contentReference[oaicite:20]{index=20}

### Class table

After the state table comes the class table. Each class is a 256-byte membership bitmap addressed by byte value. `CLASS` states refer to these class tables by class index. The match shader checks them with `classMatches()`. 

### Type map

The type map is still present, but its role is now narrower than before. It is used by the runtime to classify bytes as unmatched, delimiter, or ignore during token assembly. It is no longer the main mechanism for pattern continuation. 

### Context start map, context index, context data

Contexts are still encoded through a two-level index plus string tail:

- context start map gives the first candidate rule for a starting byte
- context index stores offset / next-rule / flags metadata
- context data stores the open, close, and escape strings themselves 

This part of the design is still conceptually similar to the old system, but it now lives inside the single packed program texture rather than inside a merge-table lookup layout. 

## GPU pass 1 - `sh_gpu_match`

The first runtime pass computes match lengths, not tokens.

For each source position, `sh_gpu_match`:

- skips positions past the end
- skips delimiter and ignore starts by consulting the type map
- seeds the NFA state set from `u_startState`
- computes epsilon closure
- simulates the NFA forward byte by byte
- tracks the best reachable `MATCH` length
- writes the final match length packed into two bytes 

This is the core replacement for the old merge-table model. Pattern continuation is no longer inferred from pairwise byte compatibility. Instead, pass 1 explicitly asks:

“Starting at byte `i`, what is the best NFA match length?” 

### State-set simulation

The shader keeps two fixed-size state arrays:

- `curr[64]`
- `next[64]` :contentReference[oaicite:27]{index=27}

It first computes epsilon closure on `curr`, then for each source byte computes transitions into `next` for:

- `CHAR`
- `CLASS`
- `ANY` 

After each byte step, it runs epsilon closure on `next` again and checks whether any reachable state is `MATCH`. If so, the current `bytesConsumed` becomes the best length seen so far. The final length is packed into two bytes as low and high parts. :contentReference[oaicite:29]{index=29}

### Why this pass exists

This pass is the main architectural upgrade. It allows the tokenizer to work from explicit match spans rather than from raw byte adjacency tables. That makes quantified and branching patterns much more principled than in the older design. 

## GPU pass 2 - `sh_gpu_tokenize`

The second pass assembles final output bytes.

It consumes:

- the source texture
- the program texture
- the match-length texture from pass 1
- unmatched mode and offset metadata uniforms 

Its job is not to run the NFA. That already happened in pass 1. Instead, pass 2 decides what byte should appear at each output position.

### Main flow

In normal mode, pass 2:

1. checks whether a context opener matches at the current source position
2. if a context matched, enters context mode
3. if already in an NFA token span, emits bytes until that span ends
4. otherwise checks type map for ignore / delimiter handling
5. queries `getMatchLen(fi)`
6. if match length is positive, begins a new NFA token span
7. otherwise falls back to unmatched-mode behavior 

This is the current token assembly model. The older explanations about `canMerge`, `canStartMerge`, previous byte, and start byte are obsolete and should not appear in the new advanced documentation. The live code now keys off explicit match lengths instead. 

### Context handling

Context handling still lives in pass 2 and is still a separate mechanism from the NFA.

When a context opener matches, pass 2:

- terminates any active unmatched run or NFA span
- optionally emits the opener if `keepOpen` is set
- resolves close and escape string offsets from context data
- enters context mode
- later handles escapes first, closers second, and raw byte emission otherwise
- optionally emits close / escape sequences depending on flags
- emits a zero byte to terminate the token when the context closes 

An important behavioral point: context openers are checked at every position, even when scanning normal text, and they take priority. If a context opener appears while an NFA token or unmatched run is active, pass 2 explicitly terminates that token first. 

That is intentional. The system is hybrid:

- NFA patterns handle normal tokens
- contexts handle string/comment-style regions with explicit opener/closer logic 

## Output format

The final output surface is read back into a CPU buffer. Public code then reads it as consecutive `buffer_string` values until `outputLength`.

In practice, token boundaries are represented by zero bytes between token runs, which is why output reading works through repeated `buffer_read(..., buffer_string)`. 

## Runtime surfaces and buffers

At runtime, the system maintains separate surfaces for:

- source bytes
- match lengths
- final output bytes
- compiled program bytes :contentReference[oaicite:38]{index=38}

The typical tokenize path is:

1. ensure or recreate source/output/match surfaces
2. ensure the program surface exists
3. upload source bytes via `bufPad`
4. run `sh_gpu_match` into `surfMatch`
5. run `sh_gpu_tokenize` into `surfOutput`
6. read `surfOutput` back into a CPU buffer 

So compared with the old design, runtime now pays for an additional intermediate pass and surface.

## Current hard limits

The new architecture is more correct, but it has several concrete ceilings.

### 1) Active state-set size is capped at 64

The match shader uses fixed arrays:

- `curr[64]`
- `next[64]` :contentReference[oaicite:40]{index=40}

So shader-side state-set simulation is currently capped at 64 tracked states.

### 2) Epsilon closure is capped at 16 passes

Both initial and per-step epsilon closure run with a fixed loop of 16 passes. Very deep epsilon chains could therefore exceed the closure budget. 

### 3) Match scanning uses a fixed outer bound

Per-start-position NFA simulation uses an outer loop capped at `65535`. That places a hard ceiling on how far a single match can extend. 

### 4) Context sequence scanning is bounded

Context open, close, and escape matching use fixed loops up to 1024 bytes. Very long context delimiters are therefore not supported. 

### 5) Several indices are byte-sized

State edges, several program fields, and parts of the context index are stored as compact byte-sized values, with `255` acting as a null / invalid sentinel in the live program logic. That keeps packing simple, but it constrains scale. 

### 6) Context data offsets are effectively 16-bit

Context index decoding reconstructs offsets from two bytes, so total serialized context data is effectively capped by a 16-bit offset range unless that encoding changes. 

### 7) The system is still strictly byte-oriented

Everything still operates on byte values from `0..255`, membership tables, and byte-addressed packed textures. This is not a codepoint-aware Unicode engine. 

## Tradeoffs in the new design

The old design favored compile-time lookup-table generation to simplify tokenize-time decisions. The new design makes a different trade:

- compile is now more complex because it constructs an actual NFA program
- runtime is now two GPU passes instead of one
- pass 1 is more expensive than simple byte adjacency checks
- pattern correctness is better because matching is based on explicit NFA simulation instead of merge heuristics 

In short:

- **old design** favored simpler runtime at the cost of pattern fidelity
- **new design** favors better pattern semantics at the cost of a heavier runtime pipeline 

## Known pain points

The current implementation has a few areas contributors should be aware of.

- State-set simulation is bounded by fixed shader arrays rather than dynamically sized sets. :contentReference[oaicite:49]{index=49}
- Epsilon closure is iterative and bounded, not unbounded. 
- Two-pass tokenization means more GPU bandwidth and another intermediate surface. 
- Context handling is intentionally separate from the NFA language, so the full system is hybrid rather than a single unified regex engine. 
- Compact byte-sized packing keeps the program small but imposes hard ceilings on state references and metadata ranges. 

## When to change the architecture

The current design is a good fit when you want:

- compile-once, tokenize-many behavior
- byte-oriented tokenization
- explicit string/comment contexts
- richer pattern behavior than the old merge-table approach provided 

You would likely need a different architecture if you need:

- much larger active NFAs
- deeper epsilon-heavy graphs
- very large context metadata
- codepoint-aware text handling
- nested grammar features rather than tokenizer-grade state 

## Summary

The current GPUTokenizer design is:

- CPU-side rule compilation into a packed program image
- Thompson-style NFA simulation in GPU pass 1
- token assembly plus context handling in GPU pass 2 

That is the core design to document going forward. The older merge-table explanation, compile shader description, and start-merge logic are no longer representative of the current system and should be removed from the advanced documentation. 
