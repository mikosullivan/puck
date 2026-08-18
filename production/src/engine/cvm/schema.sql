-- Caspian virtual machine
-- This schema defines the SQLite format for a Caspian virtual
-- machine. The intent of this design is that only valid programmatic
-- states can be stored in the database. It should not be possible
-- to build an invalid state.

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

insert into cvm (key, value) values ('schema', '9.0');


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

	-- Row-kind discriminator:
	--   'o' → object
	--   'h' → HashPrimitive
	--   'a' → ArrayPrimitive
	--   'f' → frame
	--   'r' → role
	-- [ghi]
	primitive text not null check (primitive in ('o', 'h', 'a', 'f', 'r')),

	-- Scalar type. Only meaningful when primitive = 'o'. [ghi]
	scalar_type text
		check (scalar_type in ('s', 'n', 'b', 'u'))
		check (primitive = 'o' or scalar_type is null),

	-- Scalar value. Meaningful only when `scalar_type` is set. Declared
	-- `blob` for no-affinity storage. [ghi]
	scalar_value blob
		check (scalar_type is null or scalar_type != 'b' or scalar_value is 0 or scalar_value is 1)
		check (scalar_type is null or scalar_type != 'u' or scalar_value is null)
		check (scalar_type is null or scalar_type != 'n' or typeof(scalar_value) in ('integer', 'real'))
		check (scalar_type is null or scalar_type != 's' or typeof(scalar_value) = 'text')
		check (scalar_type is not null or scalar_value is null),

	-- Mask marker: names a Lua-side engine class whose behavior the row
	-- surfaces as. Nullable — most rows carry null. Only `'o'` rows may
	-- set it (a mask sits on an object; frames, roles, hashes, arrays
	-- can't be masks). The meaning of a specific value (which Lua class
	-- name, how it's looked up, how it surfaces as a Caspian class) is
	-- deferred to a later sprint. [ghi]
	engine_class text
		check (engine_class is null or primitive = 'o'),

	-- Core-role marker: 'e' (engine), 'c' (cache), 'u' (user). Nullable
	-- — most rows aren't core roles. Unique per value via the partial
	-- index below. Only role rows ('r') may carry a core_role. [ghi]
	core_role text
		check (core_role in ('e', 'c', 'u'))
		check (core_role is null or primitive = 'r'),

	-- Role-tree parentage. Non-root roles set this. Immutable via
	-- objects_parent_role_immutable. Only role rows ('r') may carry a
	-- parent_role — enforced by the cross-column check below. The
	-- target-primitive check (that parent_role points at an 'r' row)
	-- lives in the objects_parent_role_must_be_role trigger. No
	-- ON DELETE clause — defaults to NO ACTION, which with
	-- `foreign_keys = on` acts as RESTRICT: a role can't be deleted if
	-- any other role references it via parent_role. Force cleanup from
	-- the leaves up. [ghi]
	parent_role text
		references objects(object_pk)
		check (parent_role is null or primitive = 'r'),

	-- Pointer to the role that created this row. Required for non-role
	-- rows (see objects_owner_role_required_on_non_roles). Roles may
	-- also carry it (cache and user are owned by engine). No cascade.
	-- Target-primitive check (points at an 'r' row) enforced by the
	-- objects_owner_role_must_be_role trigger below. [ghi]
	owner_role text references objects(object_pk),

	-- CaspM tree as JSON text. Biconditional with primitive='f' — every
	-- frame has an ast, no non-frame does. A cap frame (process_cap=1) has
	-- ast='[]' — the cap doesn't dispatch anything, its "one slot" is
	-- just a lifecycle position (0=live, 1=terminal). Immutable once
	-- set (see objects_ast_immutable). SQL guarantees storage integrity
	-- only (valid JSON, top-level array); semantic CaspM validity is
	-- guaranteed out-of-band by the engine/parser. [ghi]
	ast text
		check ((primitive = 'f' and ast is not null)
			or (primitive != 'f' and ast is null))
		check (process_cap is null or ast = '[]'),

	-- Current position within the frame's ast. Set on frames, null on
	-- non-frames. Under the gc cycle the handler sets `gc = 1` on the
	-- frame before the walker's bare `SET stmt_idx = ?` advance; the
	-- schema's advance-requires-gc + auto-set-gc-null triggers handle
	-- the rest. Terminal state: `stmt_idx = json_array_length(ast)`
	-- (for an empty ast, that's 0 — the frame is born terminal).
	--
	-- Third CHECK enforces the upper bound built into the column
	-- itself: stmt_idx never exceeds the ast's length. Replaces the
	-- earlier pair of BEFORE-INSERT and BEFORE-UPDATE OF stmt_idx
	-- triggers with a declarative constraint that fires on any write. [ghi]
	stmt_idx integer
		check (stmt_idx is null
			or (typeof(stmt_idx) = 'integer' and stmt_idx >= 0 and primitive = 'f'))
		check (stmt_idx is null or stmt_idx <= json_array_length(ast)),

	-- Root-of-process_cap flag. `process_cap = 1` marks this frame as the top
	-- cap of a call stack — the object identity of the process_cap itself.
	-- Null on nested frames (which have parent_frame set instead).
	-- A cap has ast='[]' (see check below), starts at stmt_idx=0, and
	-- becomes terminal when it reaches stmt_idx=1 with gc=null and no
	-- children. Frame 0 sits under the cap as a nested frame. Immutable
	-- via objects_process_cap_immutable. [ghi]
	process_cap integer
		check (process_cap = 1)
		check (process_cap is null or primitive = 'f'),

	-- Sub-frame → parent-frame FK. Frame-only. No cascade. Every frame
	-- has exactly one anchor: either parent_frame (nested frame) or
	-- process_cap=1 (the cap), never both, never neither. Enforced by the
	-- mutual-exclusion check on this column. [ghi]
	parent_frame text
		references objects(object_pk)
		check (parent_frame is null or primitive = 'f')
		check (primitive != 'f'
			or (parent_frame is not null and process_cap is null)
			or (parent_frame is null and process_cap is 1)),

	-- No dedicated bucket/stack columns. Ownership of a bucket or a
	-- stack is a normal `refs` row from the owner to the collection.
	-- The one-hash-one-array trigger (see refs section below) caps a
	-- non-container parent to at most one HashPrimitive child (its
	-- bucket) and at most one ArrayPrimitive child (its stack).
	-- Buckets and stacks can be shared across multiple owners — the
	-- graph reads exactly like the refs table shows.

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
		check (core_role is null or persistent is 1),

	-- gc-cycle state flag. Bidirectional: null (frame executing normally)
	-- ↔ 1 (frame is past-dispatch, cleanup phase). The cycle:
	--   1. Walker advances stmt_idx AND sets gc=1 (must be same UPDATE).
	--   2. gc=1 fires AFTER trigger that cascade-deletes children.
	--   3. Child-frame delete requires parent's gc=1 (BEFORE-DELETE check).
	--   4. Resetting gc to null requires no child frames (BEFORE-UPDATE check).
	-- Frames-only. [ghi]
	gc integer
		check (gc = 1)
		check (gc is null or primitive = 'f'),

	-- Human-readable label. Informational; no query path reads it. [ghi]
	debug text
);

-- Partial index for reachability queries over pinned rows. [ghi]
create index objects_persistent on objects(persistent) where persistent = 1;

-- Cap frames — the `uspace` view's process_cap-anchor branch selects
-- `process_cap = 1`; partial index keeps it empty of nulls so the branch
-- doesn't fall back to a full objects scan. [ghi]
create index objects_process_cap on objects(process_cap) where process_cap = 1;

-- Roles are a small population inside a large objects table. The `roles`
-- view (see below) is `select object_pk from objects where primitive = 'r'`;
-- this partial index keeps the view — and every uspace evaluation that
-- pulls the roles branch — off a full table scan. [ghi]
create index objects_roles on objects(object_pk) where primitive = 'r';

-- Base immutability for objects. Per-column triggers below handle
-- core_role, parent_role, owner_role, and ast. [ghi]
create trigger objects_no_update
before update on objects
begin
	select case
		when new.object_pk is not old.object_pk
			then raise(abort, 'objects_pk_immutable: objects.object_pk is immutable')
		when new.primitive is not old.primitive
			then raise(abort, 'objects_primitive_immutable: objects.primitive is immutable')
		when new.scalar_type is not old.scalar_type
			then raise(abort, 'objects_scalar_type_immutable: objects.scalar_type is immutable')
		when new.scalar_value is not old.scalar_value
			then raise(abort, 'objects_scalar_value_immutable: objects.scalar_value is immutable')
	end;
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
-- is actually a cap (`process_cap = 1`); the FK alone can't check
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

-- process_pk must reference a cap frame (`process_cap = 1`). [ghi]
create trigger needs_trace_process_pk_must_be_cap
before insert on needs_trace
when (select process_cap from objects where object_pk = new.process_pk) is not 1
begin
	select raise(abort, 'needs_trace_process_pk_must_be_cap: process_pk must reference an objects row with process_cap = 1');
end;

-- (No `process_cap_terminal_requires_no_needs_trace` here — under
-- the current design caps are born at terminal, don't participate
-- in the gc cycle, and don't advance. The worklist-must-be-drained
-- discipline is enforced instead by
-- `frames_gc_reset_requires_empty_needs_trace` below, which blocks
-- the cleanup-complete transition on ANY frame whose current process
-- still has outstanding marks.)

-- A frame's gc cannot flip 1 → null while the current process has
-- any needs_trace rows outstanding. gc = null means "cleanup done,
-- back to executing normally"; that's premature if there's still
-- pending trace work in the worklist.
--
-- Scoped by `current_process_pk()` so a background administrative
-- path touching a non-current cap's gc doesn't get blocked by an
-- unrelated process's worklist. [ghi]
create trigger frames_gc_reset_requires_empty_needs_trace
before update of gc on objects
when old.gc is 1 and new.gc is null
	and exists (select 1 from needs_trace where process_pk = current_process_pk())
begin
	select raise(abort, 'frames_gc_reset_requires_empty_needs_trace: cannot reset gc to null while the current process has outstanding needs_trace rows');
end;


-- ------------------------------------------------------------
-- Refs: parent-to-child object edges. Any primitive can be a parent;
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

-- Non-container parents ('o', 'f') can hold at most one HashPrimitive
-- child (which serves as its bucket) and at most one ArrayPrimitive
-- child (which serves as its stack). Container parents ('h', 'a') have
-- no such cap — they hold as many children as they want by their
-- native semantics. Owner-owns-bucket / owner-owns-stack is just a
-- normal refs row now; the whole "ownership" story lives in this one
-- table.
--
-- Buckets and stacks CAN be shared across multiple owners — the trigger
-- caps a parent's outgoing 'h'/'a' children but places no cap on a
-- child's incoming refs. Two 'o' rows can both point at the same hash;
-- the graph reads exactly like the refs table shows. The trigger name
-- says "owner" because "owner" is the domain term for the parent side
-- of a bucket/stack ref, not because it implies exclusive ownership. [ghi]
create trigger refs_owner_at_most_one_hash_and_one_array
before insert on refs
when (select primitive from objects where object_pk = new.parent) in ('o', 'f')
	and (select primitive from objects where object_pk = new.child) in ('h', 'a')
	and exists (
		select 1 from refs r
		join objects c on c.object_pk = r.child
		where r.parent = new.parent
			and c.primitive = (select primitive from objects where object_pk = new.child)
	)
begin
	select raise(abort, 'refs_owner_at_most_one_hash_and_one_array: a non-container object can hold at most one hash (its bucket) and one array (its stack) as refs children');
end;

-- refs rows are immutable except for `debug`, which is a human-
-- readable informational label with no query path reading it (so
-- freezing it at INSERT-time offers no invariant value). Rebind is
-- delete + insert. WHEN gates on any actual guarded-column change;
-- a no-op re-write of the same row is silently accepted. [ghi]
create trigger refs_no_update
before update on refs
when new.ref_pk is not old.ref_pk
	or new.parent is not old.parent
	or new.child is not old.child
	or new.key is not old.key
	or new.idx is not old.idx
begin
	select raise(abort, 'refs_immutable: refs rows are immutable');
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
	and (select primitive from objects where object_pk = new.parent) = 'h'
begin
	select raise(abort, 'refs_hash_key_required: refs whose parent is a HashPrimitive must have a non-null key');
end;

-- Array entries must NOT have a key — arrays use idx only. Rejects a
-- key set on any ref whose parent is an ArrayPrimitive. Only fires on
-- INSERT because refs are immutable. [ghi]
create trigger refs_array_key_forbidden
before insert on refs
when new.key is not null
	and (select primitive from objects where object_pk = new.parent) = 'a'
begin
	select raise(abort, 'refs_array_key_forbidden: refs whose parent is an ArrayPrimitive must have a null key (arrays use idx)');
end;

-- Scopes convention enforcement. A frame's bucket has a `scopes` key
-- pointing at an ArrayPrimitive whose entries are hash-primitive scope
-- rows. See requirements/cvm/scopes for the design. [ghi]

-- A ref keyed 'scopes' must point at an ArrayPrimitive.
create trigger refs_scopes_key_requires_array
before insert on refs
when new.key = 'scopes'
	and (select primitive from objects where object_pk = new.child) is not 'a'
begin
	select raise(abort, 'refs_scopes_key_requires_array: a ref with key=''scopes'' must point at an ArrayPrimitive');
end;

-- Entries in a scopes array must be hashes. Fires on INSERT into any
-- array that's referenced by a `scopes`-keyed ref. [ghi]
create trigger refs_scopes_array_entries_must_be_hashes
before insert on refs
when exists (select 1 from refs where child = new.parent and key = 'scopes')
	and (select primitive from objects where object_pk = new.child) is not 'h'
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
		where r.parent = new.child and o.primitive is not 'h'
	)
