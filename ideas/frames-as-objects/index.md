# Frames as objects

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects",
	"role": "brainstorm exploring folding the four frame-attached tables (frames, frame_locals, frame_delegations, frame_ambers) into the objects table. A frame becomes just another objects row so the object-graph GC keeps captured scope alive for closures that outlive their defining frame. Motivation, the table-level changes, and the downstream consequences all live on this page. Working artifacts: schema + Lua source at `src/`, walkthroughs at `examples/`, tests at `tests/`, ER diagram at `documentation/`. Not spec — exploration.",
	"status": "brainstorm"
}}
~~~

Exploring folding frames into the object table. Working artifacts around this page — schema at [src/cvm.sql](https://www.puck.uno/ideas/frames-as-objects/src/cvm.sql), Lua source at `src/`, walkthroughs at [examples/](https://www.puck.uno/ideas/frames-as-objects/examples/), tests at `tests/`.

## Overview

The primary reason to do this is **closure lifetime**: a closure that outlives its defining frame must keep the captured scope alive, and the current schema has no mechanism to do that. Under the frames-as-objects model, a closure holds an ordinary object-graph reference to its enclosing frame; that reference makes the frame uspace-anchored; the frame lives as long as any closure (or anything else) points at it. GC collects it only when the last reference goes, and its captured locals — living in its bucket — go with it. That's exactly what real closure semantics require.

**What breaks in the current CVM.** Frames are a dedicated table. `frame_locals` cascades on frame delete. `lexical_parent` is `ON DELETE SET NULL` — a spec-level admission the link can go stale (the schema comment: "engine-side concern, not a corruption"). Fine for a walking skeleton with no escaping closures. The moment a closure returns from its defining function and gets called later, its captured `$x` is gone.

**What folding into `objects` fixes.** Frames become ordinary objects. Locals become bucket entries. `lexical_parent` becomes a plain object reference. The whole thing participates in the standard object-graph mark-sweep — no special-case cascade rule, no "SET NULL" resignation. Reference → alive. No reference → collected.

## What changes

- `frames` — gone as a table. Each frame becomes an `objects` row (ast in `objects.ast`, other frame fields — process, idx, lexical_parent, next_stmt_idx — either become columns on `objects` or entries in the frame-object's bucket).
- `frame_locals` — gone. Locals become bucket entries on the frame-object.
- `frame_delegations`, `frame_ambers` — gone. Same treatment.
- **`processes` stays** as call-stack roots (one row per stack).
- `objects`, `refs`, `instance_listeners`, `class_listeners` unchanged in role.

Ten tables → six. [cvm.sql](https://www.puck.uno/ideas/frames-as-objects/src/cvm.sql) has the working schema sketch.

## Consequences (nice, but not the point)

Once frames-as-objects is on the table for the closure reason, some downstream wins fall out:

- **Reflection is free.** `%process.frames` is an ordinary array of ordinary objects. Walking the call stack, filtering it, mapping over it — all use the language's existing hash and array primitives.
- **Uniform GC.** No special uspace anchors for frames; frames participate in mark-sweep like anything else.
- **"Caspian all the way down."** The runtime call stack is objects, not a parallel structure hiding in special tables.
- **Simpler schema surface.** Fewer specialized triggers, fewer cross-table cascade paths.

## Promotion coordination

When this idea promotes to `requirements/`, land the changes in this order:

1. **Update `requirements/` docs first** — every doc that mentions the affected surface.
2. **Update the reference implementation** at `src/engine/cvm.sql` and `src/engine/cvm.lua`.
3. **Update the engine tests** at `tests/main/lua/engine/`.
4. **Run all tests** (engine + trivet + the ideas/-side `view-indexes.lua`) and confirm each passes.

Docs before code; code before tests. Doing them out of order — code before docs, tests before code — leaves the codebase transiently inconsistent and produces spurious test failures.
