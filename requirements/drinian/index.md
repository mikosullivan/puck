# Drinian

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian",
	"role": "Drinian is Caspian's runtime state store, implemented as a SQLite database — the authoritative schema (src/engine/drinian.sql), per-subsystem specs (garbage-collection, pause-resume), and the walking-skeleton Lua engine + tests. Two-layer split: Mikobase (general-purpose DBMS pieces) + Drinian (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "V1 spec"
}}
~~~

Purpose-built SQLite schema for Drinian — every field of the runtime state hash maps to a table directly shaped around what Drinian actually needs, rather than being layered on top of a generic object store.

![Drinian entity-relationship diagram: eleven tables in five color-coded clusters (drinian marker in gray, object graph in teal, listeners in purple, execution stack in blue, frame-attached tables in orange), each showing its primary key and foreign keys, with curved gray lines drawn for cross-table foreign keys.](./schema.svg)

- [sql](https://www.puck.uno/requirements/drinian/sql) — display of the schema DDL
- [garbage-collection](https://www.puck.uno/requirements/drinian/garbage-collection/) — mark triggers + the trace routine
- [pause-resume](https://www.puck.uno/requirements/drinian/pause-resume/) — pause via top-of-stack frame + DB close, resume via SQL edit + optional payload

Code and tests live outside the doc tree:

- Schema and engine entry point: [src/engine/drinian.sql](../../src/engine/drinian.sql), [src/engine/drinian.lua](../../src/engine/drinian.lua)
- Tests: [tests/main/lua/engine/test_drinian.lua](../../tests/main/lua/engine/test_drinian.lua)

Still in flux (in ideas/):

- [api](https://www.puck.uno/ideas/drinian-with-sqlite/api/) — first-pass method sketch of the Drinian API
- [features](https://www.puck.uno/ideas/drinian-with-sqlite/features) — features the SQLite substrate unlocks (including transferring consciousness / big processes)

## The Lua-owner contract

Using Drinian requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.
