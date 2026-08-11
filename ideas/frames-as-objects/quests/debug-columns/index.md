# debug column on objects and refs

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_sidequests_debug_column",
	"role": "sidequest carried alongside the frames-as-objects brainstorm: both `objects` and `refs` gain a permanent `debug` column — nullable text, populated by the engine or by hand so state snapshots self-describe what each row is meant to be. Purely informational. Rendered as 'comment' in walkthrough tables for readability, but the storage-level name is `debug`. Documents the addition and the promotion coordination rule.",
	"status": "landed in ideas/, needs promotion"
}}
~~~

Both `objects` and `refs` carry a `debug` column — nullable text, populated by the engine or by hand so a state snapshot self-describes what each row is meant to be. Purely informational — no query path reads it. Permanent feature of the schema, not scaffolding. Rendered as "comment" in walkthrough tables for readability, but the storage-level name is `debug`.

## On objects

Labels rows: "user seed", "frame 0", "frame 0's bucket", "scalar 42". Any snapshot dump shows each row with a human-readable identifier without the reader having to trace back through the surrounding relationships to figure out what a bare UUID is.

## On refs

Labels edges: which callable owns the edge, which language feature the edge implements, whatever the writer wants a reader to know at a glance.

## Promotion coordination

When frames-as-objects promotes to `requirements/`, the addition lands in this order:

1. Update `requirements/` docs — spec the `debug` column on both tables.
2. Update `src/engine/mvm.sql` — add the column.
3. Update the engine tests where they inspect the schema.
4. Run all tests and verify each passes.

Docs before code; code before tests. Adding the column to `requirements/` before touching `src/engine/mvm.sql` avoids the "column doesn't exist yet" flake.
