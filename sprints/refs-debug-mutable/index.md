~~~vibecode
{"doc": "sprint-index", "sprint": "refs-debug-mutable",
	"role": "Split from the retired close-schema-holes sprint. Carves `debug` out of `refs_no_update`'s WHEN clause so `refs.debug` becomes mutable (matching the already-in-shipping carve-out for `objects.debug`). Debug is an informational label with no query path reading it; freezing it at INSERT-time offered no invariant value.",
	"status": "pre-integration — sprint schema + tests complete; shipping untouched"}
~~~

# refs-debug-mutable

`refs.debug` is a human-readable informational label. No query path reads it. Shipping's `refs_no_update` trigger includes `or new.debug is not old.debug` in its WHEN clause, which rejects a caller updating just the debug label with `refs_immutable: refs rows are immutable`. That's noise — the value is designed for exactly this kind of update.

Companion carve-out: `objects.debug` has been mutable since the needs_trace / in_trace carve-out landed (via issue #1667). This sprint brings `refs.debug` into line.

## Fix

Remove `or new.debug is not old.debug` from `refs_no_update`'s WHEN clause. Every other column stays guarded — a rebind is still delete + insert.

## Status

**Pre-integration.** Sprint schema at [sprints/refs-debug-mutable/src/schema.sql](https://puck.uno/sprints/refs-debug-mutable/src/schema.sql); tests at [sprints/refs-debug-mutable/tests/test_refs_debug_mutable.lua](https://puck.uno/sprints/refs-debug-mutable/tests/test_refs_debug_mutable.lua). Shipping untouched.

## Integration

One-line WHEN-clause edit to shipping's `refs_no_update` trigger.
