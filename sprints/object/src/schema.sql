-- Caspian virtual machine
-- This schema defines the SQLite format for a Caspian virtual
-- machine. The intent of this design is that only valid programmatic
-- states can be stored in the database. It should not be possible
-- to build an invalid state.

-- vibecode
/*
{"doc": "cvm-schema-sqlite", "version": "13.0-object-sprint",
	"role": "SQLite DDL for the CVM — Caspian's runtime state store. Every runtime state read or write flows through this schema. Design intent: only valid programmatic states can be stored; the DB itself refuses invalid states at write time via CHECK constraints and triggers, each raising a grep-able error id (e.g. `objects_frame_ast_immutable`, `refs_object_parent_key_must_be_bsh`). Engine bugs that would produce a bad state raise at the exact write site instead of silently corrupting the DB.",
	"tables": {
		"cvm":                "single-row marker; presence signals 'this DB is a CVM'. Append-only.",
		"objects":            "load-bearing table. Every CVM entity — plain objects, hashes, arrays, frames, roles — is a row here, discriminated by the (base, control) pair. See `axes`.",
		"refs":               "parent-to-child object edges. Refs from a non-container parent (base='o') carry the parent's b/s/h properties by key: 'b' → bucket (hash), 's' → stack (array), 'h' → shadow (hash). Each is optional; at most one of each per parent (unique(parent, key)). Container children (base='h'/'a') hold refs by their own semantics — key-per-entry for hashes, idx-per-entry for arrays.",
		"instance_listeners": "per-instance event dispatch registrations. Weak-ref lifetime via ON DELETE CASCADE on either party.",
		"class_listeners":    "per-class event dispatch registrations. Same shape.",
		"needs_trace":        "per-process GC worklist. Persistent — marks must survive engine restart. PK (process_pk, object_pk); repeated marks coalesce via ON CONFLICT DO NOTHING.",
		"debug_log":          "per-process diagnostic log. Free-form note scoped to a process cap; ON DELETE CASCADE from the cap."},
	"axes": {
		"base":    "row's underlying storage shape. NOT NULL. Values: 'o' (regular object — the base every user object, frame, and role uses), 'h' (HashPrimitive container), 'a' (ArrayPrimitive container).",
		"control": "optional CVM control-plane role, layered on top of base='o'. Values: 'f' (frame — carries executable frame_ast + a frame_stmt_idx/frame_gc/frame_parent/frame_process_cap lifecycle), 'r' (role — identity anchor via role_core/role_parent). NULL on plain objects. Cross-column CHECK enforces `control is null or base = 'o'` (a container-that-is-also-a-frame is a schema violation)."},
	"scalar_columns": "Scalar-carrying objects use one of four typed columns rather than a polymorphic blob: scalar_string (TEXT — affinity preserves numeric-looking strings verbatim), scalar_number (REAL — affinity forces integer inputs to float, enforcing 'all numbers are floats' at the storage layer), scalar_bool (0/1 integer), scalar_null (marker '1' for the u-type null value; distinct from 'no scalar assigned' which is all four columns null). Cross-column trigger `objects_scalar_at_most_one_column` enforces exclusivity; the `scalars` view coalesces the four into (object_pk, scalar_type, value).",
	"naming_conventions": {
		"prefix_by_control_kind": "columns that only apply to a specific control kind wear that kind's prefix. Frame-only: frame_ast, frame_stmt_idx, frame_process_cap, frame_parent, frame_gc. Role-only: role_core, role_parent. Scalar-only: scalar_null, scalar_string, scalar_number, scalar_bool. Reading a `frame_*` column name tells you the column is only meaningful when control='f'.",
		"unprefixed": "columns any row can carry are unprefixed: object_pk, base, control, owner_role, engine_class, persistent, debug. owner_role points at a role but sits on every non-role row, so it doesn't wear the role_ prefix."},
	"views": {
		"scalars":           "(object_pk, scalar_type, value) — coalesces the four scalar_* columns; derives scalar_type from which column is populated; filters to scalar-carrying rows only.",
		"roles":             "single-column filter on control='r'. Single source of truth for 'what is a role'.",
		"uspace":            "GC anchor set — roles + persistent=1 rows + process caps. Anything transitively reachable from uspace via refs is alive.",
		"frame_scoped_vars": "(frame_pk, scope_idx, var_name, value_pk) — every variable visible from a frame's scope chain, ordered by scope depth. scope_idx=0 is the frame's own scope; higher indexes are captured scopes.",
		"object_bucket":     "(object_pk, bucket_pk) — every base='o' row with its bucket pk (or null if not yet materialized). Bucket is the ref keyed 'b'.",
		"object_stack":      "(object_pk, stack_pk) — same shape for stacks. Stack is the ref keyed 's'.",
		"object_shadow":     "(object_pk, shadow_pk) — same shape for shadow platters. Shadow is the ref keyed 'h'; targets a hash, same as bucket."},
	"gc_cycle_state_machine": "A frame's (frame_stmt_idx, frame_gc) pair moves through a strict state machine enforced by triggers on `objects`. The walker's per-statement operation is `UPDATE frame SET frame_stmt_idx = frame_stmt_idx + 1` — the trigger stack takes care of frame_gc auto-null, child-delete cascades, and the parent's frame_gc auto-set. Names to grep: frames_advance_requires_gc, frames_advance_sets_gc_null, frames_advance_rejects_non_null_gc, frames_gc_change_requires_no_child, frames_gc_set_rejects_at_terminal, frames_gc_reset_requires_empty_needs_trace, frames_delete_requires_no_child, frames_child_delete_sets_parent_gc, frames_child_delete_propagates_rv, frames_no_child_under_terminal_parent, frames_stmt_idx_starts_at_zero, frames_stmt_idx_advances_by_one, frames_gc_starts_null. Each raises with its trigger name as the error id — grep to see what invariant fired.",
	"gc_marking": "Any orphaned pk lands in needs_trace automatically via `refs_mark_needs_trace_after_delete` (on ref DELETE) and `refs_mark_needs_trace_after_child_update` (on ref child UPDATE — the upsert-ref path). The mark is scoped to the current process via the current_process_pk UDF. The drain (`cvm:drain_needs_trace` in Lua) sweeps the worklist by reaping unreachable rows and unmarking reachable ones.",
	"immutability": "The primary structural columns on objects are immutable after INSERT — enforced by per-column BEFORE-UPDATE triggers with error ids of the form `objects_<column>_immutable`. The only columns that permit updates are `frame_gc`, `frame_stmt_idx`, and `debug`; every other column is set once at INSERT and never changes (scalar columns included — the objects_scalar_*_immutable triggers use `is not` null-safe distinctness, so even null→populated raises). Bucket, stack, and shadow ownership are `refs` rows (keyed 'b', 's', 'h') rather than dedicated columns.",
	"object_properties_shape": "Under the object-sprint b/s/h design, an object's structural properties live as three well-known keyed refs from the objects row. Enforcement triggers: refs_object_parent_key_must_be_bsh (no other keys allowed from an 'o'-parent), refs_key_b_target_must_be_hash, refs_key_s_target_must_be_array, refs_key_h_target_must_be_hash. Uniqueness (parent, key) already caps each slot at one.",
	"companions": {
		"preflight.sql":       "per-connection temp tables (traces, in_trace) + temp triggers that reproduce cascade semantics across the temp/persistent boundary (SQLite disallows cross-schema FKs). Runs on every connection open.",
		"current_process_pk":  "engine-supplied UDF returning the currently-dispatching process cap's pk. Called by needs_trace.process_pk's DEFAULT, by debug_log.object_pk's DEFAULT, and by frames_gc_reset_requires_empty_needs_trace's per-process scoping. Every connection must register this UDF before applying the schema, or the schema apply fails."}}
*/

-- Every connection to a CVM database must run these two pragmas
-- immediately after opening. [ghi]
pragma foreign_keys = on;
pragma recursive_triggers = on;


-- ------------------------------------------------------------
-- cvm marker table — presence signals "this DB is a CVM." [ghi]
-- Append-only.
-- ------------------------------------------------------------
create table cvm (
	key text primary key,
	value text
);

create trigger cvm_no_update
before update on cvm
when new.key is not old.key
	or new.value is not old.value
begin
	select raise(abort, 'cvm_append_only: cvm is append-only; no updates allowed');
end;

create trigger cvm_no_delete
before delete on cvm
begin
	select raise(abort, 'cvm_append_only: cvm is append-only; no deletes allowed');
end;

insert into cvm (key, value) values ('schema', '13.0-object-sprint');


-- ------------------------------------------------------------
-- Objects.
-- ------------------------------------------------------------

