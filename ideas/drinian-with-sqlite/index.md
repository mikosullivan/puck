# Drinian with SQLite

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite",
	"role": "Drinian implemented as a SQLite database — the authoritative schema (src/drinian.sql), per-subsystem specs (garbage-collection, pause-resume, api), the features the SQLite substrate unlocks, and walking-skeleton Lua+tests that exercise the schema. Two-layer split: Mikobase (general-purpose DBMS pieces) + Drinian (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "stable — pre-promotion review; tree ready to move to requirements/drinian/ + src/engine/"
}}
~~~

Purpose-built SQLite schema for Drinian — every field of the runtime state hash maps to a table directly shaped around what Drinian actually needs, rather than being layered on top of a generic object store.

- [sql](sql)
- [api](api/)
- [garbage-collection](garbage-collection/)
- [features](features)
- [pause-resume](pause-resume/)
- [src](src/)
- [tests](tests/)

## The Lua-owner contract

Using Drinian requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.
