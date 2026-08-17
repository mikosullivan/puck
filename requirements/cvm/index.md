# CVM

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm",
	"role": "CVM is Caspian's runtime state store, implemented as a SQLite database — the authoritative schema (src/engine/cvm/schema.sql), per-subsystem specs (frame-lifecycle, ownership, scopes, garbage-collection, pause-resume), and the CVM's data-access layer at src/engine/cvm/. Two-layer split: Mikobase (general-purpose DBMS pieces) + CVM (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "V1 spec"
}}
~~~

Purpose-built SQLite schema for CVM — every field of the runtime state hash maps to a table directly shaped around what CVM actually needs, rather than being layered on top of a generic object store.

Frames are not a separate table. A frame is an `objects` row with `primitive = 'f'` — a fourth primitive kind alongside `'o'` (object / scalar), `'h'` (HashPrimitive), and `'a'` (ArrayPrimitive). The `ast` column is biconditional with `primitive = 'f'`: every frame row carries the code it's executing; no non-frame row carries an ast. That fold is what lets the standard object-graph GC keep captured scope alive for closures that outlive their defining frame.

A process is also not a separate table. A process is a **cap frame**: an `objects` row with `primitive = 'f'`, `process = 1`, `ast = '[]'`, and no parent — the top of a call stack. Its `object_pk` IS the process identity. Frame 0 (the top of user code) sits under the cap as a nested frame; sub-frames chain from frame 0 via `parent_frame`. The cap participates in the same lifecycle machinery as any frame, which is what lets the walker cascade-clean frame 0 uniformly.

![CVM entity-relationship diagram: color-coded clusters — cvm marker (gray), object graph (objects and refs, teal), listeners (instance_listeners and class_listeners, purple). Frames and processes are not separate tables — a frame is an `objects` row with primitive='f'; a process is an objects row with primitive='f' and process=1.](./schema.svg)

**Diagram staleness note.** The rendered SVG above is stale — a rewrite is a follow-on. Under the current schema: no `processes` table (a process is a cap frame in `objects`); no `bucket_pk` / `stack_pk` / `bucket_for` / `stack_for` columns (ownership is a normal refs row from owner to collection); `parent_frame` chains sub-frames to their parent; `process = 1` marks the cap frame.

- [sql](https://www.puck.uno/requirements/cvm/sql) — display of the schema DDL
- [ast-storage](https://www.puck.uno/requirements/cvm/ast-storage) — why ast blobs are stored as JSON text, not SQLite JSONB
- [frame-lifecycle](https://www.puck.uno/requirements/cvm/frame-lifecycle) — cap-as-frame, advance-with-gc, terminal state; step-by-step through `$x = 1`
- [ownership](https://www.puck.uno/requirements/cvm/ownership) — buckets and stacks as refs; the one-hash-one-array cap; shared collections
- [scopes](https://www.puck.uno/requirements/cvm/scopes) — the bucket → scopes → scopes[0] chain, hash-key identifier rule, `frame_scoped_vars` view
- [garbage-collection](https://www.puck.uno/requirements/cvm/garbage-collection/) — mark triggers + the trace routine
- [pause-resume](https://www.puck.uno/requirements/cvm/pause-resume/) — pause via top-of-stack frame + DB close, resume via SQL edit + optional payload

Code and tests live outside the doc tree:

- Schema, connection-open, and CVM's data-access layer: [src/engine/cvm/](../../src/engine/cvm/) — `schema.sql`, `open.lua`, `engine.lua`, `object.lua`, `frame.lua`
- Tests: [tests/main/lua/engine/test_cvm.lua](../../tests/main/lua/engine/test_cvm.lua)

## The Lua-owner contract

Using CVM requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.

## Deferred: closure capture reconciliation

Closures need their defining frame's scope kept alive past the frame's return. The CVM schema settles the storage side (a frame is an `objects` row; its bucket holds locals; standard object-graph GC anchors what any live reference reaches), but the specific capture mechanism — how a closure holds a reference to its captured frame's bucket, whether that reference is a plain `refs` entry or a dedicated column, whether the resulting model matches the scope-agg proposal in [lua/scope](https://puck.uno/requirements/lua/scope#reconciliation-with-the-cvms-frame-model--open) — is left for a dedicated closure-design slice.