create table objects (
	-- UUID v4 shape, lowercase. DEFAULT builds a full v4 (position 15
	-- = '4' for version, position 20 ∈ {8,9,a,b} for variant, all
	-- lowercase via the wrapping `lower()`). CHECK enforces lowercase
	-- 8-4-4-4-12 hex — accepts non-v4 UUIDs (v1, v3, v7, etc.) so
	-- callers passing IDs generated elsewhere aren't rejected, but
	-- requires lowercase so uppercase-vs-lowercase can't produce two
	-- distinct PKs for the same conceptual UUID. Per-segment `substr`
	-- checks rather than one global char-class — earlier the LIKE-plus-
	-- global-glob shape accepted 36 hyphens because `_` in LIKE matches
	-- any character and `-` was in the allowed character class
	-- everywhere. [ghi]
	object_pk text primary key
		default (
			lower(
				substr(hex(randomblob(4)), 1, 8) || '-' ||
				substr(hex(randomblob(2)), 1, 4) || '-' ||
				'4' || substr(hex(randomblob(2)), 1, 3) || '-' ||
				substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 1, 3) || '-' ||
				substr(hex(randomblob(6)), 1, 12)
			)
		)
		check (
			length(object_pk) = 36
			and substr(object_pk, 9,  1) = '-'
			and substr(object_pk, 14, 1) = '-'
			and substr(object_pk, 19, 1) = '-'
			and substr(object_pk, 24, 1) = '-'
			and substr(object_pk, 1,  8)  not glob '*[^0-9a-f]*'
			and substr(object_pk, 10, 4)  not glob '*[^0-9a-f]*'
			and substr(object_pk, 15, 4)  not glob '*[^0-9a-f]*'
			and substr(object_pk, 20, 4)  not glob '*[^0-9a-f]*'
			and substr(object_pk, 25, 12) not glob '*[^0-9a-f]*'
		),

	-- Base type — the row's underlying storage shape. Every row is
	-- one of three bases:
	--
	--   'o' → object (a "regular" object: user-defined, scalar-carriers,
	--         frames, and roles all use this base — the last two add a
	--         `control` value below to name their special CVM role).
	--   'h' → HashPrimitive (a container that holds hash-refs by its
	--         own semantics).
	--   'a' → ArrayPrimitive (a container that holds array-refs by its
	--         own semantics).
	--
	-- Immutable via objects_no_update. [ghi]
	base text not null check (base in ('o', 'h', 'a')),

	-- Control aspect — an OPTIONAL special role in the CVM's control
	-- plane. Null on plain objects (the common case). Values:
	--
	--   'f' → frame. The row carries executable code via the `frame_ast`
	--         column plus a frame_stmt_idx / frame_gc / frame_parent / frame_process_cap
	--         lifecycle.
	--   'r' → role. The row is an identity anchor via role_core /
	--         role_parent.
	--
	-- Frames and roles are still "regular objects" (base = 'o') that
	-- additionally play a control-plane role — the second CHECK below
	-- enforces that control can only be set when base = 'o' (a
	-- hash-that-is-also-a-frame is a schema violation). Immutable via
	-- objects_no_update. [ghi]
	control text
		check (control is null or control in ('f', 'r'))
		check (control is null or base = 'o'),

	-- Persistence pin. Rows with `persistent = 1` are kept alive; rows
	-- with `persistent = null` (the SQL default when the column is
	-- omitted) are ordinary and eligible for GC.
	--
	--   * Core-role rows MUST be pinned. The cross-column check rejects
	--     any core-role INSERT that leaves persistent null (uses `is 1`
	--     not `= 1` — SQL three-valued logic makes `null = 1` yield
	--     NULL, which doesn't fire a CHECK; `null is 1` yields false,
	--     which does).
	--   * Non-core rows default to unpinned. Omit the column to get null;
	--     set `persistent = 1` to opt into pinning.
	--   * The cross-column CHECK keeps core roles pinned on both write
	--     paths — INSERT with `persistent = null` fails, and UPDATE that
	--     clears `persistent` on a core-role row also fails (CHECKs fire
	--     on INSERT and UPDATE). [ghi]
	persistent integer
		check (persistent = 1)
		check (role_core is null or persistent is 1),

	-- Pointer to the role that created this row. Required for non-role
	-- rows (see objects_owner_role_required_on_non_roles). Roles may
	-- also carry it (cache and user are owned by engine). No cascade.
	-- Target-column check (points at an 'r' row) enforced by the
	-- objects_owner_role_must_be_role trigger below. [ghi]
	owner_role text references objects(object_pk),

	-- Mask marker: names a Lua-side engine class whose behavior the row
	-- surfaces as. Nullable — most rows carry null. Only `'o'` rows may
	-- set it (a mask sits on an object; frames, roles, hashes, arrays
	-- can't be masks). The meaning of a specific value (which Lua class
	-- name, how it's looked up, how it surfaces as a Caspian class) is
	-- deferred to a later sprint. [ghi]
	engine_class text
		check (engine_class is null or (base = 'o' and control is null)),

	-- Human-readable label. Informational; no query path reads it. [ghi]
	debug text,
	
	-- Scalar value columns. One column per scalar type; type is
	-- derived from which column is populated rather than carried in
	-- a separate discriminator column. A base='o' row IS or IS
	-- NOT a scalar-carrying object based on whether any of these
	-- four columns is non-null. Non-'o' rows can't carry a scalar
	-- in any form (see the objects_scalar_columns_only_on_objects
	-- and objects_scalar_at_most_one_column CHECKs later on).
	--
	-- `scalar_null` is the load-bearing marker for an explicit null
	-- value (the `u` type at the language level). Without it, an
	-- object holding an explicit null value would look identical to
	-- an object with no scalar assigned yet — both would have all
	-- value columns null. The distinct marker preserves that split.
	-- CHECK pins the payload to `1` so the column has one canonical
	-- non-null value. [ghi]
	scalar_null integer check (scalar_null = 1),

	-- `scalar_string` holds the text of a string scalar. `text`
	-- affinity keeps SQLite from coercing numeric-looking strings
	-- like '42' into REAL storage. [ghi]
	scalar_string text,

	-- `scalar_number` holds the value of a number scalar. `real`
	-- affinity forces integer values to floating-point representation
	-- at insert time — this is what enforces the "all numbers are
	-- floats" language rule at the storage layer. Bind a Lua integer
	-- `1` here and SQLite stores REAL `1.0`. Companion CHECK pins
	-- the affinity so a text-like value can't sneak in via the
	-- NUMERIC-affinity text→numeric fallback. [ghi]
	scalar_number real
		check (scalar_number is null or typeof(scalar_number) = 'real'),

	-- `scalar_bool` holds the value of a boolean scalar as SQLite's
	-- native 0/1 convention. Kept in its own column rather than
	-- riding along in `scalar_number` — the column name should not
	-- lie about its contents. [ghi]
	scalar_bool integer
		check (scalar_bool is null or scalar_bool in (0, 1)),

	-- Core-role marker: 'e' (engine), 'c' (cache), 'u' (user). Nullable
	-- — most rows aren't core roles. Unique per value via the partial
	-- index below. Only role rows ('r') may carry a role_core. [ghi]
	role_core text
		check (role_core in ('e', 'c', 'u'))
		check (role_core is null or control is 'r'),

	-- Role-tree parentage. Non-root roles set this. Immutable via
	-- objects_parent_role_immutable. Only role rows ('r') may carry a
	-- role_parent — enforced by the cross-column check below. The
	-- target-column check (that role_parent points at an 'r' row)
	-- lives in the objects_parent_role_must_be_role trigger. No
	-- ON DELETE clause — defaults to NO ACTION, which with
	-- `foreign_keys = on` acts as RESTRICT: a role can't be deleted if
	-- any other role references it via role_parent. Force cleanup from
	-- the leaves up. [ghi]
	role_parent text
		references objects(object_pk)
		check (role_parent is null or control is 'r'),

	-- CaspM tree as JSON text. Biconditional with control='f' — every
	-- frame has an frame_ast, no non-frame does. A cap frame (frame_process_cap=1) has
	-- frame_ast='[]' — the cap doesn't dispatch anything, its "one slot" is
	-- just a lifecycle position (0=live, 1=terminal). Immutable once
	-- set (see objects_ast_immutable). SQL guarantees storage integrity
	-- only (valid JSON, top-level array); semantic CaspM validity is
	-- guaranteed out-of-band by the engine/parser. [ghi]
	frame_ast text
		check ((control = 'f' and frame_ast is not null)
			or (control is not 'f' and frame_ast is null))
		check (frame_process_cap is null or frame_ast = '[]'),

	-- Current position within the frame's frame_ast. Set on frames, null on
	-- non-frames. Under the frame_gc cycle the handler sets `frame_gc = 1` on the
	-- frame before the walker's bare `SET frame_stmt_idx = ?` advance; the
	-- schema's advance-requires-frame_gc + auto-set-frame_gc-null triggers handle
	-- the rest. Terminal state: `frame_stmt_idx = json_array_length(frame_ast)`
	-- (for an empty frame_ast, that's 0 — the frame is born terminal).
	--
	-- Third CHECK enforces the upper bound built into the column
	-- itself: frame_stmt_idx never exceeds the frame_ast's length. Replaces the
	-- earlier pair of BEFORE-INSERT and BEFORE-UPDATE OF frame_stmt_idx
	-- triggers with a declarative constraint that fires on any write. [ghi]
	frame_stmt_idx integer
		check (frame_stmt_idx is null
			or (typeof(frame_stmt_idx) = 'integer' and frame_stmt_idx >= 0 and control = 'f'))
		check (frame_stmt_idx is null or frame_stmt_idx <= json_array_length(frame_ast)),

	-- Root-of-frame_process_cap flag. `frame_process_cap = 1` marks this frame as the top
	-- cap of a call stack — the object identity of the frame_process_cap itself.
	-- Null on nested frames (which have frame_parent set instead).
	-- A cap has frame_ast='[]' (see check below), so json_array_length(frame_ast)=0
	-- and the terminal predicate `frame_stmt_idx >= json_array_length(frame_ast)`
	-- is satisfied at frame_stmt_idx=0 — the cap is born terminal and stays there
	-- for the process's lifetime. The frame_stmt_idx <= json_array_length(frame_ast)
	-- CHECK structurally forbids the cap from ever advancing past 0. Frame 0 sits
	-- under the cap as a nested frame. Immutable via objects_process_cap_immutable. [ghi]
	frame_process_cap integer
		check (frame_process_cap = 1)
		check (frame_process_cap is null or control is 'f'),

	-- Sub-frame → parent-frame FK. Frame-only. No cascade. Every frame
	-- has exactly one anchor: either frame_parent (nested frame) or
	-- frame_process_cap=1 (the cap), never both, never neither. Enforced by the
	-- mutual-exclusion check on this column. [ghi]
	frame_parent text
		references objects(object_pk)
		check (frame_parent is null or control is 'f')
		check (control is not 'f'
			or (frame_parent is not null and frame_process_cap is null)
			or (frame_parent is null and frame_process_cap is 1)),

	-- frame_gc-cycle state flag. Bidirectional: null (frame executing normally)
	-- ↔ 1 (frame is past-dispatch, cleanup phase). The cycle:
	--   1. Walker advances frame_stmt_idx AND sets frame_gc=1 (must be same UPDATE).
	--   2. frame_gc=1 fires AFTER trigger that cascade-deletes children.
	--   3. Child-frame delete requires parent's frame_gc=1 (BEFORE-DELETE check).
	--   4. Resetting frame_gc to null requires no child frames (BEFORE-UPDATE check).
	-- Frames-only. [ghi]
	frame_gc integer
		check (frame_gc = 1)
		check (frame_gc is null or control is 'f')
);

-- Partial index for reachability queries over pinned rows. [ghi]
create index objects_persistent on objects(persistent) where persistent = 1;

-- Cap frames — the `uspace` view's frame_process_cap-anchor branch selects
-- `frame_process_cap = 1`; partial index keeps it empty of nulls so the branch
-- doesn't fall back to a full objects scan. [ghi]
create index objects_process_cap on objects(frame_process_cap) where frame_process_cap = 1;

-- Roles are a small population inside a large objects table. The `roles`
-- view (see below) is `select object_pk from objects where control = 'r'`;
-- this partial index keeps the view — and every uspace evaluation that
-- pulls the roles branch — off a full table scan. [ghi]
create index objects_roles on objects(object_pk) where control = 'r';

-- Base immutability for objects. Per-column triggers below handle
-- role_core, role_parent, owner_role, and frame_ast. [ghi]
create trigger objects_no_update
before update on objects
begin
	select case
		when new.object_pk is not old.object_pk
			then raise(abort, 'objects_pk_immutable: objects.object_pk is immutable')
		when new.base is not old.base
			then raise(abort, 'objects_base_immutable: objects.base is immutable')
		when new.scalar_null is not old.scalar_null
			then raise(abort, 'objects_scalar_null_immutable: objects.scalar_null is immutable')
		when new.scalar_string is not old.scalar_string
			then raise(abort, 'objects_scalar_string_immutable: objects.scalar_string is immutable')
		when new.scalar_number is not old.scalar_number
			then raise(abort, 'objects_scalar_number_immutable: objects.scalar_number is immutable')
		when new.scalar_bool is not old.scalar_bool
			then raise(abort, 'objects_scalar_bool_immutable: objects.scalar_bool is immutable')
	end;
end;

-- Non-'o' rows can't carry a scalar in any form: all four value
-- columns must be null. This is the schema-side companion to the
-- per-column check on base='o' rows below. [ghi]
create trigger objects_scalar_columns_only_on_objects
before insert on objects
when (new.base is not 'o' or new.control is not null)
	and (new.scalar_null is not null
		or new.scalar_string is not null
		or new.scalar_number is not null
		or new.scalar_bool is not null)
begin
	select raise(abort, 'objects_scalar_columns_only_on_objects: non-''o'' rows must have all four scalar_* columns null');
end;

-- 'o' rows can hold at most one scalar-value column. Zero columns
-- populated is legal — that's an object that carries no scalar
-- value (a plain object). One column populated identifies the
-- scalar type. Two or more is a schema violation. [ghi]
create trigger objects_scalar_at_most_one_column
before insert on objects
when (new.base = 'o' and new.control is null)
	and (
		(case when new.scalar_null   is not null then 1 else 0 end)
		+ (case when new.scalar_string is not null then 1 else 0 end)
		+ (case when new.scalar_number is not null then 1 else 0 end)
		+ (case when new.scalar_bool   is not null then 1 else 0 end)
	) > 1
begin
	select raise(abort, 'objects_scalar_at_most_one_column: at most one of scalar_null / scalar_string / scalar_number / scalar_bool may be non-null');
end;


-- ------------------------------------------------------------
-- GC trace-state.
--
-- `needs_trace` is PERSISTENT (main schema, real FKs). A mark
-- means "this object needs tracing" and must survive engine
-- restart — an engine that crashes with pending marks needs to
-- know on restart that those objects still need to be traced.
-- Losing the mark would leak.
--
-- The rest of the trace state — `traces`, `in_trace`, and the
-- two FK-equivalent triggers that reproduce cascade semantics
-- for those temp tables — lives in `preflight.sql`. It's
-- per-connection scratch and gets created on every connection
-- open, so it can't live in `schema.sql` (which runs once at
-- DB creation). See preflight.sql for the details.
-- ------------------------------------------------------------

