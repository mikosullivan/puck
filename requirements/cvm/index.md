# CVM

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm",
	"role": "CVM is Caspian's runtime state store, implemented as a SQLite database — the authoritative schema (src/engine/cvm.sql), per-subsystem specs (garbage-collection, pause-resume), and the walking-skeleton Lua engine + tests. Two-layer split: Mikobase (general-purpose DBMS pieces) + CVM (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "V1 spec"
}}
~~~

Purpose-built SQLite schema for CVM — every field of the runtime state hash maps to a table directly shaped around what CVM actually needs, rather than being layered on top of a generic object store.

![CVM entity-relationship diagram: ten tables in five color-coded clusters (mvm marker in gray, object graph in teal, listeners in purple, execution stack in green, frame-attached tables in orange), each showing its primary key and foreign keys, with curved lines drawn for cross-table foreign keys.](./schema.svg)

- [sql](https://www.puck.uno/requirements/cvm/sql) — display of the schema DDL
- [ast-storage](https://www.puck.uno/requirements/cvm/ast-storage) — why ast blobs are stored as JSON text, not SQLite JSONB
- [garbage-collection](https://www.puck.uno/requirements/cvm/garbage-collection/) — mark triggers + the trace routine
- [pause-resume](https://www.puck.uno/requirements/cvm/pause-resume/) — pause via top-of-stack frame + DB close, resume via SQL edit + optional payload

Code and tests live outside the doc tree:

- Schema and engine entry point: [src/engine/cvm.sql](../../src/engine/cvm.sql), [src/engine/cvm.lua](../../src/engine/cvm.lua)
- Tests: [tests/main/lua/engine/test_cvm.lua](../../tests/main/lua/engine/test_cvm.lua)

Still in flux (in ideas/):

- [api](https://www.puck.uno/ideas/drinian-with-sqlite/api/) — first-pass method sketch of the CVM API
- [features](https://www.puck.uno/ideas/drinian-with-sqlite/features) — features the SQLite substrate unlocks (including transferring consciousness / big processes)

## The Lua-owner contract

Using CVM requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.
