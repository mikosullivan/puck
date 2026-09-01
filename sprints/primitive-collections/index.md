~~~vibecode
{"vibecode": {
	"doc": "sprint-index",
	"sprint": "primitive-collections",
	"role": "Sprint for extending the `primitive` atom in the refactored CaspM to carry hash and array literals in addition to scalars. Split out of `caspm-method-refactor` because the scalar case can land first without settling the collection case. Deferred until the CaspM refactor's core atoms (scalar primitive, var, rv, frame) are settled and working.",
	"status": "not yet started"
}}
~~~

# primitive-collections

Sprint for adding hash and array literals to the `primitive` atom's payload space.

## Background

The [caspm-method-refactor](../caspm-method-refactor/) sprint settled the `primitive` atom for scalar payloads:

- `{primitive: "foo"}` — String
- `{primitive: 42}` — Number
- `{primitive: true}` — Boolean
- `{primitive: null}` — Null

The idea of extending the same atom key to carry collection payloads came up while writing that sprint's atom-key spec:

- `{primitive: {a: 1, b: 2}}` — a Hash literal
- `{primitive: ["a", "b", "c"]}` — an Array literal

Reads well — one atom kind covers every built-in literal construction. But it opens design questions that would slow down the CaspM refactor if they had to be answered as part of it. Split into its own sprint.

## Open questions to answer here

- **Discriminating hash vs array in JSON.** JSON serializes both as similar-looking structures but Lua distinguishes on integer-vs-string keys. What's the rule for reading `{primitive: X}` when X is a table — is a Lua array (integer-keyed, contiguous from 1) an Array primitive, a Lua hash a Hash primitive? What about the empty-collection edge case (`{primitive: {}}`)?
- **Recursive primitives.** Are the values inside a hash/array primitive themselves atoms (`{primitive: {a: {primitive: 1}}}`) or raw literals (`{primitive: {a: 1}}`)? The recursive form is uniform but verbose; the raw form matches the "atom payload is JSON literal" framing.
- **What method dispatches to build the collection.** When the engine sees `{primitive: {a: 1}}` in a value step, does it call `Hash.new(...)` internally? Or is the collection materialized directly via CVM primitives (`add_hash` + refs)? Trade-off: uniformity through the class registry vs a faster path for built-in construction.
- **Mutability.** Are Hash / Array literals materialized as MUTABLE collections (user can add / remove keys) or FROZEN literal-derived instances? Language design decision that affects the constructor's shape.
- **Nesting.** A hash-of-arrays, an array-of-hashes, arbitrarily nested. Does one `{primitive:X}` atom construct the whole tree in one step, or does each sub-collection get its own atom?

## Not urgent

Sprint is queued behind the [caspm-method-refactor](../caspm-method-refactor/) sprint, which needs its four core atoms (`primitive`, `var`, `rv`, `frame`) to settle first. Nothing to build here yet.
