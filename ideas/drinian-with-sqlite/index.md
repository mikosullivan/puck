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

## Handle storage

Objects holding native handles (file descriptors, sockets, coroutines, C userdata) are handled via `objects.handle_key` — a nullable text column: for objects that carry a native handle, the column holds a key that resolves through an engine-side Lua registry to the actual handle. SQLite doesn't inspect the handle; it just keeps the row alive so the handle stays reachable.

That's the escape hatch — everything else is normal SQL, and the handle mechanism only pays cost for the specific objects that need it.

## Open questions

- **Concurrency model.** Caspian is single-threaded, but if we want to snapshot mid-execution or read from an inspector, we need at least a read consistency story. SQLite's WAL mode handles this fine but adds cost.
- **Where the app-level cache lives.** Every "hot state" implementation would look different depending on whether the engine caches at the row level, the object level, the frame level, or coarser.
