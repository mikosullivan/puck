# MVM spec

~~~vibecode
{"vibecode": {
	"doc": "ideas_mvm_spec",
	"role": "working notes for the MVM state hash's exact shape as we build it out — companion to requirements/mvm/ which owns the settled spec. Landing pad for design questions surfaced during implementation (roles-tree bootstrap, ast referencing, sequence-counter starting value, primitive-slot location, src on identity objects, etc.) before they get promoted to requirements.",
	"status": "landing initial state-hash shape 2026-08-06 — roles bootstrap + field roster + AST access model captured; parent-child edge semantics for the roles tree still open"
}}
~~~

Companion to [requirements/mvm/](https://www.puck.uno/requirements/mvm/). Captures the design decisions we're making as we build the MVM machinery, before they're settled enough to move into `requirements/`.

## The state hash

`state.new()` (in [src/engine/state.lua](../../src/engine/state.lua)) returns the MVM state hash — the single top-level table every field of Caspian's execution state lives inside. V1.0 in-memory shape:

~~~lua
{
    roles      = <Trivet root node>,   -- role hierarchy
    srcs       = {},                   -- source-file interning registry
    objects    = {},                   -- every live object's record, keyed by ID
    references = {},                   -- ref_id → target_id pointers
    call_stack = {},                   -- frames + in-flight exceptions
    gc_errors  = {},                   -- on_close handler failures
    asts       = {},                   -- CaspM trees keyed by ast_id
    sequence   = <Sequence>,           -- shared ID counter (see § The Sequence)
}
~~~

Every field is present at construction with its empty representation, so downstream code can insert / walk / read without existence checks.

## Roles as a Trivet tree

Roles live in a [Trivet](../../src/engine/trivet.lua) n-ary tree rather than a flat hash. Each node's `.value` carries the role's metadata; parent-child edges organize the role graph.

Initial tree at engine construction:

~~~
engine (root)
└── user
~~~

Every additional role (loaded library, faucet, delegation target) becomes a child of whichever existing role loaded / spawned it.

**Node value shape.** Currently a [Role](../../src/engine/roles.lua) instance — a metatable-backed object with a `.name` field. `roles.new(name)` is the constructor; `state.new()` calls it during bootstrap to seed the initial tree with `engine` at the root and `user` as its child. Per-role metadata (trust webs, capability grants, etc.) grows onto the Role object as those features land.

**Parent-child edge semantics.** Not pinned. The bootstrap tree (engine → user) is minimal enough to work under any reasonable reading — loading provenance, trust cascade, namespace / addressing. Commit to a specific meaning when the first feature that depends on it lands.

## AST storage and access

The `asts` field is the top-level hash the [requirements § The AST lives in MVM](https://www.puck.uno/requirements/mvm/#the-ast-lives-in-mvm) section left TBD-named. Named `asts` here — plural of ast, matches the `srcs` naming pattern.

Each entry pairs the CaspM tree with the src_key for the file it came from:

~~~json
"asts": {
    "1": {"src_key": "a", "body": <CaspM tree — top-level program from main.casp>},
    "2": {"src_key": "a", "body": <CaspM tree — &foo body, defined in main.casp>},
    "3": {"src_key": "b", "body": <CaspM tree — &to_html body from library>}
}
~~~

**Frame → callable → ast chain.** A frame's `callable` slot holds an object ID; the callable object (Function / Method / Closure) carries `bucket.ast = <ast_id>`; the ast entry in `state.asts` holds the tree to walk. Two lookups from frame to code.

**src_key propagation.** The ast's `src_key` combines with each currently-executing CaspM node's `line` to form the `[src_key, line]` tuple stamped on every value born during that frame's execution. Cheap: one string + one integer per value, interned back to the full path via `state.srcs`.

**Uniform across first-file and library.** Top-level code from `main.casp` and function bodies from a loaded library both live in `asts`, each carrying the src_key of their originating file. Frames don't distinguish "user code" from "library code" via the ast field — they just point at the ast_id.

**Note on the requirements examples.** The mid-execution walkthrough at [requirements/mvm/](https://www.puck.uno/requirements/mvm/#worked-example-mvm-mid-execution) shows frames carrying `"function": "greet"` — a name string — rather than a callable object ID. Read as a readable-snapshot shorthand rather than the real runtime shape (dispatch by walking the lexical chain and re-resolving the name at every step would be expensive; caching the resolved callable ID on the frame at call time is essentially free and matches the object-and-reference pattern used everywhere else).

## The Sequence

`state.sequence` is a [Sequence](../../src/engine/sequence.lua) — a small object that encapsulates the shared program-wide ID counter. At rest, the Sequence's `value` is the next ID to hand out; every allocation site calls `state.sequence:next()`, which returns the current value and advances the counter internally. First call after `state.new()` returns `"1"`; subsequent calls return `"2"`, `"3"`, and so on.

Explicit `state` at each allocation site gets tiring fast; wrapping the counter as an object keeps the call site to `state.sequence:next()` (the caller already has state in hand as a property access, not a re-threaded arg).

The counter is stored as a decimal string so it grows indefinitely without bigint machinery, per [references § Object IDs](https://www.puck.uno/requirements/mvm/references#object-ids). The internal increment routine walks digits right-to-left, carries on 9s, and grows the string when the whole thing was 9s — no `tonumber` / `tostring` round-trip, so the counter grows past `2^53` (Lua 5.4's integer-vs-float boundary) with no precision loss.

Nested-object platter IDs use UUIDs instead ([objects § Object IDs](https://www.puck.uno/requirements/mvm/objects#object-ids)) — the Sequence is only for slots where the ID isn't user-visible.

## Field summary

| Field | Type | Purpose |
|---|---|---|
| `roles` | Trivet root node | Role hierarchy; `engine` at root, `user` as its child |
| `srcs` | hash | Source-file interning registry (`src_key → {file\|uns: path}`) |
| `objects` | hash | Live object records (`object_id → {role, src, bucket, stack}`) |
| `references` | hash | Reference pointers (`ref_id → target_id`) |
| `call_stack` | array | Frames + in-flight exceptions |
| `gc_errors` | array | `on_close` handler failures |
| `asts` | hash | CaspM trees (`ast_id → {src_key, body}`) |
| `sequence` | Sequence object | Shared ID counter; `:next()` returns then increments |
