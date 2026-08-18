-- ============================================================
-- CVM per-connection preflight.
--
-- Runs immediately after opening a connection to an existing CVM
-- database, before any application query. Distinct from
-- `schema.sql`, which runs once at DB creation.
--
-- Two kinds of things live here:
--
--   1. Session-level pragmas. `foreign_keys` and
--      `recursive_triggers` default to OFF in SQLite for
--      backwards-compatibility reasons; the CVM's design assumes
--      both are ON, so every connection sets them explicitly.
--
--   2. Temp tables and their triggers. These are per-connection
--      by construction (they die when the connection closes),
--      so they can't live in `schema.sql`. The engine's trace
--      state (`traces`, `in_trace`) is scratch — no WAL churn —
--      but every connection needs a fresh instance.
--
-- No compile-time UDF dependency here — SQLite defers UDF
-- resolution until fire time, and the temp triggers in this file
-- don't reference `current_process_pk()` in their WHEN clauses.
-- (The needs_trace-based guards that DO reference it live in
-- schema.sql; the UDF must be registered before either file
-- fires a guarded UPDATE.)
-- ============================================================

pragma foreign_keys = on;
pragma recursive_triggers = on;


-- ------------------------------------------------------------
-- Temp scratch tables — `traces` and `in_trace`
-- ------------------------------------------------------------
-- SQLite disallows cross-schema FKs, so `temp.traces` and
-- `temp.in_trace` cannot reference `main.objects` via FK. Cascade
-- semantics that FKs would have enforced are reconstructed as
-- `create temp trigger` blocks below.
--
-- Every trigger that references a temp table (either as its host
-- or in its body) must itself be `create temp trigger` — permanent
-- triggers in `main` cannot reference `temp.*`.
-- ------------------------------------------------------------

-- Trace log. One row per trace run.
--
-- No `process_pk` column: because the table is temp, every row
-- belongs to the connection's current process by construction.
-- `current_process_pk()` gives the engine's live view of "which
-- process's trace state is this" whenever it needs to reason
-- across the boundary.
--
-- `trace_pk` is a monotonic integer PK (AUTOINCREMENT, not just
-- rowid aliasing — the current max isn't reused after delete).
--
-- `object_pk` is the object the trace entry is about:
--   * NOT NULL.
--   * CASCADE on object delete enforced by
--     `objects_delete_cascades_scratch`.
--
-- `done` is a boolean flag (SQLite integer 0 / 1, CHECK-enforced)
-- indicating whether the trace has completed. NOT NULL, DEFAULT 0. [ghi]
create temp table traces (
	trace_pk integer primary key autoincrement,
	object_pk text not null,
	done integer not null default 0
		check (done in (0, 1))
);

-- Per-trace object membership. One row per (trace, object) pair
-- indicates that `object` was visited during `trace`.
--
-- Composite PK on `(trace_pk, object_pk)` gives the uniqueness
-- constraint for free (SQLite indexes PKs; no separate UNIQUE
-- declaration needed).
--
-- Both cascade semantics reproduced by triggers:
--   * On traces DELETE, `traces_delete_cascades_in_trace` drops
--     matching rows.
--   * On objects DELETE, `objects_delete_cascades_scratch` drops
--     matching rows. [ghi]
create temp table in_trace (
	trace_pk integer not null,
	object_pk text not null,
	primary key (trace_pk, object_pk)
);


-- ============================================================
-- FK-equivalent triggers: cascade semantics that cross-schema FKs
-- cannot express (only the temp tables need these — `needs_trace`
-- is persistent and uses real FKs in schema.sql).
-- ============================================================

-- CASCADE on main.objects DELETE. Wipes rows in the temp scratch
-- tables that referenced the deleted object as `object_pk`. The
-- persistent `needs_trace` table's own FK handles its side; this
-- trigger only covers `traces` and `in_trace`. [ghi]
create temp trigger objects_delete_cascades_scratch
after delete on main.objects
begin
	delete from traces   where object_pk = old.object_pk;
	delete from in_trace where object_pk = old.object_pk;
end;

-- CASCADE: on traces DELETE, drop matching in_trace rows. [ghi]
create temp trigger traces_delete_cascades_in_trace
after delete on traces
begin
	delete from in_trace where trace_pk = old.trace_pk;
end;
