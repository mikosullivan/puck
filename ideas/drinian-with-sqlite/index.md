# Drinian with SQLite

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite",
	"role": "brainstorm space for using SQLite directly as Drinian's storage layer — a purpose-built schema shaped around Drinian's fields.",
	"status": "sketching 2026-08-07 — table shapes proposed; not committed"
}}
~~~

Purpose-built SQLite schema for Drinian — every field of the runtime state hash maps to a table directly shaped around what Drinian actually needs, rather than being layered on top of a generic object store.

## The Lua-owner contract

Using Drinian requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.
