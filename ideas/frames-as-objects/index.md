# Frames as objects

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects",
	"role": "umbrella page for a brainstorm exploring folding the four frame-attached tables (frames, frame_locals, frame_delegations, frame_ambers) into the objects table. This page indexes the parallel quests inside the brainstorm; substantive content — motivation, table changes, walkthroughs, schema sketch, Lua source — lives in the individual quest dirs under `quests/`. Not spec — exploration.",
	"status": "brainstorm"
}}
~~~

Umbrella page for a brainstorm exploring folding frames into the object table. Substantive content — motivation, table changes, walkthroughs, schema sketch, Lua source — lives inside the individual quests below.

> **Housecleaning coming.** This brainstorm has grown a lot of pages, sidequests, walkthroughs, and Lua source over its exploration life. A pass to consolidate, tidy stale prose, and align section structure is queued before this idea gets promoted to `requirements/`.

## Quests

Every parallel workstream inside this brainstorm. `main` is the primary folding; the sidequests are design changes riding along that will promote to `requirements/` at the same time. See [quests/](https://www.puck.uno/ideas/frames-as-objects/quests/) for the promotion coordination rule that applies to each:

- [main](https://www.puck.uno/ideas/frames-as-objects/quests/main/) — the primary folding: motivation, table-level changes, and the working artifacts at `main/src/`, `main/examples/`, `main/tests/`
- [refs — renamed from relationships](https://www.puck.uno/ideas/frames-as-objects/quests/refs-rename/) — schema rename affecting the table, column, triggers, indexes, and error ids
- [debug column on objects and refs](https://www.puck.uno/ideas/frames-as-objects/quests/debug-columns/) — permanent human-readable row-label field on both tables