-- Drain worklist. A row here means the object has been marked for
-- retrace by a specific process. PERSISTENT because a mark must
-- survive engine restart — the engine needs to re-trace on the
-- next run if it crashed mid-mark.
--
-- `process_pk` scopes the mark to a specific process's trace (each
-- process cap runs its own reachability sweep independently) and is
-- required. Defaults to `current_process_pk()` — the engine's UDF
-- returning the currently-dispatching process cap's pk — so triggers
-- and callers that INSERT without specifying it pick up the engine's
-- runtime context automatically. The companion trigger
-- `needs_trace_process_pk_must_be_cap` verifies the referenced row
-- is actually a cap (`frame_process_cap = 1`); the FK alone can't check
-- other columns of the target row.
--
-- PRIMARY KEY is composite `(process_pk, object_pk)` — the same
-- object can be marked once per process (each cap runs an
-- independent trace), but a single process cannot double-mark. The
-- ref-delete trigger uses an `ON CONFLICT DO NOTHING` upsert so
-- repeated ref-drops within the same process silently coalesce.
--
-- ON DELETE semantics on the two FKs differ deliberately:
--   * `object_pk` — CASCADE. If the marked object is deleted, its
--     mark row goes with it. Cascades across all processes' marks.
--   * `process_pk` — NO ACTION (RESTRICT). A process cannot be
--     deleted until it has cleaned up its own needs_trace rows.
--     Companion trigger `process_cap_terminal_requires_no_needs_trace`
--     enforces the earlier phase: a cap cannot even advance to its
--     terminal state while any needs_trace rows still reference it. [ghi]
create table needs_trace (
	process_pk text not null
		default (current_process_pk())
		references objects(object_pk),
	object_pk text not null
		references objects(object_pk) on delete cascade,
	primary key (process_pk, object_pk)
);

-- process_pk must reference a cap frame (`frame_process_cap = 1`). [ghi]
create trigger needs_trace_process_pk_must_be_cap
before insert on needs_trace
when (select frame_process_cap from objects where object_pk = new.process_pk) is not 1
begin
	select raise(abort, 'needs_trace_process_pk_must_be_cap: process_pk must reference an objects row with frame_process_cap = 1');
end;

-- (No `process_cap_terminal_requires_no_needs_trace` here — under
-- the current design caps are born at terminal, don't participate
-- in the frame_gc cycle, and don't advance. The worklist-must-be-drained
-- discipline is enforced instead by
-- `frames_gc_reset_requires_empty_needs_trace` below, which blocks
-- the cleanup-complete transition on ANY frame whose current process
-- still has outstanding marks.)

