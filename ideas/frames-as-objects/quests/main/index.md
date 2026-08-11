# main

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_quests_main",
	"role": "landing page for the main quest — the primary folding of frames into objects. Sits alongside `src/`, `examples/`, `tests/`, and `documentation/` under quests/main/. Prose that describes the whole folding rather than any single moving piece lives here.",
	"status": "living"
}}
~~~

The primary folding: frames become ordinary `objects` rows. The parent [frames-as-objects](https://www.puck.uno/ideas/frames-as-objects/) page has the closure-lifetime motivation and the schema-level table changes; the working artifacts live in the surrounding `main/` dir — schema at [src/cvm.sql](https://www.puck.uno/ideas/frames-as-objects/quests/main/src/cvm.sql), Lua source at `src/`, walkthroughs at [examples/](https://www.puck.uno/ideas/frames-as-objects/quests/main/examples/), tests at `tests/`.

## Consequences (nice, but not the point)

Once frames-as-objects is on the table for the closure reason, some downstream wins fall out:

- **Reflection is free.** `%process.frames` is an ordinary array of ordinary objects. Walking the call stack, filtering it, mapping over it — all use the language's existing hash and array primitives.
- **Uniform GC.** No special uspace anchors for frames; frames participate in mark-sweep like anything else.
- **"Caspian all the way down."** The runtime call stack is objects, not a parallel structure hiding in special tables.
- **Simpler schema surface.** Fewer specialized triggers, fewer cross-table cascade paths.
