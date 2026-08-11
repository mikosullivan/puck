# main

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_quests_main",
	"role": "the main quest — folding frames into the objects table. Motivation (closure lifetime), the table-level changes, and the downstream consequences all live here. Working artifacts sit alongside in `src/` (schema + Lua), `examples/` (walkthroughs), `tests/`, and `documentation/` (ER diagram).",
	"status": "living"
}}
~~~

The primary folding: frames become ordinary `objects` rows. Working artifacts around this page — schema at [src/cvm.sql](https://www.puck.uno/ideas/frames-as-objects/quests/main/src/cvm.sql), Lua source at `src/`, walkthroughs at [examples/](https://www.puck.uno/ideas/frames-as-objects/quests/main/examples/), tests at `tests/`.

## Overview

The primary reason to do this is **closure lifetime**: a closure that outlives its defining frame must keep the captured scope alive, and the current schema has no mechanism to do that. Under the frames-as-objects model, a closure holds an ordinary object-graph reference to its enclosing frame; that reference makes the frame uspace-anchored; the frame lives as long as any closure (or anything else) points at it. GC collects it only when the last reference goes, and its captured locals — living in its bucket — go with it. That's exactly what real closure semantics require.

**What breaks in the current MVM.** Frames are a dedicated table. `frame_locals` cascades on frame delete. `lexical_parent` is `ON DELETE SET NULL` — a spec-level admission the link can go stale (the schema comment: "engine-side concern, not a corruption"). Fine for a walking skeleton with no escaping closures. The moment a closure returns from its defining function and gets called later, its captured `$x` is gone.

**What folding into `objects` fixes.** Frames become ordinary objects. Locals become bucket entries. `lexical_parent` becomes a plain object reference. The whole thing participates in the standard object-graph mark-sweep — no special-case cascade rule, no "SET NULL" resignation. Reference → alive. No reference → collected.

## What changes

- `frames` — gone as a table. Each frame becomes an `objects` row (ast in `objects.ast`, other frame fields — process, idx, lexical_parent, next_stmt_idx — either become columns on `objects` or entries in the frame-object's bucket).
- `frame_locals` — gone. Locals become bucket entries on the frame-object.
- `frame_delegations`, `frame_ambers` — gone. Same treatment.
- **`processes` stays** as call-stack roots (one row per stack).
- `objects`, `refs`, `instance_listeners`, `class_listeners` unchanged in role.

Ten tables → six. [cvm.sql](https://www.puck.uno/ideas/frames-as-objects/quests/main/src/cvm.sql) has the working schema sketch.

## Consequences (nice, but not the point)

Once frames-as-objects is on the table for the closure reason, some downstream wins fall out:

- **Reflection is free.** `%process.frames` is an ordinary array of ordinary objects. Walking the call stack, filtering it, mapping over it — all use the language's existing hash and array primitives.
- **Uniform GC.** No special uspace anchors for frames; frames participate in mark-sweep like anything else.
- **"Caspian all the way down."** The runtime call stack is objects, not a parallel structure hiding in special tables.
- **Simpler schema surface.** Fewer specialized triggers, fewer cross-table cascade paths.