-- A frame's frame_gc cannot flip 1 → null while the current process has
-- any needs_trace rows outstanding. frame_gc = null means "cleanup done,
-- back to executing normally"; that's premature if there's still
-- pending trace work in the worklist.
--
-- Scoped by `current_process_pk()` so a background administrative
-- path touching a non-current cap's frame_gc doesn't get blocked by an
-- unrelated process's worklist. [ghi]
create trigger frames_gc_reset_requires_empty_needs_trace
before update of frame_gc on objects
when old.frame_gc is 1 and new.frame_gc is null
	and exists (select 1 from needs_trace where process_pk = current_process_pk())
begin
	select raise(abort, 'frames_gc_reset_requires_empty_needs_trace: cannot reset frame_gc to null while the current process has outstanding needs_trace rows');
end;


-- ------------------------------------------------------------
-- Refs: parent-to-child object edges. Any row can be a parent;
-- non-container parents ('o', 'f') are capped at one hash-child (its
-- bucket) and one array-child (its stack) by a trigger below.
-- ------------------------------------------------------------

create table refs (
	ref_pk  integer primary key autoincrement,

	parent  text not null references objects(object_pk) on delete cascade,
	-- ON DELETE RESTRICT so a delete with incoming refs raises loudly. [ghi]
	child   text not null references objects(object_pk) on delete restrict,

	-- Hash entries use `key`; array entries leave key null and use idx. [ghi]
	key     text,

	-- Position for arrays; insertion order for hashes.
	-- `typeof(idx) = 'integer'` closes SQLite's affinity hole —
	-- `integer` alone is affinity, not strict typing, so a real like
	-- 1.5 or a text like 'abc' would satisfy `>= 0` without the
	-- typeof clause. [ghi]
	idx     integer not null check (typeof(idx) = 'integer' and idx >= 0),

	-- Human-readable label. Informational. [ghi]
	debug text,

	-- No two refs from the same parent share a key or idx. [ghi]
	unique (parent, key),
	unique (parent, idx)
);

create index refs_parent on refs(parent);
create index refs_child  on refs(child);

-- Non-container parents (base = 'o', which covers plain objects,
-- frames, and roles alike — control layers on top of 'o') carry their
-- top-level properties as keyed refs under a strict shape: at most one
-- bucket (`key = 'b'`), one stack (`key = 's'`), and one shadow
-- (`key = 'h'`). Every ref out of an 'o'-parent MUST use one of those
-- three keys; any other key or a null key is rejected.
--
-- Storage-shape reasoning: modelling the object's structural
-- properties as three well-known keys under a hash means the
-- "at most one" cap comes for free from `unique(parent, key)` — no
-- separate cap trigger needed. Each key/target-shape pairing is
-- enforced by its own type-check trigger below.
--
-- Property → key → target-base:
--   bucket → 'b' → 'h' (a hash of state entries)
--   stack  → 's' → 'a' (an array of classes, innermost-first)
--   shadow → 'h' → 'h' (a hash serving as the top-of-dispatch platter)
--
-- The three properties are optional — an object with none of them is
-- a bare stub. Materialize on demand.
--
-- Roles (control = 'r') are regular objects for this purpose — same
-- b/s/h shape as any other 'o'-based row.
--
-- Buckets/stacks/shadows CAN be shared across multiple owners — the
-- triggers cap a parent's outgoing edges by key but place no cap on a
-- child's incoming refs. Two 'o' rows can both point at the same
-- hash; the graph reads exactly like the refs table shows.
--
-- Two of the three (b and h) both target base='h' rows. They're
-- distinguished by the KEY on the ref, not by the target's shape.
-- Consult the key to know which slot you're looking at.
--
-- NAMING GOTCHA: `key='h'` (shadow) and `base='h'` (hash) both use
-- the letter h. Different columns, different tables, different
-- meanings; they happen to align because the shadow IS a hash.
-- A `key='h'` ref targeting a `base='h'` row is normal — it's a
-- shadow platter attached to its owner. Same letter, different
-- axes. [ghi]
create trigger refs_object_parent_key_must_be_bsh
before insert on refs
when (select base from objects where object_pk = new.parent) = 'o'
	and (new.key is null or new.key not in ('b', 's', 'h'))
begin
	select raise(abort, 'refs_object_parent_key_must_be_bsh: refs from a non-container object (base=''o'') must have key in (''b'', ''s'', ''h'')');
end;

-- key='b' → target must be a hash (base='h'). The bucket is the
-- object's state platter. Fires on any INSERT where the parent is
-- an 'o'-row and the key is 'b'; verifies the child's base. [ghi]
create trigger refs_key_b_target_must_be_hash
before insert on refs
when new.key = 'b'
	and (select base from objects where object_pk = new.parent) = 'o'
	and (select base from objects where object_pk = new.child) is not 'h'
begin
	select raise(abort, 'refs_key_b_target_must_be_hash: a ref with key=''b'' (bucket) must point at a hash (base=''h'')');
end;

-- key='s' → target must be an array (base='a'). The stack is the
-- object's class chain, innermost-first. [ghi]
create trigger refs_key_s_target_must_be_array
before insert on refs
when new.key = 's'
	and (select base from objects where object_pk = new.parent) = 'o'
	and (select base from objects where object_pk = new.child) is not 'a'
begin
	select raise(abort, 'refs_key_s_target_must_be_array: a ref with key=''s'' (stack) must point at an array (base=''a'')');
end;

-- key='h' → target must be a hash (base='h'). The shadow is the
-- top-of-dispatch platter — always consulted first, before the
-- stack. Same target-shape as bucket; distinguished by the key. [ghi]
create trigger refs_key_h_target_must_be_hash
before insert on refs
when new.key = 'h'
	and (select base from objects where object_pk = new.parent) = 'o'
	and (select base from objects where object_pk = new.child) is not 'h'
begin
	select raise(abort, 'refs_key_h_target_must_be_hash: a ref with key=''h'' (shadow) must point at a hash (base=''h'')');
end;

-- refs rows are mostly immutable — `debug` is freely editable (it's
-- informational, no invariant value in freezing it), and `child` is
-- editable so a rebind like `$x = 2` on top of `$x = 1` can UPSERT
-- rather than delete-then-insert. Every other guarded column stays
-- immutable. The WHEN clause guards on any actual guarded-column
-- change; a no-op re-write of the same row is silently accepted.
-- Array child updates are permitted at the schema level too — the
-- same after-update mark trigger below fires on any `child` change,
-- so rebinding an array element by idx (whenever the engine grows
-- that path) marks the outgoing child the same way as a hash rebind. [ghi]
create trigger refs_no_update
before update on refs
when new.ref_pk is not old.ref_pk
	or new.parent is not old.parent
	or new.key is not old.key
	or new.idx is not old.idx
begin
	select raise(abort, 'refs_immutable: refs.ref_pk / parent / key / idx are immutable (only child and debug are editable)');
end;

-- On refs DELETE: mark the old child for trace. Insertion into the
-- separate `needs_trace` table. `process_pk` is omitted from the
-- INSERT — the column's DEFAULT is `current_process_pk()`, so the
-- engine's currently-dispatching process cap gets recorded
-- automatically. The `ON CONFLICT DO NOTHING` upsert coalesces
-- duplicate marks from the same process (matching the composite
-- `(process_pk, object_pk)` PK on needs_trace); a different
-- process dropping a ref to the same child writes a fresh row.
-- The child is guaranteed to still exist in objects at this point
-- — `refs.child` has ON DELETE RESTRICT, so a child object can't
-- be deleted while any ref points at it. [ghi]
create trigger refs_mark_needs_trace_after_delete
after delete on refs
begin
	insert into needs_trace (object_pk) values (old.child)
		on conflict do nothing;
end;

-- On refs UPDATE OF child: mark the OLD child for trace. Mirror of
-- the after-delete mark — a rebind that replaces the child with a
-- new object leaves the previous child dangling exactly the same
-- way a delete-then-insert would, so it needs the same worklist
-- entry. Guarded on `new.child is not old.child` so a no-op UPDATE
-- (same child value written to the same ref, e.g. a bulk touch)
-- doesn't spuriously mark anything. [ghi]
create trigger refs_mark_needs_trace_after_child_update
after update of child on refs
when new.child is not old.child
begin
	insert into needs_trace (object_pk) values (old.child)
		on conflict do nothing;
end;

-- Hash entries REQUIRE a non-null key. A hash-vs-array distinction:
-- hash refs carry a key; array refs use idx and leave key null. This
-- trigger rejects the missing-key case on hash inserts. Only fires on
-- INSERT because refs are immutable.
--
-- No grammar rule on the key's content — any non-null string is a
-- valid hash key. Identifier-shape enforcement is out of scope for
-- the schema; if a language layer wants stricter rules for a
-- particular use of hashes (variable names, method dispatch, etc.),
-- that lives in the language layer. [ghi]
create trigger refs_hash_key_required
before insert on refs
when new.key is null
	and (select base from objects where object_pk = new.parent) = 'h'
begin
	select raise(abort, 'refs_hash_key_required: refs whose parent is a HashPrimitive must have a non-null key');
end;

