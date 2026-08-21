# CVM

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm",
	"role": "CVM is Caspian's runtime state store, implemented as a SQLite database — the authoritative schema (src/engine/cvm/sqlite/schema.sql), per-subsystem specs (frame-lifecycle, ownership, scopes, garbage-collection, pause-resume), and the CVM's data-access layer at src/engine/cvm/. Two-layer split: Mikobase (general-purpose DBMS pieces) + CVM (Caspian-specific runtime layer added via ALTER TABLE).",
	"status": "V1 spec"
}}
~~~

Purpose-built SQLite schema for CVM — every field of the runtime state hash maps to a table directly shaped around what CVM actually needs, rather than being layered on top of a generic object store.

Every runtime entity is a row in `objects`, discriminated by two columns rather than one:

- `base` — the row's underlying storage shape. NOT NULL. Values: `'o'` (regular object — the base every user object, frame, and role uses), `'h'` (HashPrimitive container), `'a'` (ArrayPrimitive container).
- `control` — an optional CVM control-plane role, layered on top of `base = 'o'`. Values: `'f'` (frame), `'r'` (role). NULL on plain objects. A cross-column CHECK enforces `control is null or base = 'o'` — a container-that-is-also-a-frame is a schema violation.

Frames are not a separate table. A frame is an `objects` row with `control = 'f'`. Frame-only columns wear a `frame_` prefix — `frame_ast`, `frame_stmt_idx`, `frame_process_cap`, `frame_parent`, `frame_gc` — so reading a column name tells you which control kind it applies to. `frame_ast` is biconditional with `control = 'f'`: every frame row carries the code it's executing; no non-frame row carries a `frame_ast`. That fold is what lets the standard object-graph GC keep captured scope alive for closures that outlive their defining frame.

Roles are also not a separate table. A role is an `objects` row with `control = 'r'`. Roles exist in a strict hierarchical tree via `role_parent`, don't hold state (can't be `refs` parents), and serve as identity anchors. The three seeded core roles — engine, cache, user — are `'r'` rows marked by `role_core`. See [roles](https://puck.uno/requirements/cvm/roles) for the full storage contract.

A process is also not a separate table. A process is a **cap frame**: an `objects` row with `control = 'f'`, `frame_process_cap = 1`, empty `frame_ast`, and no parent — the top of a call stack. Its `object_pk` IS the process identity. Frame 0 (the top of user code) sits under the cap as a nested frame; sub-frames chain from frame 0 via `frame_parent`. The cap participates in the same lifecycle machinery as any frame; when a program is done, the cap sits at terminal state (`frame_stmt_idx = 1, frame_gc = null, no children`) as the completion signal.

Scalar values ride on four typed columns rather than a polymorphic blob: `scalar_string` (TEXT), `scalar_number` (REAL — the affinity coerces integer inputs to float, enforcing the "all numbers are floats" invariant at the storage layer), `scalar_bool` (0/1 integer), `scalar_null` (marker `1` for the null value). A cross-column trigger enforces exclusivity; the `scalars` view coalesces the four into `(object_pk, scalar_type, value)` for consumers that want the polymorphic read shape.

`object_pk` is a lowercase-hex UUID (8-4-4-4-12 shape). The column DEFAULT generates a fresh v4 UUID; the column CHECK accepts any UUID of that shape (v1, v3, v7, etc.) so callers passing IDs from elsewhere aren't rejected. Lowercase is enforced so the same conceptual UUID can't sit under two distinct PKs (SQLite's default TEXT collation is binary).

![CVM schema: five tables in three color-coded clusters — `cvm` marker (gray), `objects` and `refs` object graph (teal), `instance_listeners` and `class_listeners` (purple). Frames, roles, and processes are not separate tables — they are `objects` rows discriminated by the `(base, control)` pair (`base` = `'o'`/`'h'`/`'a'` for storage shape; `control` = `'f'` frame, `'r'` role, or null on plain objects). Self-referential FKs (`role_parent`, `owner_role`, `frame_parent`) are drawn as dashed loops on the right edge of the `objects` box.](./schema.svg)

- [sql](https://www.puck.uno/requirements/cvm/sql) — display of the schema DDL
- [ast-storage](https://www.puck.uno/requirements/cvm/ast-storage) — why ast blobs are stored as JSON text, not SQLite JSONB
- [frame-lifecycle](https://puck.uno/requirements/cvm/frame-lifecycle) — cap-as-frame, the nine gc-cycle rules, auto-delete at terminal; step-by-step through `$x = 1`
- [ownership](https://www.puck.uno/requirements/cvm/ownership) — buckets and stacks as refs; the one-hash-one-array cap; shared collections
- [roles](https://www.puck.uno/requirements/cvm/roles) — role tree, `control = 'r'`, `role_core` marker, cycle-free-by-construction
- [scopes](https://www.puck.uno/requirements/cvm/scopes) — the bucket → scopes → scopes[0] chain, hash-key required rule, `frame_scoped_vars` view
- [garbage-collection](https://www.puck.uno/requirements/cvm/garbage-collection/) — mark triggers + the trace routine
- [pause-resume](https://www.puck.uno/requirements/cvm/pause-resume/) — pause via top-of-stack frame + DB close, resume via SQL edit + optional payload
- [test-only-triggers](https://puck.uno/production/requirements/cvm/test-only-triggers) — the pattern for installing SQLite triggers from test code to observe in-flight state (mirror into `debug_log`, assert after the run)
- [x-equals-1](https://puck.uno/requirements/cvm/sqlite/x-equals-1) — concrete run of `$x = 1` with `%process.stop` afterward; dumps `objects` and `refs`, walks every row and every ref

Code and tests live outside the doc tree:

- Schema, connection-open, and CVM's data-access layer: [src/engine/cvm/](../../../src/engine/cvm/sqlite/) — `schema.sql`, `open.lua`, `engine.lua`, `object.lua`, `frame.lua`
- Tests: [tests/main/lua/engine/test_cvm.lua](../../../tests/main/lua/engine/test_cvm.lua)

## The Lua-owner contract

Using CVM requires a Lua wrapper — the engine — that owns the SQLite connection, registers whatever UDFs the schema expects, and mediates access. A bare `sqlite3` CLI can read the file for inspection, but writes go through the Lua wrapper.

## Deferred: closure capture reconciliation

Closures need their defining frame's scope kept alive past the frame's return. The CVM schema settles the storage side (a frame is an `objects` row; its bucket holds locals; standard object-graph GC anchors what any live reference reaches), but the specific capture mechanism — how a closure holds a reference to its captured frame's bucket, whether that reference is a plain `refs` entry or a dedicated column, whether the resulting model matches the scope-agg proposal in [lua/scope](https://puck.uno/requirements/lua/scope#reconciliation-with-the-cvms-frame-model--open) — is left for a dedicated closure-design slice.
