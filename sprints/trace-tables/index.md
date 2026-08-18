~~~vibecode
{"doc": "sprint-index", "sprint": "trace-tables",
	"role": "Reworks the CVM's GC scratch storage into the tables and helpers a trace routine will need — pulls needs_trace and in_trace out of the objects table into their own tables, adds a per-run traces log, adds a per-trace object-membership table (in_trace), scopes marks by process. Infrastructure only: the trace routine itself lands in a later sprint. Persistent needs_trace vs. temp traces / in_trace split keeps GC bookkeeping out of the WAL while still surviving engine restart for pending marks.",
	"deliverables": ["needs_trace_table", "traces_temp_table", "in_trace_temp_table",
		"current_process_pk_udf", "fk_equivalent_triggers"],
	"status": "active — integration into shipping pending"}
~~~

# trace-tables

Sets up the tables and helpers a trace routine will use. **Infrastructure only** — the routine itself is a separate sprint. The shipping schema keeps `needs_trace` and `in_trace` as columns on the `objects` table; this sprint splits them into their own tables and adds a per-run trace log so the engine has somewhere to reason about "which suspect am I tracing, what did that trace visit" once the routine lands.

## What's in the sprint

The sprint lives under [sprints/trace-tables/](.) with:

- [src/schema.sql](src/schema.sql) — the reworked schema, forked from shipping and evolved in place.
- [src/engine/cvm/udfs/current\_process\_pk.lua](src/engine/cvm/udfs/current_process_pk.lua) — a SQLite UDF that exposes the engine's current process cap to schema-side rules.
- [tests/test\_current\_process\_pk.lua](tests/test_current_process_pk.lua) — UDF-behavior tests.
- [tests/test\_needs\_trace\_lifecycle.lua](tests/test_needs_trace_lifecycle.lua) — `needs_trace` cascade / restrict / composite-PK tests.
- [tests/test\_trace\_run.lua](tests/test_trace_run.lua) — `traces_run_on_insert` behavior tests.
- [schema.svg](schema.svg) — ER diagram reflecting the current sprint state.

## Storage layout

Three tables replace the two `objects` columns:

### needs_trace — persistent, in the main schema

The drain worklist. A row means "this object has been marked for retrace by a specific process."

- **Persistent** — a mark must survive engine restart. An engine that crashed with pending marks needs to re-trace on the next run.
- **Composite PK** `(process_pk, object_pk)` — one row per (process, object) pair. Each cap runs an independent trace worklist; a single process cannot double-mark, but different processes each get their own row.
- **`process_pk` FK** to `objects(object_pk)`, NO ACTION on delete (RESTRICT). Defaults to `current_process_pk()` so callers omitting the column get the running cap's id automatically.
- **`object_pk` FK** to `objects(object_pk)`, CASCADE on delete. If the marked object goes, its mark rows across all processes go with it.
- **Cap-only check** — the companion trigger `needs_trace_process_pk_must_be_cap` rejects a process_pk that doesn't reference a `process_cap = 1` row.

### traces — temp, per-connection

Log of trace runs. One row per trace.

- **Temp** — trace state is scratch; the engine can always re-run traces from the worklist on restart. Keeping it out of the persistent store avoids WAL writes for churny GC bookkeeping.
- **No process_pk** — because the table is temp, every row belongs to the connection's current process by construction. `current_process_pk()` gives the engine's live view whenever it needs to reason across the boundary.
- **`trace_pk`** — autoincrement integer PK, monotonic (not rowid reuse).
- **`object_pk`** — the seed object for this trace. NOT NULL.
- **`done`** — 0/1 flag, NOT NULL, DEFAULT 0. Set to 1 by the trigger when the trace completes without hitting uspace.

### in_trace — temp, per-connection

Per-trace object membership. One row per `(trace_pk, object_pk)`.

- **Composite PK** on `(trace_pk, object_pk)` gives uniqueness for free.
- **Both FKs cascade on delete** — if the trace goes away, its membership rows go with it; if the object goes away, every trace's record of visiting it goes with it.

## The FK-equivalent triggers

SQLite disallows FKs across schemas, so the temp tables can't reference `main.objects` with real FKs. Cascade and restrict semantics get reconstructed as `create temp trigger` blocks:

- `objects_delete_cascades_scratch` — AFTER DELETE on `main.objects`, wipes `traces` and `in_trace` rows referencing the deleted object.
- `traces_delete_cascades_in_trace` — AFTER DELETE on `traces`, drops matching `in_trace` rows.

`needs_trace` is persistent and uses real FKs, so no equivalent triggers needed there.

## `current_process_pk` — the engine ↔ schema bridge

A nullary SQLite UDF that returns the engine's current process cap's pk. Schema-level rules that need per-process scoping (the DEFAULT expression on `needs_trace.process_pk`, and the terminal-advance guard for the current process) call `current_process_pk()` in SQL and get whatever the engine's Lua-side state currently says.

Registered per connection with a getter closure — no cache, no polling. `cvm:mark_frame_gc` and its cousins wire this in during boot.

## Ref-delete cascade to needs_trace

`refs_mark_needs_trace_after_delete` — AFTER DELETE on `refs`. Inserts `(process_pk = current_process_pk(), object_pk = old.child)` with `ON CONFLICT DO NOTHING`. Same-process re-marks silently coalesce; a different process dropping a ref to the same child writes a fresh row.

## Test coverage

Twenty sprint-scoped tests covering the infrastructure this sprint delivers, all green:

- **6 UDF tests** — getter passthrough, null handling, closure-state reflection, DEFAULT-driven insert, ref-delete auto-attribution.
- **14 needs_trace lifecycle tests** — object-delete cascade, process-delete RESTRICT, cap-terminal guard, composite-PK conflict, upsert coalescing, multi-process independence, cascade-on-delete for all processes' marks, cross-connection persistence.

An additional six `test_trace_run.lua` tests exist for an experimental trigger that isn't part of what the sprint ships — that trigger and its tests move out during the trace-routine sprint.

Run: `lua5.4 sprints/trace-tables/tests/test_*.lua` from the repo root.

## Status

**Active.** Sprint work is complete. Integration into shipping (moving the schema changes into `production/src/engine/cvm/schema.sql`, wiring the UDF into `cvm.open`, updating shipping tests) is pending — waiting for the shipping GC-cycle rework to settle first (that landed in `9dbde98`).