begin
	select raise(abort, 'refs_scopes_key_existing_entries_must_be_hashes: the target array already contains non-hash entries');
end;

-- ------------------------------------------------------------
-- Frame ast validation triggers.
-- ------------------------------------------------------------

-- BEFORE INSERT: reject non-array or non-JSON ast on frame rows.
-- Every frame has an ast (biconditional column check); this validator
-- guards the shape. [ghi]
create trigger objects_ast_valid_insert
before insert on objects
when new.primitive = 'f'
begin
	select case
		when not json_valid(new.ast)
			then raise(abort, 'ast_not_valid_json: frame ast must be valid JSON')
		when json_type(new.ast) != 'array'
			then raise(abort, 'ast_not_array: frame ast must be a JSON array')
	end;
end;

-- ast is immutable once set. [ghi]
create trigger objects_ast_immutable
before update of ast on objects
when new.ast is not old.ast
begin
	select raise(abort, 'ast_immutable: objects.ast is immutable once set');
end;

-- A frame is born with stmt_idx = 0. Transitional rule (trigger,
-- not column CHECK), so a bulk-load with triggers off can install a
-- frame at any mid-state stmt_idx. [ghi]
create trigger frames_stmt_idx_starts_at_zero
before insert on objects
when new.primitive = 'f' and new.stmt_idx is not 0
begin
	select raise(abort, 'frames_stmt_idx_must_start_at_zero: a frame is born with stmt_idx = 0');