-- Array entries must NOT have a key — arrays use idx only. Rejects a
-- key set on any ref whose parent is an ArrayPrimitive. Only fires on
-- INSERT because refs are immutable. [ghi]
create trigger refs_array_key_forbidden
before insert on refs
when new.key is not null
	and (select base from objects where object_pk = new.parent) = 'a'
begin
	select raise(abort, 'refs_array_key_forbidden: refs whose parent is an ArrayPrimitive must have a null key (arrays use idx)');
end;

-- Scopes convention enforcement. A frame's bucket has a `scopes` key
-- pointing at an ArrayPrimitive whose entries are hash-primitive scope
-- rows. See requirements/cvm/sqlite/scopes for the design. [ghi]

-- A ref keyed 'scopes' must point at an ArrayPrimitive.
create trigger refs_scopes_key_requires_array
before insert on refs
when new.key = 'scopes'
	and (select base from objects where object_pk = new.child) is not 'a'
begin
	select raise(abort, 'refs_scopes_key_requires_array: a ref with key=''scopes'' must point at an ArrayPrimitive');
end;

-- Entries in a scopes array must be hashes. Fires on INSERT into any
-- array that's referenced by a `scopes`-keyed ref. [ghi]
create trigger refs_scopes_array_entries_must_be_hashes
before insert on refs
when exists (select 1 from refs where child = new.parent and key = 'scopes')
	and (select base from objects where object_pk = new.child) is not 'h'
begin
	select raise(abort, 'refs_scopes_array_entries_must_be_hashes: entries in a scopes array must be hashes');
end;

