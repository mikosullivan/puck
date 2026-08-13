# CVM

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm",
	"role": "CVM is Caspian's runtime state store, implemented as a SQLite database — the authoritative schema (src/engine/cvm/schema.sql), per-subsystem specs (garbage-collection, pause-resume), and the CVM's data-access layer at src/engine/cvm/. Two-layer split: Mikobase (general-purpose DBMS pieces) + CVM (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "V1 spec"
}}
~~~

Purpose-built SQLite schema for CVM — every field of the runtime state hash maps to a table directly shaped around what CVM actually needs, rather than being layered on top of a generic object store.

Frames are not a separate table. A frame is an `objects` row with `primitive = 'f'` — a fourth primitive kind alongside `'o'` (object / scalar), `'h'` (HashPrimitive), and `'a'` (ArrayPrimitive). The `ast` column is biconditional with `primitive = 'f'`: every frame row carries the code it's executing; no non-frame row carries an ast. That fold is what lets the standard object-graph GC keep captured scope alive for closures that outlive their defining frame.

![CVM entity-relationship diagram: six tables in color-coded clusters — cvm marker (gray), object graph (objects and refs, teal), listeners (instance_listeners and class_listeners, purple), execution (processes, green). Frames are not a separate table — a frame is an `objects` row with primitive='f'.](./schema.svg)

**Diagram staleness note.** The rendered SVG above still shows an `idx` column on `objects` and doesn't yet show `frame_parent`. Post frame-0 integration, the actual schema drops `idx` (stack ordering is derived from the `frame_parent` chain) and adds `frame_parent` (sub-frames chain to their pusher via this column; only frame 0 binds to `processes` directly). Regenerating the SVG is a follow-on to this integration.

- [sql](https://www.puck.uno/requirements/cvm/sql) — display of the schema DDL
- [ast-storage](https://www.puck.uno/requirements/cvm/ast-storage) — why ast blobs are stored as JSON text, not SQLite JSONB
- [garbage-collection](https://www.puck.uno/requirements/cvm/garbage-collection/) — mark triggers + the trace routine
- [pause-resume](https://www.puck.uno/requirements/cvm/pause-resume/) — pause via top-of-stack frame + DB close, resume via SQL edit + optional payload

Code and tests live outside the doc tree:

- Schema, connection-open, and CVM's data-access layer: [src/engine/cvm/](../../src/engine/cvm/) — `schema.sql`, `open.lua`, `engine.lua`, `object.lua`, `frame.lua`
- Tests: [tests/main/lua/engine/test_cvm.lua](../../tests/main/lua/engine/test_cvm.lua)

Still in flux (in ideas/):

- [api](https://www.puck.uno/ideas/drinian-with-sqlite/api/) — first-pass method sketch of the CVM API
- [features](https://www.puck.uno/ideas/drinian-with-sqlite/features) — features the SQLite substrate unlocks (including transferring consciousness / big processes)

## The Lua-owner contract

Using CVM requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.

## Deferred: closure capture reconciliation

Closures need their defining frame's scope kept alive past the frame's return. The CVM schema settles the storage side (a frame is an `objects` row; its bucket holds locals; standard object-graph GC anchors what any live reference reaches), but the specific capture mechanism — how a closure holds a reference to its captured frame's bucket, whether that reference is a plain `refs` entry or a dedicated column, whether the resulting model matches the scope-agg proposal in [lua/scope](https://puck.uno/requirements/lua/scope#reconciliation-with-the-cvms-frame-model--open) — is left for a dedicated closure-design slice.