end;

-- New gc-cycle design, rule 2: a frame cannot be inserted with
-- gc = 1. Fresh frames are always born at gc = null; the gc = 1
-- state is reached later via rule 3 (child delete) or manual set. [ghi]
create trigger frames_gc_starts_null
before insert on objects
when new.primitive = 'f' and new.gc is not null
begin
	select raise(abort, 'frames_gc_starts_null: a frame must be born with gc = null');
end;

-- stmt_idx moves +1 at a time. Skips and rewinds are rejected. A no-op
-- re-write of the same value is silently accepted. [ghi]
create trigger frames_stmt_idx_advances_by_one
before update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx
	and new.stmt_idx is not old.stmt_idx + 1
begin
	select raise(abort, 'frames_stmt_idx_must_advance_by_one: stmt_idx moves +1 at a time');
end;


-- ------------------------------------------------------------
-- The gc cycle — four invariants
-- ------------------------------------------------------------
-- The walker's per-statement operation is `UPDATE frame SET stmt_idx =
-- stmt_idx + 1, gc = 1`. That single statement's cascade goes:
--
--   1. BEFORE-UPDATE checks pass (advance +1 rule, advance-requires-gc,
--      no-active-children).
--   2. Row updates: stmt_idx moves, gc becomes 1.
--   3. AFTER-UPDATE OF gc fires: DELETE FROM objects WHERE parent_frame
--      = frame — the child (marker or completed nested call) is swept.
--   4. Each child's BEFORE-DELETE checks parent.gc = 1 — passes because
--      step 2 already updated the row.
--   5. Child deleted.
--
-- At-rest state after the cascade: frame at new stmt_idx, gc = 1, no
-- children. The engine then runs GC (needs_trace sweep, on_close
-- callbacks if any) and completes the cycle with `UPDATE frame SET
-- gc = null` — which requires no children (invariant 4).
--
-- Bidirectional gc: null (executing) ↔ 1 (post-dispatch cleanup).

-- New gc-cycle design, rule 5: advancing stmt_idx requires gc = 1
-- to consume. The advance can be issued as bare `UPDATE ... SET
-- stmt_idx = stmt_idx + 1` — the caller does not need to touch gc.
-- The AFTER trigger frames_advance_sets_gc_null (below) auto-sets
-- gc = null as a side effect. [ghi]
create trigger frames_advance_requires_gc
before update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx and old.gc is not 1
begin
	select raise(abort, 'frames_advance_requires_gc: advancing stmt_idx requires gc = 1');
end;

-- New gc-cycle design, rule 6 (auto-mechanism): advancing stmt_idx
-- automatically sets gc to null. AFTER UPDATE trigger runs a follow-
-- up UPDATE on the same row. The caller never has to include
-- `gc = null` in the advance UPDATE (though it's harmless if they
-- do — the auto-set becomes a no-op). The inner UPDATE fires
-- frames_gc_change_requires_no_child, but rule 4 combined with rule
-- 5 means the frame has no children at the moment of advance
-- (advancing requires gc = 1, gc = 1 requires no children), so the
-- inner UPDATE's WHEN is satisfied. [ghi]
create trigger frames_advance_sets_gc_null
after update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx
begin
	update objects set gc = null where object_pk = new.object_pk;
end;

-- New gc-cycle design: on advance, the caller may include gc in the
-- SET clause only if the value is null. `SET stmt_idx = N+1, gc = 1`
-- is an engine bug — the auto-set trigger above would silently
-- overwrite the caller's 1 with null, which correct the state but
-- hides the bug. Reject it loudly.
--
-- SQLite fires BEFORE UPDATE OF <col> only when the column appears
-- in the UPDATE's SET clause. So this trigger sees only cases where
-- the caller explicitly wrote gc, not the bare-advance case where
-- gc was left out (and the auto-set does its work). [ghi]
create trigger frames_advance_rejects_non_null_gc
before update of gc on objects
when new.stmt_idx is not old.stmt_idx and new.gc is not null
begin
	select raise(abort, 'frames_advance_rejects_non_null_gc: an advance UPDATE that mentions gc must set it to null');
end;

-- New gc-cycle design, rule 9: a frame cannot be deleted while it
-- has a child. The parent_frame FK (NO ACTION) would already reject
-- the delete with a generic FOREIGN KEY error — this trigger fires
-- first with a specific error id for cleaner diagnostics. [ghi]
create trigger frames_delete_requires_no_child
before delete on objects
when old.primitive = 'f'
	and exists (
		select 1 from objects
		where parent_frame = old.object_pk and primitive = 'f'
	)
begin
	select raise(abort, 'frames_delete_requires_no_child: a frame cannot be deleted while it has a child frame');
end;

-- New gc-cycle design, rule 3: deleting a child frame auto-sets the
-- parent's gc to 1. The parent now has 0 children (linear-stack
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
when old.primitive = 'f' and old.parent_frame is not null
	and (select process_cap from objects where object_pk = old.parent_frame) is not 1
begin
	update objects set gc = 1 where object_pk = old.parent_frame;
end;

-- New gc-cycle design, rule 4: gc cannot change while the frame has
-- a child. Bidirectional — rejects both null→1 and 1→null. Under
-- the old design, only 1→null was blocked (via
-- frames_gc_reset_requires_no_children) and null→1 cascade-deleted
-- children; the new state machine drops the cascade in favor of
-- strict rejection. At most one child exists per frame
-- (`objects_one_child_per_frame` unique index), so the check is a
-- single existence test. [ghi]
create trigger frames_gc_change_requires_no_child
before update of gc on objects
when new.gc is not old.gc
	and exists (
		select 1 from objects
		where parent_frame = new.object_pk and primitive = 'f'
	)
begin
	select raise(abort, 'frames_gc_change_requires_no_child: gc cannot change while the frame has a child');
end;

-- New gc-cycle design, rule 7: gc cannot be set to 1 when the frame
-- is already in its terminal state (stmt_idx past the last executable
-- position). Setting gc=1 there would signal "ready to advance," but
-- a terminal frame can't advance — the bounds trigger blocks any
-- further stmt_idx change. A terminal frame's only next legal step
-- is DELETE. Rule 7 keeps the state machine from stalling at
-- (terminal, 1, no children) with no path forward.
--
-- Under normal flow this is unreachable: reaching terminal triggers
-- the auto-delete (rule 8). Guard is for the direct-INSERT edge case
-- and for hardening against engine bugs. [ghi]
create trigger frames_gc_set_rejects_at_terminal
before update of gc on objects
when new.gc is 1
	and new.stmt_idx >= json_array_length(new.ast)
begin
	select raise(abort, 'frames_gc_set_rejects_at_terminal: cannot set gc = 1 when the frame is in its terminal state');
end;


-- `parent_frame` is immutable. A frame's parent is set at INSERT and
-- never changes. Rejects only on actual change. [ghi]
create trigger objects_parent_frame_immutable
before update of parent_frame on objects
when new.parent_frame is not old.parent_frame
begin
	select raise(abort, 'objects_parent_frame_immutable: objects.parent_frame is immutable');
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
when new.primitive = 'f' and new.parent_frame = new.object_pk
begin
	select raise(abort, 'frames_parent_frame_not_self: a frame cannot be its own parent');
end;

-- parent_frame's target must itself be a frame. The column-level
-- CHECK `check (parent_frame is null or primitive = 'f')` covers the
-- ROW HOLDING the pointer (must be a frame); this trigger covers the
-- TARGET (must also be a frame). Together they enforce
-- "parent_frame links a frame to a frame." Direct primitive check on
-- the target row. Mirrors objects_parent_role_must_be_role and
-- objects_owner_role_must_be_role. No update-side trigger needed —
-- objects_parent_frame_immutable already blocks changes after INSERT. [ghi]
create trigger objects_parent_frame_must_be_frame
before insert on objects
when new.parent_frame is not null
	and (select primitive from objects where object_pk = new.parent_frame) is not 'f'
begin
	select raise(abort, 'parent_frame_must_be_frame: parent_frame must reference a frame (primitive = ''f'')');
end;

-- A child frame cannot be inserted under a nested-frame parent
-- that is in its terminal state. A terminal parent has no more
-- statements to dispatch; spawning a child there would resurrect a
-- done frame.
--
-- CAP parents are exempt (`process_cap is not 1` on the parent). Caps
-- have empty ast and are born terminal under the new formula, and
-- frame 0 is always inserted as a cap's child at boot — that's the
-- normal case, not a resurrection. Caps are static process_cap
-- anchors, not executing frames. [ghi]
create trigger frames_no_child_under_terminal_parent
before insert on objects
when new.parent_frame is not null
	and (
		select stmt_idx >= json_array_length(ast) and process_cap is not 1
		from objects
		where object_pk = new.parent_frame
	)
begin
	select raise(abort, 'frames_no_child_under_terminal_parent: cannot insert a child frame under a parent that is in its terminal state');
end;

-- `process_cap` is immutable. A frame's identity as a cap (or not) is
-- fixed at INSERT and never changes. Rejects only on actual change. [ghi]
create trigger objects_process_cap_immutable
before update of process_cap on objects
when new.process_cap is not old.process_cap
begin
	select raise(abort, 'objects_process_cap_immutable: objects.process_cap is immutable');
end;

-- A parent frame can have at most one child frame at a time. Partial
-- index keeps it empty of nulls (root frames don't participate). Drop-
-- and-replace lands cleanly because the outgoing frame is gone by the
-- time the trigger body runs. [ghi]
create unique index objects_one_child_per_frame on objects(parent_frame)
	where primitive = 'f' and parent_frame is not null;


-- ------------------------------------------------------------
-- Indexes for the role / ownership / frame columns.
-- ------------------------------------------------------------

-- Unique per core_role value ('e', 'c', 'u'); partial keeps it empty of nulls. [ghi]
create unique index objects_core_role on objects(core_role)
	where core_role is not null;

-- Partial index on parent_role for role-tree traversal. [ghi]
create index objects_parent_role on objects(parent_role) where parent_role is not null;

create index objects_owner_role  on objects(owner_role)  where owner_role is not null;


-- ------------------------------------------------------------
-- Roles view — single source of truth for "what is a role."
-- A role is `primitive = 'r'`; the view is a single-column filter. [ghi]
create view roles as
	select object_pk from objects where primitive = 'r';


-- ------------------------------------------------------------
-- Immutability triggers for the role columns (core_role,
-- parent_role, owner_role). Below the roles view because they
-- reference role concepts. [ghi]
-- ------------------------------------------------------------

-- core_role is set at INSERT and never changes. [ghi]
create trigger objects_core_role_immutable
before update of core_role on objects
when new.core_role is not old.core_role
begin
	select raise(abort, 'objects_core_role_immutable: objects.core_role is immutable');
end;

-- parent_role is set at INSERT and never changes. Load-bearing: this
-- immutability is what makes the role tree cycle-free. [ghi]
create trigger objects_parent_role_immutable
before update of parent_role on objects
when new.parent_role is not old.parent_role
begin
	select raise(abort, 'objects_parent_role_immutable: objects.parent_role is immutable (no role reparenting)');
end;

-- Seeds three core-role rows: engine (root), cache, user (both children
-- of engine via parent_role, owned by engine via owner_role). All three
-- are role primitives ('r') and pinned. Seeded before the ownership
-- triggers below, so any grandfathering is transparent. [ghi]

-- Engine — root of the core-role tree.
insert into objects (primitive, core_role, persistent)
	values ('r', 'e', 1);

-- Cache — child of engine, owned by engine.
insert into objects (primitive, core_role, parent_role, owner_role, persistent)
	values ('r', 'c',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);

-- User — child of engine, owned by engine.
insert into objects (primitive, core_role, parent_role, owner_role, persistent)
	values ('r', 'u',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);

-- Non-role rows must have owner_role set. Roles ('r') may omit it —
-- the engine seed does. Direct primitive check reads cleaner than
-- the pre-'r' composite test on parent_role + core_role. [ghi]
create trigger objects_owner_role_required_on_non_roles
before insert on objects
when new.primitive != 'r' and new.owner_role is null
begin
	select raise(abort, 'objects_owner_role_required: a non-role must have owner_role set');
end;

-- Every non-root role's parent_role must point at a role. Direct
-- primitive check on the target row — no view subquery. [ghi]
create trigger objects_parent_role_must_be_role
before insert on objects
when new.parent_role is not null
	and (select primitive from objects where object_pk = new.parent_role) is not 'r'
begin
	select raise(abort, 'parent_role_must_be_role: parent_role must reference a role (primitive = ''r'')');
end;

-- parent_role cannot be self. Defense-in-depth with a specific error ID. [ghi]
create trigger objects_parent_role_not_self
before insert on objects
when new.parent_role is not null and new.parent_role = new.object_pk
begin
	select raise(abort, 'objects_parent_role_not_self: parent_role cannot equal object_pk');
end;

-- The engine role is the only role that can be tree-root — every
-- other role (cache, user, and any runtime-added role) must have a
-- parent_role. Locks the "single root" shape of the role tree at
-- INSERT time. [ghi]
create trigger objects_only_engine_can_be_role_root
before insert on objects
when new.primitive = 'r'
	and new.parent_role is null
	and new.core_role is not 'e'
begin
	select raise(abort, 'objects_only_engine_can_be_role_root: only the engine role can have parent_role = null; every other role must have a parent_role');
end;

-- owner_role, if set, must point at a role. Direct primitive check
-- on the target row — no view subquery. [ghi]
create trigger objects_owner_role_must_be_role
before insert on objects
when new.owner_role is not null
	and (select primitive from objects where object_pk = new.owner_role) is not 'r'
begin
	select raise(abort, 'owner_role_must_be_role: owner_role must reference a role (primitive = ''r'')');
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

-- Guards any core-role row. `old.core_role is not null` is sufficient —
-- the cross-column check on core_role means only 'r' rows can have it
-- set, so this WHEN implicitly filters to core-role 'r' rows. [ghi]
create trigger objects_no_delete_root_role
before delete on objects
when old.core_role is not null
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
-- Frame-column indexes.
-- ------------------------------------------------------------

-- Child-of-frame walk: given a frame pk, find its child sub-frame. [ghi]
create index objects_frame_by_parent on objects(parent_frame)
	where primitive = 'f' and parent_frame is not null;


-- ------------------------------------------------------------
-- uspace — derived view of GC anchor set. Cost per check: one
-- indexed lookup per union branch. [ghi]
-- ------------------------------------------------------------

create view uspace as
	-- Every role (root + non-root) — pulled from the roles view.
	-- Roles branch is now a single-column filter on `primitive = 'r'`
	-- via the roles view; the eventual test_view_indexes.lua uspace
	-- plan will show one lookup on this branch, not the historical
	-- UNION-of-two. [ghi]
	select object_pk from roles
	union
	-- Objects flagged persistent. [ghi]
	select object_pk from objects where persistent = 1
	union
	-- Process caps — the top of every live call stack. Frame 0 and
	-- everything below it are reachable via parent_frame from the cap. [ghi]
	select object_pk from objects where primitive = 'f' and process_cap = 1;


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
-- PK on objects). The bucket join uses refs_parent + a primitive
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
	join objects bucket
		on bucket.object_pk = bucket_ref.child
		and bucket.primitive = 'h'
	join refs scopes_ref
		on scopes_ref.parent = bucket.object_pk
		and scopes_ref.key = 'scopes'
	join refs scope_ref
		on scope_ref.parent = scopes_ref.child
	join refs var_ref
		on var_ref.parent = scope_ref.child
where f.primitive = 'f';


-- ------------------------------------------------------------
-- object_bucket — every non-container object with its bucket_pk
-- (or null if it hasn't been given one). "Non-container" = primitive
-- in ('o', 'f'); those are the ones the one-hash-one-array trigger
-- caps, so the correlated subquery returns at most one row and lands
-- safely as a scalar value.
--
-- **No caller yet.** Kept in the schema as a convenience for whoever
-- eventually needs "give me this object's bucket" without hand-writing
-- the refs + objects + primitive-filter join. Usage:
-- `SELECT bucket_pk FROM object_bucket WHERE object_pk = ?`. [ghi]
-- ------------------------------------------------------------
create view object_bucket as
select
	o.object_pk as object_pk,
	(
		select r.child
		from refs r
			join objects h on h.object_pk = r.child and h.primitive = 'h'
		where r.parent = o.object_pk
	) as bucket_pk
from objects o
where o.primitive in ('o', 'f');


-- ------------------------------------------------------------
-- object_stack — every non-container object with its stack_pk
-- (or null if it hasn't been given one). Same shape as object_bucket
-- but filtered to array-children. Same "no caller yet, kept as a
-- convenience" note applies. [ghi]
-- ------------------------------------------------------------
create view object_stack as
select
	o.object_pk as object_pk,
	(
		select r.child
		from refs r
			join objects a on a.object_pk = r.child and a.primitive = 'a'
		where r.parent = o.object_pk
	) as stack_pk
from objects o
where o.primitive in ('o', 'f');