-- Retro-check: when the `scopes`-keyed ref is inserted, verify any
-- existing entries in the target array are all hashes. Handles the
-- case where refs into the array were inserted before the scopes ref
-- was attached (so refs_scopes_array_entries_must_be_hashes above
-- couldn't fire on them). [ghi]
create trigger refs_scopes_key_existing_entries_must_be_hashes
before insert on refs
when new.key = 'scopes'
	and exists (
		select 1 from refs r
		join objects o on o.object_pk = r.child
		where r.parent = new.child and o.base is not 'h'
	)
begin
	select raise(abort, 'refs_scopes_key_existing_entries_must_be_hashes: the target array already contains non-hash entries');
end;

-- ------------------------------------------------------------
-- Frame frame_ast validation triggers.
-- ------------------------------------------------------------

-- BEFORE INSERT: reject non-array or non-JSON frame_ast on frame rows.
-- Every frame has an frame_ast (biconditional column check); this validator
-- guards the shape. [ghi]
create trigger objects_ast_valid_insert
before insert on objects
when new.control = 'f'
begin
	select case
		when not json_valid(new.frame_ast)
			then raise(abort, 'ast_not_valid_json: frame frame_ast must be valid JSON')
		when json_type(new.frame_ast) != 'array'
			then raise(abort, 'ast_not_array: frame frame_ast must be a JSON array')
	end;
end;

-- frame_ast is immutable once set. [ghi]
create trigger objects_ast_immutable
before update of frame_ast on objects
when new.frame_ast is not old.frame_ast
begin
	select raise(abort, 'ast_immutable: objects.frame_ast is immutable once set');
end;

-- A frame is born with frame_stmt_idx = 0. Transitional rule (trigger,
-- not column CHECK), so a bulk-load with triggers off can install a
-- frame at any mid-state frame_stmt_idx. [ghi]
create trigger frames_stmt_idx_starts_at_zero
before insert on objects
when new.control = 'f' and new.frame_stmt_idx is not 0
begin
	select raise(abort, 'frames_stmt_idx_must_start_at_zero: a frame is born with frame_stmt_idx = 0');
end;

-- New frame_gc-cycle design, rule 2: a frame cannot be inserted with
-- frame_gc = 1. Fresh frames are always born at frame_gc = null; the frame_gc = 1
-- state is reached later via rule 3 (child delete) or manual set. [ghi]
create trigger frames_gc_starts_null
before insert on objects
when new.control = 'f' and new.frame_gc is not null
begin
	select raise(abort, 'frames_gc_starts_null: a frame must be born with frame_gc = null');
end;

-- frame_stmt_idx moves +1 at a time. Skips and rewinds are rejected. A no-op
-- re-write of the same value is silently accepted. [ghi]
create trigger frames_stmt_idx_advances_by_one
before update of frame_stmt_idx on objects
when new.frame_stmt_idx is not old.frame_stmt_idx
	and new.frame_stmt_idx is not old.frame_stmt_idx + 1
begin
	select raise(abort, 'frames_stmt_idx_must_advance_by_one: frame_stmt_idx moves +1 at a time');
end;


-- ------------------------------------------------------------
-- The frame_gc cycle — four invariants
-- ------------------------------------------------------------
-- The walker's per-statement operation is `UPDATE frame SET frame_stmt_idx =
-- frame_stmt_idx + 1, frame_gc = 1`. That single statement's cascade goes:
--
--   1. BEFORE-UPDATE checks pass (advance +1 rule, advance-requires-frame_gc,
--      no-active-children).
--   2. Row updates: frame_stmt_idx moves, frame_gc becomes 1.
--   3. AFTER-UPDATE OF frame_gc fires: DELETE FROM objects WHERE frame_parent
--      = frame — the child (marker or completed nested call) is swept.
--   4. Each child's BEFORE-DELETE checks parent.frame_gc = 1 — passes because
--      step 2 already updated the row.
--   5. Child deleted.
--
-- At-rest state after the cascade: frame at new frame_stmt_idx, frame_gc = 1, no
-- children. The engine then runs GC (needs_trace sweep, on_close
-- callbacks if any) and completes the cycle with `UPDATE frame SET
-- frame_gc = null` — which requires no children (invariant 4).
--
-- Bidirectional frame_gc: null (executing) ↔ 1 (post-dispatch cleanup).

-- New frame_gc-cycle design, rule 5: advancing frame_stmt_idx requires frame_gc = 1
-- to consume. The advance can be issued as bare `UPDATE ... SET
-- frame_stmt_idx = frame_stmt_idx + 1` — the caller does not need to touch frame_gc.
-- The AFTER trigger frames_advance_sets_gc_null (below) auto-sets
-- frame_gc = null as a side effect. [ghi]
create trigger frames_advance_requires_gc
before update of frame_stmt_idx on objects
when new.frame_stmt_idx is not old.frame_stmt_idx and old.frame_gc is not 1
begin
	select raise(abort, 'frames_advance_requires_gc: advancing frame_stmt_idx requires frame_gc = 1');
end;

-- New frame_gc-cycle design, rule 6 (auto-mechanism): advancing frame_stmt_idx
-- automatically sets frame_gc to null. AFTER UPDATE trigger runs a follow-
-- up UPDATE on the same row. The caller never has to include
-- `frame_gc = null` in the advance UPDATE (though it's harmless if they
-- do — the auto-set becomes a no-op). The inner UPDATE fires
-- frames_gc_change_requires_no_child, but rule 4 combined with rule
-- 5 means the frame has no children at the moment of advance
-- (advancing requires frame_gc = 1, frame_gc = 1 requires no children), so the
-- inner UPDATE's WHEN is satisfied. [ghi]
create trigger frames_advance_sets_gc_null
after update of frame_stmt_idx on objects
when new.frame_stmt_idx is not old.frame_stmt_idx
begin
	update objects set frame_gc = null where object_pk = new.object_pk;
end;

-- New frame_gc-cycle design: on advance, the caller may include frame_gc in the
-- SET clause only if the value is null. `SET frame_stmt_idx = N+1, frame_gc = 1`
-- is an engine bug — the auto-set trigger above would silently
-- overwrite the caller's 1 with null, which correct the state but
-- hides the bug. Reject it loudly.
--
-- SQLite fires BEFORE UPDATE OF <col> only when the column appears
-- in the UPDATE's SET clause. So this trigger sees only cases where
-- the caller explicitly wrote frame_gc, not the bare-advance case where
-- frame_gc was left out (and the auto-set does its work). [ghi]
create trigger frames_advance_rejects_non_null_gc
before update of frame_gc on objects
when new.frame_stmt_idx is not old.frame_stmt_idx and new.frame_gc is not null
begin
	select raise(abort, 'frames_advance_rejects_non_null_gc: an advance UPDATE that mentions frame_gc must set it to null');
end;

-- New frame_gc-cycle design, rule 9: a frame cannot be deleted while it
-- has a child. The frame_parent FK (NO ACTION) would already reject
-- the delete with a generic FOREIGN KEY error — this trigger fires
-- first with a specific error id for cleaner diagnostics. [ghi]
create trigger frames_delete_requires_no_child
before delete on objects
when old.control = 'f'
	and exists (
		select 1 from objects
		where frame_parent = old.object_pk and control = 'f'
	)
begin
	select raise(abort, 'frames_delete_requires_no_child: a frame cannot be deleted while it has a child frame');
end;

-- New frame_gc-cycle design, rule 3: deleting a child frame auto-sets the
-- parent's frame_gc to 1. The parent now has 0 children (linear-stack
-- rule: at most 1 child per frame; the one that was there is now
-- gone), so rule 4 permits the change.
--
-- Unconditional. If a bug ever produces a "child under a terminal
-- parent" state (currently unreachable — `no_child_under_terminal_
-- parent` and rules 4+5 together prevent it), rule 7 will reject the
-- auto-set with a specific error id, aborting the outer DELETE. That's
-- the correct diagnostic: a specific rule identifies exactly which
-- invariant was broken, instead of the guard silently absorbing the
-- inconsistency. [ghi]
create trigger frames_child_delete_sets_parent_gc
after delete on objects
when old.control = 'f' and old.frame_parent is not null
	and (select frame_process_cap from objects where object_pk = old.frame_parent) is not 1
begin
	update objects set frame_gc = 1 where object_pk = old.frame_parent;
end;

-- Return-value propagation: on a nested-frame reap, copy the reaping
-- frame's rv to its parent's rv. Under the design where every frame
-- has a return value (implicitly null when unset), parent's rv after
-- a child reap = child's rv at reap. rv is stored as a ref from the
-- frame's bucket with key='rv' pointing at any object.
--
-- Fires on every nested-frame reap — the hottest trigger on the
-- schema once nested-frame dispatch is common. Body is optimized for
-- the update-in-place hot path via ON CONFLICT DO UPDATE.
--
-- BEFORE delete, not AFTER, because the body READS from the child.
-- Every lookup here walks `refs where parent = old.object_pk` (the
-- child's outgoing refs) to find the child's bucket and rv-ref chain.
-- `refs.parent` is `on delete cascade` (see the refs table
-- definition), so once the child's `objects` row is gone, its
-- outgoing refs cascade away with it — an AFTER trigger would see
-- an empty subtree and copy nothing. BEFORE runs while the child's
-- refs are still resolvable. Contrast with the sibling trigger
-- `frames_child_delete_sets_parent_gc` above, which only writes to
-- the parent's own column and needs no data from the child — that
-- one is AFTER because there's nothing time-sensitive to preserve.
--
-- Body statements:
--
-- 1a. Materialize parent's bucket on demand — fires only if the
--     child has an rv AND parent has no bucket yet. object_pk gets
--     a fresh UUID via the column's DEFAULT; owner_role inherits
--     from parent.
-- 1b. Link the new bucket to parent — fires only if 1a inserted
--     (changes() > 0 guard). last_insert_rowid() gives the rowid;
--     lookup produces the object_pk (a UUID, not the rowid).
-- 2.  UPSERT — updates parent's existing rv ref's child in place
--     (hot path — one write, one refs_mark_needs_trace_after_child_update
--     firing to mark the old value) or inserts a new one if parent
--     had no rv yet. CROSS JOIN of two subqueries produces 1 row iff
--     both parent's bucket and child's rv exist; 0 rows otherwise
--     (no-op).
-- 3.  DELETE — clears parent's existing rv ref when the child had no
--     rv (child_rv subquery empty). The DELETE fires the standard
--     refs_mark_needs_trace_after_delete on the old value.
--
-- Cap-exempt via the `old.frame_parent is not null` guard: the cap
-- has no parent, so cap deletion doesn't fire this trigger.
--
-- SQLite parser workaround: ON CONFLICT after a top-level JOIN
-- triggers a "near 'do': syntax error" because the parser reads "on"
-- as a JOIN condition. Wrapping the two lookup subqueries in a
-- nested SELECT (rather than joining directly in FROM) avoids that.
-- Don't "clean up" the nested SELECT back into a JOIN — it will
-- re-trip the parser. [ghi]
create trigger frames_child_delete_propagates_rv
before delete on objects
when old.control = 'f'
	and old.frame_parent is not null
begin
	-- Statement 1a: materialize parent's bucket on demand.
	-- Under the b/s/h shape, "does the parent have a bucket" is
	-- "does a ref with key='b' exist from the parent." Same shape
	-- for looking up child's bucket via key='b'.
	insert into objects (base, owner_role)
	select 'h', (select owner_role from objects where object_pk = old.frame_parent)
	where exists (
		select 1 from refs r1
		join refs r2 on r2.parent = r1.child and r2.key = 'rv'
		where r1.parent = old.object_pk
		  and r1.key = 'b'
	)
	  and not exists (
		select 1 from refs r
		where r.parent = old.frame_parent
		  and r.key = 'b'
	);

	-- Statement 1b: link the new bucket to parent (only if 1a inserted).
	-- Bucket ref is keyed 'b' under the object-property shape.
	insert into refs (parent, child, key, idx)
	select
		old.frame_parent,
		(select object_pk from objects where rowid = last_insert_rowid()),
		'b',
		coalesce(
			(select max(idx) from refs where parent = old.frame_parent),
			-1
		) + 1
	where changes() > 0;

	-- Statement 2: UPSERT — update in place, or insert if parent had no rv.
	-- Bucket lookups now filter by key='b' rather than by target's base;
	-- the type-check trigger guarantees key='b' targets are hashes.
	insert into refs (parent, child, key, idx)
	select
		pb,
		crv,
		'rv',
		coalesce((select max(idx) from refs where parent = pb), -1) + 1
	from (
		select
			(
				select r.child from refs r
				where r.parent = old.frame_parent and r.key = 'b'
			) as pb,
			(
				select r2.child from refs r1
				join refs r2 on r2.parent = r1.child and r2.key = 'rv'
				where r1.parent = old.object_pk and r1.key = 'b'
			) as crv
	)
	where pb is not null and crv is not null
	on conflict (parent, key) do update set child = excluded.child;

	-- Statement 3: DELETE — clear parent's rv when child had none.
	delete from refs
	where key = 'rv'
	  and parent in (
		select r.child from refs r
		where r.parent = old.frame_parent and r.key = 'b'
	)
	  and not exists (
		select 1 from refs r1
		join refs r2 on r2.parent = r1.child and r2.key = 'rv'
		where r1.parent = old.object_pk and r1.key = 'b'
	);
end;

-- New frame_gc-cycle design, rule 4: frame_gc cannot change while the frame has
-- a child. Bidirectional — rejects both null→1 and 1→null. Under
-- the old design, only 1→null was blocked (via
-- frames_gc_reset_requires_no_children) and null→1 cascade-deleted
-- children; the new state machine drops the cascade in favor of
-- strict rejection. At most one child exists per frame
-- (`objects_one_child_per_frame` unique index), so the check is a
-- single existence test. [ghi]
create trigger frames_gc_change_requires_no_child
before update of frame_gc on objects
when new.frame_gc is not old.frame_gc
	and exists (
		select 1 from objects
		where frame_parent = new.object_pk and control = 'f'
	)
begin
	select raise(abort, 'frames_gc_change_requires_no_child: frame_gc cannot change while the frame has a child');
end;

-- New frame_gc-cycle design, rule 7: frame_gc cannot be set to 1 when the frame
-- is already in its terminal state (frame_stmt_idx past the last executable
-- position). Setting frame_gc=1 there would signal "ready to advance," but
-- a terminal frame can't advance — the bounds trigger blocks any
-- further frame_stmt_idx change. A terminal frame's only next legal step
-- is DELETE. Rule 7 keeps the state machine from stalling at
-- (terminal, 1, no children) with no path forward.
--
-- Under normal flow this is unreachable: reaching terminal triggers
-- the auto-delete (rule 8). Guard is for the direct-INSERT edge case
-- and for hardening against engine bugs. [ghi]
create trigger frames_gc_set_rejects_at_terminal
before update of frame_gc on objects
when new.frame_gc is 1
	and new.frame_stmt_idx >= json_array_length(new.frame_ast)
begin
	select raise(abort, 'frames_gc_set_rejects_at_terminal: cannot set frame_gc = 1 when the frame is in its terminal state');
end;


-- `frame_parent` is immutable. A frame's parent is set at INSERT and
-- never changes. Rejects only on actual change. [ghi]
create trigger objects_parent_frame_immutable
before update of frame_parent on objects
when new.frame_parent is not old.frame_parent
begin
	select raise(abort, 'objects_parent_frame_immutable: objects.frame_parent is immutable');
end;

-- `engine_class` is immutable. The mask marker is set at object
-- creation and never changes. Many rows may share the same value
-- (no uniqueness constraint) — that's the intent, since one Lua
-- class typically backs many instances. Rejects only on actual
-- change. [ghi]
create trigger objects_engine_class_immutable
before update of engine_class on objects
when new.engine_class is not old.engine_class
begin
	select raise(abort, 'objects_engine_class_immutable: objects.engine_class is immutable');
end;

-- A frame cannot be its own parent. Defense-in-depth against a state
-- that would spin the walker's "focus on deepest live child" traversal
-- forever. Parallels objects_parent_role_not_self. [ghi]
create trigger frames_parent_frame_not_self
before insert on objects
when new.control = 'f' and new.frame_parent = new.object_pk
begin
	select raise(abort, 'frames_parent_frame_not_self: a frame cannot be its own parent');
end;

-- frame_parent's target must itself be a frame. The column-level
-- CHECK `check (frame_parent is null or control is 'f')` covers the
-- ROW HOLDING the pointer (must be a frame); this trigger covers the
-- TARGET (must also be a frame). Together they enforce
-- "frame_parent links a frame to a frame." Direct control check on
-- the target row. Mirrors objects_parent_role_must_be_role and
-- objects_owner_role_must_be_role. No update-side trigger needed —
-- objects_parent_frame_immutable already blocks changes after INSERT. [ghi]
create trigger objects_parent_frame_must_be_frame
before insert on objects
when new.frame_parent is not null
	and (select control from objects where object_pk = new.frame_parent) is not 'f'
begin
	select raise(abort, 'parent_frame_must_be_frame: frame_parent must reference a frame (control = ''f'')');
end;

-- A child frame cannot be inserted under a nested-frame parent
-- that is in its terminal state. A terminal parent has no more
-- statements to dispatch; spawning a child there would resurrect a
-- done frame.
--
-- CAP parents are exempt (`frame_process_cap is not 1` on the parent). Caps
-- have empty frame_ast and are born terminal under the new formula, and
-- frame 0 is always inserted as a cap's child at boot — that's the
-- normal case, not a resurrection. Caps are static frame_process_cap
-- anchors, not executing frames. [ghi]
create trigger frames_no_child_under_terminal_parent
before insert on objects
when new.frame_parent is not null
	and (
		select frame_stmt_idx >= json_array_length(frame_ast) and frame_process_cap is not 1
		from objects
		where object_pk = new.frame_parent
	)
begin
	select raise(abort, 'frames_no_child_under_terminal_parent: cannot insert a child frame under a parent that is in its terminal state');
end;

-- `frame_process_cap` is immutable. A frame's identity as a cap (or not) is
-- fixed at INSERT and never changes. Rejects only on actual change. [ghi]
create trigger objects_process_cap_immutable
before update of frame_process_cap on objects
when new.frame_process_cap is not old.frame_process_cap
begin
	select raise(abort, 'objects_process_cap_immutable: objects.frame_process_cap is immutable');
end;

-- A parent frame can have at most one child frame at a time. Partial
-- index keeps it empty of nulls (root frames don't participate). Drop-
-- and-replace lands cleanly because the outgoing frame is gone by the
-- time the trigger body runs. [ghi]
create unique index objects_one_child_per_frame on objects(frame_parent)
	where control = 'f' and frame_parent is not null;


-- ------------------------------------------------------------
-- Indexes for the role / ownership / frame columns.
-- ------------------------------------------------------------

-- Unique per role_core value ('e', 'c', 'u'); partial keeps it empty of nulls. [ghi]
create unique index objects_core_role on objects(role_core)
	where role_core is not null;

-- Partial index on role_parent for role-tree traversal. [ghi]
create index objects_parent_role on objects(role_parent) where role_parent is not null;

create index objects_owner_role  on objects(owner_role)  where owner_role is not null;


-- ------------------------------------------------------------
-- Scalars view — read shape for scalar-carrying rows. Derives the
-- scalar type from which value column is populated (no scalar_type
-- column stored anywhere) and coalesces the three data columns into
-- a single `value` field so callers reach the payload without
-- needing to know which affinity slot it lived in.
--
-- `scalar_null` scalars come back with `value` = NULL and
-- `scalar_type` = 'u' — the language-level null value. Non-scalar
-- 'o' rows (plain objects with no scalar assigned) are filtered
-- out — this view is scalar-only. Non-'o' rows are also filtered.
-- Anyone wanting a raw objects-table peek queries `objects`
-- directly; anyone wanting scalar semantics goes through here. [ghi]
create view scalars as
select
	object_pk,
	case
		when scalar_string is not null then 's'
		when scalar_number is not null then 'n'
		when scalar_bool   is not null then 'b'
		when scalar_null   is not null then 'u'
	end as scalar_type,
	coalesce(scalar_string, scalar_number, scalar_bool) as value
from objects
where base = 'o' and control is null
	and (scalar_null   is not null
		or scalar_string is not null
		or scalar_number is not null
		or scalar_bool   is not null);


-- ------------------------------------------------------------
-- Roles view — single source of truth for "what is a role."
-- A role is `control = 'r'`; the view is a single-column filter. [ghi]
create view roles as
	select object_pk from objects where control = 'r';


-- ------------------------------------------------------------
-- Immutability triggers for the role columns (role_core,
-- role_parent, owner_role). Below the roles view because they
-- reference role concepts. [ghi]
-- ------------------------------------------------------------

-- role_core is set at INSERT and never changes. [ghi]
create trigger objects_core_role_immutable
before update of role_core on objects
when new.role_core is not old.role_core
begin
	select raise(abort, 'objects_core_role_immutable: objects.role_core is immutable');
end;

-- role_parent is set at INSERT and never changes. Load-bearing: this
-- immutability is what makes the role tree cycle-free. [ghi]
create trigger objects_parent_role_immutable
before update of role_parent on objects
when new.role_parent is not old.role_parent
begin
	select raise(abort, 'objects_parent_role_immutable: objects.role_parent is immutable (no role reparenting)');
end;

-- Seeds three core-role rows: engine (root), cache, user (both children
-- of engine via role_parent, owned by engine via owner_role). All three
-- are role primitives ('r') and pinned. Seeded before the ownership
-- triggers below, so any grandfathering is transparent. [ghi]

-- Engine — root of the core-role tree.
insert into objects (base, control, role_core, persistent)
	values ('o', 'r', 'e', 1);

-- Cache — child of engine, owned by engine.
insert into objects (base, control, role_core, role_parent, owner_role, persistent)
	values ('o', 'r', 'c',
		(select object_pk from objects where role_core = 'e'),
		(select object_pk from objects where role_core = 'e'),
		1);

-- User — child of engine, owned by engine.
insert into objects (base, control, role_core, role_parent, owner_role, persistent)
	values ('o', 'r', 'u',
		(select object_pk from objects where role_core = 'e'),
		(select object_pk from objects where role_core = 'e'),
		1);

-- Non-role rows must have owner_role set. Roles ('r') may omit it —
-- the engine seed does. Direct control check reads cleaner than
-- the pre-'r' composite test on role_parent + role_core. [ghi]
create trigger objects_owner_role_required_on_non_roles
before insert on objects
when new.control is not 'r' and new.owner_role is null
begin
	select raise(abort, 'objects_owner_role_required: a non-role must have owner_role set');
end;

-- Every non-root role's role_parent must point at a role. Direct
-- control check on the target row — no view subquery. [ghi]
create trigger objects_parent_role_must_be_role
before insert on objects
when new.role_parent is not null
	and (select control from objects where object_pk = new.role_parent) is not 'r'
begin
	select raise(abort, 'parent_role_must_be_role: role_parent must reference a role (control = ''r'')');
end;

-- role_parent cannot be self. Defense-in-depth with a specific error ID. [ghi]
create trigger objects_parent_role_not_self
before insert on objects
when new.role_parent is not null and new.role_parent = new.object_pk
begin
	select raise(abort, 'objects_parent_role_not_self: role_parent cannot equal object_pk');
end;

-- The engine role is the only role that can be tree-root — every
-- other role (cache, user, and any runtime-added role) must have a
-- role_parent. Locks the "single root" shape of the role tree at
-- INSERT time. [ghi]
create trigger objects_only_engine_can_be_role_root
before insert on objects
when new.control = 'r'
	and new.role_parent is null
	and new.role_core is not 'e'
begin
	select raise(abort, 'objects_only_engine_can_be_role_root: only the engine role can have role_parent = null; every other role must have a role_parent');
end;

-- owner_role, if set, must point at a role. Direct control check
-- on the target row — no view subquery. [ghi]
create trigger objects_owner_role_must_be_role
before insert on objects
when new.owner_role is not null
	and (select control from objects where object_pk = new.owner_role) is not 'r'
begin
	select raise(abort, 'owner_role_must_be_role: owner_role must reference a role (control = ''r'')');
end;

-- owner_role is immutable at INSERT — no reparenting. [ghi]
create trigger objects_owner_role_immutable
before update of owner_role on objects
when new.owner_role is not old.owner_role
begin
	select raise(abort, 'objects_owner_role_immutable: owner_role is immutable');
end;

-- owner_role cannot be self. [ghi]
create trigger objects_owner_role_not_self
before insert on objects
when new.owner_role is not null and new.owner_role = new.object_pk
begin
	select raise(abort, 'objects_owner_role_not_self: owner_role cannot equal object_pk');
end;

-- Guards any core-role row. `old.role_core is not null` is sufficient —
-- the cross-column check on role_core means only 'r' rows can have it
-- set, so this WHEN implicitly filters to core-role 'r' rows. [ghi]
create trigger objects_no_delete_root_role
before delete on objects
when old.role_core is not null
begin
	select raise(abort, 'root_role_cannot_be_deleted: core-role rows cannot be deleted');
end;

-- ------------------------------------------------------------
-- Instance-level event listeners. Registrations are bookkeeping,
-- not graph edges — GC does NOT count them as reachability. Weak-ref
-- lifetime via ON DELETE CASCADE on either party. Spec:
-- requirements/events/index. [ghi]
-- ------------------------------------------------------------

create table instance_listeners (
	reg_pk integer primary key autoincrement,

	broadcaster text not null references objects(object_pk) on delete cascade,
	listener    text not null references objects(object_pk) on delete cascade,

	-- event / method names are inline text (interning can come later). [ghi]
	event_name  text not null,
	method_name text not null,

	-- Idempotent: dup .listen_to is one registration, not two. [ghi]
	unique (broadcaster, event_name, listener, method_name)
);

-- Dispatch lookup. [ghi]
create index instance_listeners_broadcaster on instance_listeners(broadcaster, event_name);

-- Unlisten-all lookup. [ghi]
create index instance_listeners_listener on instance_listeners(listener);

-- Registrations are immutable; change = delete + insert. WHEN gates
-- on actual change; a no-op re-write is silently accepted. [ghi]
create trigger instance_listeners_no_update
before update on instance_listeners
when new.reg_pk is not old.reg_pk
	or new.broadcaster is not old.broadcaster
	or new.listener is not old.listener
	or new.event_name is not old.event_name
	or new.method_name is not old.method_name
begin
	select raise(abort, 'instance_listeners_no_update: rows are immutable');
end;


-- ------------------------------------------------------------
-- Class-level event listeners. Same shape as instance_listeners
-- but keyed by class. Spec: requirements/events/listen-to-class. [ghi]
-- ------------------------------------------------------------

create table class_listeners (
	reg_pk integer primary key autoincrement,

	class    text not null references objects(object_pk) on delete cascade,
	listener text not null references objects(object_pk) on delete cascade,

	event_name  text not null,
	method_name text not null,

	unique (class, event_name, listener, method_name)
);

create index class_listeners_class    on class_listeners(class, event_name);
create index class_listeners_listener on class_listeners(listener);

create trigger class_listeners_no_update
before update on class_listeners
when new.reg_pk is not old.reg_pk
	or new.class is not old.class
	or new.listener is not old.listener
	or new.event_name is not old.event_name
	or new.method_name is not old.method_name
begin
	select raise(abort, 'class_listeners_no_update: rows are immutable');
end;


-- ------------------------------------------------------------
-- Debug log. Free-form per-process log entries. `object_pk`
-- references a process cap (an objects row with `frame_process_cap = 1`);
-- ON DELETE CASCADE ties each entry's lifetime to its cap so when a
-- process's cap goes away, its log goes with it. `note` is a
-- required text column — the log's only payload.
-- ------------------------------------------------------------

create table debug_log (
	entry_pk integer primary key autoincrement,

	-- FK to a process cap in objects. Defaults to
	-- `current_process_pk()` — the engine's UDF returning the
	-- currently-dispatching process cap's pk — so triggers and
	-- callers that INSERT without specifying object_pk pick up the
	-- engine's runtime context automatically. Same pattern
	-- needs_trace.process_pk uses. The FK alone only checks that
	-- the target row exists; the companion trigger
	-- debug_log_object_pk_must_be_cap enforces that the target's
	-- frame_process_cap column is 1. ON DELETE CASCADE: when the process
	-- cap is deleted, its debug_log rows go with it. [ghi]
	object_pk text not null
		default (current_process_pk())
		references objects(object_pk) on delete cascade,

	-- Free-form log text. Required. No shape check on the content —
	-- the log's whole surface is a bag of strings the engine chose
	-- to record. [ghi]
	note text not null
);

-- Lookup by process. Every read of the log filters by object_pk
-- (`select ... from debug_log where object_pk = ?`), so a plain
-- index on that column keeps it off a full scan.
create index debug_log_object_pk on debug_log(object_pk);

-- object_pk must reference a cap frame (frame_process_cap = 1). The FK
-- alone can't check other columns of the target row; this trigger
-- fills the gap. Mirrors needs_trace_process_pk_must_be_cap. [ghi]
create trigger debug_log_object_pk_must_be_cap
before insert on debug_log
when (select frame_process_cap from objects where object_pk = new.object_pk) is not 1
begin
	select raise(abort, 'debug_log_object_pk_must_be_cap: object_pk must reference an objects row with frame_process_cap = 1');
end;


-- ------------------------------------------------------------
-- Frame-column indexes.
-- ------------------------------------------------------------

-- The child-of-frame walk ("given a frame pk, find its child
-- sub-frame") is already served by the `objects_one_child_per_frame`
-- unique partial index above — same key (frame_parent), same predicate
-- (control='f' and frame_parent is not null). A second non-unique
-- copy alongside it is pure index-maintenance overhead and buys
-- nothing at read time; SQLite will pick the unique one for lookups
-- as readily as for uniqueness enforcement. [ghi]


-- ------------------------------------------------------------
-- uspace — derived view of GC anchor set. Cost per check: one
-- indexed lookup per union branch. [ghi]
-- ------------------------------------------------------------

create view uspace as
	-- Every role (root + non-root) — pulled from the roles view.
	-- Roles branch is now a single-column filter on `control = 'r'`
	-- via the roles view; the eventual test_view_indexes.lua uspace
	-- plan will show one lookup on this branch, not the historical
	-- UNION-of-two. [ghi]
	select object_pk from roles
	union
	-- Objects flagged persistent. [ghi]
	select object_pk from objects where persistent = 1
	union
	-- Process caps — the top of every live call stack. Frame 0 and
	-- everything below it are reachable via frame_parent from the cap. [ghi]
	select object_pk from objects where control = 'f' and frame_process_cap = 1;


-- ------------------------------------------------------------
-- frame_scoped_vars — flattened view of every variable visible from
-- a frame's scope chain. One row per (frame, scope position, var
-- name). scope_idx=0 is the frame's own scope (innermost); higher
-- indexes are captured scopes from an enclosing closure.
--
-- For a straight lookup: `SELECT value_pk FROM frame_scoped_vars
-- WHERE frame_pk = ? AND var_name = ? ORDER BY scope_idx LIMIT 1` —
-- returns the effective binding (nearest scope wins).
--
-- For a full dump: `SELECT * FROM frame_scoped_vars WHERE frame_pk
-- = ?` — every scoped var, with its scope depth.
--
-- Cost per row: all joins go through indexed lookups (refs.parent,
-- PK on objects). The bucket join uses refs_parent + a base
-- filter to pick out the frame's hash-child. [ghi]
-- ------------------------------------------------------------
create view frame_scoped_vars as
select
	f.object_pk         as frame_pk,
	scope_ref.idx       as scope_idx,
	var_ref.key         as var_name,
	var_ref.child       as value_pk
from objects f
	join refs bucket_ref
		on bucket_ref.parent = f.object_pk
		and bucket_ref.key = 'b'
	join refs scopes_ref
		on scopes_ref.parent = bucket_ref.child
		and scopes_ref.key = 'scopes'
	join refs scope_ref
		on scope_ref.parent = scopes_ref.child
	join refs var_ref
		on var_ref.parent = scope_ref.child
where f.control = 'f';


-- ------------------------------------------------------------
-- object_bucket — every non-container object with its bucket_pk
-- (or null if it hasn't been given one). "Non-container" = base = 'o'
-- (covers plain objects, frames, and roles alike — control layers on
-- top of 'o'). Those are the ones the one-hash-one-array trigger caps,
-- so the correlated subquery returns at most one row and lands safely
-- as a scalar value.
--
-- **No caller yet.** Kept in the schema as a convenience for whoever
-- eventually needs "give me this object's bucket" without hand-writing
-- the refs + objects + base-filter join. Usage:
-- `SELECT bucket_pk FROM object_bucket WHERE object_pk = ?`. [ghi]
-- ------------------------------------------------------------
create view object_bucket as
select
	o.object_pk as object_pk,
	(
		select r.child
		from refs r
		where r.parent = o.object_pk and r.key = 'b'
	) as bucket_pk
from objects o
where o.base = 'o';


-- ------------------------------------------------------------
-- object_stack — every non-container object with its stack_pk
-- (or null if it hasn't been given one). Filter is `refs.key = 's'`;
-- the type-check trigger guarantees any such target is an array. [ghi]
-- ------------------------------------------------------------
create view object_stack as
select
	o.object_pk as object_pk,
	(
		select r.child
		from refs r
		where r.parent = o.object_pk and r.key = 's'
	) as stack_pk
from objects o
where o.base = 'o';


-- ------------------------------------------------------------
-- object_shadow — every non-container object with its shadow_pk
-- (or null if it hasn't been given one). Filter is `refs.key = 'h'`;
-- the type-check trigger guarantees any such target is a hash.
-- Symmetric with object_bucket (both target hashes) — the axis
-- that distinguishes them is the key, not the target's shape. [ghi]
-- ------------------------------------------------------------
create view object_shadow as
select
	o.object_pk as object_pk,
	(
		select r.child
		from refs r
		where r.parent = o.object_pk and r.key = 'h'
	) as shadow_pk
from objects o
where o.base = 'o';
