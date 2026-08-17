~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Design principle: the engine's GC phase is fixed-point iteration — keep sweeping until a pass catches nothing new, then reset gc to null. Invariant 4 (gc reset requires no children) is the only gate; the engine just loops until the state naturally settles."}
~~~

# GC as fixed-point iteration

> **GC sweeps are cheap. Err on the side of using them.**

While a frame is at `gc = 1`, the engine's job is dead simple: run a sweep. If the sweep produced no new work, reset `gc = null`. If it did, let that new work run to completion (via the walker's normal loop) and sweep again. Repeat until a sweep is a no-op.

That's fixed-point iteration — which is what GC fundamentally is, in any system where cleanup can trigger more cleanup.

## Why the schema doesn't need to know

The four gc-cycle invariants leave the engine free to run as many sweeps as it wants. Invariant 4 (`gc reset requires no children`) is the only gate, and it isn't asking "is GC done?" — it's asking "are the children cleared?" The engine keeps sweeping until they are.

No column tracks "have we already run GC on this frame this cycle." Each sweep is independent. The absence of new work at the end of a sweep is the terminal condition.

## Concrete: cascading needs_trace

A cascade of deletes can create new `needs_trace` marks that need more passes:

~~~
UPDATE R SET stmt_idx += 1, gc = 1     -- walker's advance
	→ cascade deletes marker child      -- invariant 2 fires
	→ R now: gc=1, no children

Engine loop on R:
	sweep pass 1
		→ query for needs_trace = 1
		→ finds a hash (locals) that was orphaned when the marker's ref cascade ran
		→ locals has no other incoming refs → delete
		→ locals delete cascades to ref → scalar loses its incoming ref
		→ scalar now needs_trace = 1
	sweep pass 2
		→ query for needs_trace = 1
		→ finds the scalar
		→ scalar has no incoming refs → delete
	sweep pass 3
		→ query for needs_trace = 1
		→ empty
	UPDATE R SET gc = null              -- passes invariant 4 (no children)

R ready for next statement.
~~~

Each pass is one query and possibly one round of deletes. Cascades from a delete propagate `needs_trace` further; the next pass picks them up. Fixed point emerges from repetition.

## What this buys

- **No "am I done?" bookkeeping.** "Children exist" (invariant 4) plus "any needs_trace items" (query the engine already runs) IS the done check.
- **Uniform control flow.** Every walker tick is "pick the deepest live frame, do the state-appropriate thing." Nothing special about gc-phase ticks.
- **Cheap to over-sweep.** The terminating pass finds nothing and lets the engine reset. That wasted pass is a small constant, well under the threshold that would push a design.

## What we're paying

One wasted sweep pass per cycle — the terminating pass that finds nothing and lets the engine reset. Cheap enough that it doesn't factor into design decisions. The alternative (some sort of "have we run GC yet?" flag with a lifecycle) is more machinery for less clarity.
