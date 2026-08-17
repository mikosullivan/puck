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
	-- UUID4-shaped hex string via SQLite's randomblob(). [ghi]
	object_pk text primary key default (
		lower(
			substr(hex(randomblob(4)), 1, 8) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(6)), 1, 12)
		)
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
	-- frame has an ast, no non-frame does. A cap frame (process=1) has
	-- ast='[]' — the cap doesn't dispatch anything, its "one slot" is
	-- just a lifecycle position (0=live, 1=terminal). Immutable once
	-- set (see objects_ast_immutable). [ghi]
	ast text
		check ((primitive = 'f' and ast is not null)
			or (primitive != 'f' and ast is null))
		check (process is null or ast = '[]'),

	-- Current position within the frame's ast. Set on frames, null on
	-- non-frames. Under the gc cycle, stmt_idx increments by 1 per
	-- statement dispatched, in the SAME UPDATE that sets gc=1. [ghi]
	stmt_idx integer
		check (stmt_idx is null or (stmt_idx >= 0 and primitive = 'f')),

	-- Root-of-process flag. `process = 1` marks this frame as the top
	-- cap of a call stack — the object identity of the process itself.
	-- Null on nested frames (which have parent_frame set instead).
	-- A cap has ast='[]' (see check below), starts at stmt_idx=0, and
	-- becomes terminal when it reaches stmt_idx=1 with gc=null and no
	-- children. Frame 0 sits under the cap as a nested frame. Immutable
	-- via objects_process_immutable. [ghi]
	process integer
		check (process = 1)
		check (process is null or primitive = 'f'),

	-- Sub-frame → parent-frame FK. Frame-only. No cascade. Every frame
	-- has exactly one anchor: either parent_frame (nested frame) or
	-- process=1 (the cap), never both, never neither. Enforced by the
	-- mutual-exclusion check on this column. [ghi]
	parent_frame text
		references objects(object_pk)
		check (parent_frame is null or primitive = 'f')
		check (primitive != 'f'
			or (parent_frame is not null and process is null)
			or (parent_frame is null and process is 1)),

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
	--   * Combined with objects_no_update_root_role's persistent guard,
	--     core roles are pinned at INSERT and can never be unpinned. [ghi]
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

	-- GC scratch: mark from the drain's retrace pass. Null in the common case. [ghi]
	needs_trace integer check (needs_trace = 1),

	-- GC scratch: callback-order index. Null in the common case. [ghi]
	in_trace integer check (in_trace > 0),

	-- Human-readable label. Informational; no query path reads it. [ghi]
	debug text
);

-- Partial index for reachability queries over pinned rows. [ghi]
create index objects_persistent on objects(persistent) where persistent = 1;

-- Cap frames — the `uspace` view's process-anchor branch selects
-- `process = 1`; partial index keeps it empty of nulls so the branch
-- doesn't fall back to a full objects scan. [ghi]
create index objects_process on objects(process) where process = 1;

-- Partial indexes for the drain's worklist / callback-order walks. [ghi]
create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;

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

	-- Position for arrays; insertion order for hashes. [ghi]
	idx     integer not null check (idx >= 0),

	-- Human-readable label. Informational. [ghi]
	debug text,

	-- No two refs from the same parent share a key or idx. [ghi]
	unique (parent, key),
	unique (parent, idx)
);

create index refs_parent on refs(parent);
create index refs_child  on refs(child);

-- Role rows ('r') cannot be a ref parent. Roles don't carry state —
-- nothing hangs off them. If role features grow later (permissions,
-- config, etc.), that's a separate slice with its own rules. [ghi]
create trigger refs_role_cannot_be_parent
before insert on refs
when (select primitive from objects where object_pk = new.parent) = 'r'
begin
	select raise(abort, 'refs_role_cannot_be_parent: role rows cannot be ref parents (roles do not carry state)');
end;

-- Non-container parents ('o', 'f') can hold at most one HashPrimitive
-- child (which serves as its bucket) and at most one ArrayPrimitive
-- child (which serves as its stack). Container parents ('h', 'a') have
-- no such cap — they hold as many children as they want by their
-- native semantics. Owner-owns-bucket / owner-owns-stack is just a
-- normal refs row now; the whole "ownership" story lives in this one
-- table. [ghi]
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

-- refs rows are immutable; rebind is delete + insert. WHEN gates on
-- any actual column change; a no-op re-write of the same row is
-- silently accepted. [ghi]
create trigger refs_no_update
before update on refs
when new.ref_pk is not old.ref_pk
	or new.parent is not old.parent
	or new.child is not old.child
	or new.key is not old.key
	or new.idx is not old.idx
	or new.debug is not old.debug
begin
	select raise(abort, 'refs_immutable: refs rows are immutable');
end;

-- On refs DELETE: mark the old child for retrace. [ghi]
create trigger refs_mark_needs_trace_after_delete
after delete on refs
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- Hash keys must be Caspian-compliant identifiers — start with a
-- letter or underscore, then only letters, digits, or underscores.
-- Rejects malformed strings, punctuation, whitespace, and keys that
-- lead with a digit. Only applies to hash entries; array entries
-- (key is null) are unaffected. [ghi]
create trigger refs_hash_key_must_be_identifier
before insert on refs
when new.key is not null
	and (select primitive from objects where object_pk = new.parent) = 'h'
	and (
		substr(new.key, 1, 1) not glob '[a-zA-Z_]'
		or new.key glob '*[^a-zA-Z0-9_]*'
	)
begin
	select raise(abort, 'refs_hash_key_must_be_identifier: hash keys must match [a-zA-Z_][a-zA-Z0-9_]*');
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

-- Invariant 1a: advancing stmt_idx requires gc = 1 in same UPDATE. [ghi]
create trigger frames_advance_requires_gc
before update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx and new.gc is not 1
begin
	select raise(abort, 'frames_advance_requires_gc: advancing stmt_idx requires gc=1 in the same UPDATE');
end;

-- Invariant 1b: setting gc=1 requires stmt_idx to advance in same UPDATE. [ghi]
create trigger frames_gc_set_requires_advance
before update of gc on objects
when new.gc = 1 and old.gc is null and new.stmt_idx is old.stmt_idx
begin
	select raise(abort, 'frames_gc_set_requires_advance: setting gc=1 requires stmt_idx to advance in the same UPDATE');
end;

-- Invariant 2: setting gc=1 cascade-deletes children. [ghi]
create trigger frames_gc_set_deletes_children
after update of gc on objects
when new.gc = 1 and old.gc is null
begin
	delete from objects where parent_frame = new.object_pk and primitive = 'f';
end;

-- Invariant 3: a child frame can only be deleted when its parent's
-- gc = 1. The BEFORE-DELETE trigger checks the parent at delete time;
-- since the cascade from invariant 2 fires AFTER the parent's gc was
-- set to 1, the check passes for legitimate sweep. Direct DELETE
-- attempts (parent still gc=null) abort. [ghi]
create trigger frames_child_delete_requires_parent_gc
before delete on objects
when old.primitive = 'f'
	and old.parent_frame is not null
	and (select gc from objects where object_pk = old.parent_frame) is not 1
begin
	select raise(abort, 'frames_child_delete_requires_parent_gc: a child frame can only be deleted when parent.gc = 1');
end;

-- A frame can only be deleted when its own gc cycle is complete
-- (gc is null). Rejects mid-cleanup deletes. Does NOT require the
-- frame to be past its last statement — early return via `return X`
-- is a legitimate delete at any stmt_idx. Cascade-swept markers pass
-- because they're born gc=null; frames finishing normally pass because
-- their own advance-then-reset cycle ends with gc=null. [ghi]
create trigger frames_delete_requires_gc_null
before delete on objects
when old.primitive = 'f' and old.gc is not null
begin
	select raise(abort, 'frames_delete_requires_gc_null: a frame can only be deleted when its gc cycle is complete (gc is null); mid-cleanup deletes are rejected');
end;

-- Invariant 4: resetting gc = null requires no child frames. Engine's
-- `UPDATE frame SET gc = null` at the end of a cleanup phase only
-- succeeds when all children (including any on_close callback frames)
-- have run to completion and been swept. Guarantees at-rest gc=null
-- always means "ready for next dispatch." [ghi]
create trigger frames_gc_reset_requires_no_children
before update of gc on objects
when new.gc is null and old.gc = 1
	and exists (
		select 1 from objects
		where parent_frame = new.object_pk and primitive = 'f'
	)
begin
	select raise(abort, 'frames_gc_reset_requires_no_children: cannot reset gc to null while child frames exist');
end;


-- `parent_frame` is immutable. A frame's parent is set at INSERT and
-- never changes. Rejects only on actual change. [ghi]
create trigger objects_parent_frame_immutable
before update of parent_frame on objects
when new.parent_frame is not old.parent_frame
begin
	select raise(abort, 'objects_parent_frame_immutable: objects.parent_frame is immutable');
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

-- `process` is immutable. A frame's identity as a cap (or not) is
-- fixed at INSERT and never changes. Rejects only on actual change. [ghi]
create trigger objects_process_immutable
before update of process on objects
when new.process is not old.process
begin
	select raise(abort, 'objects_process_immutable: objects.process is immutable');
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

-- Guards any core-role row (symmetric with the delete version). WHEN
-- gates on actual change to any GUARDED column; a no-op re-write of a
-- core-role row is silently accepted. `needs_trace` and `in_trace` are
-- GC-scratch columns and are freely writable on core roles too —
-- otherwise deleting a ref whose child is a core role would fail (the
-- ref-delete trigger marks the child needs_trace=1 and would hit this
-- guard). [ghi]
create trigger objects_no_update_root_role
before update on objects
when old.core_role is not null
	and (
		new.object_pk is not old.object_pk
		or new.primitive is not old.primitive
		or new.scalar_type is not old.scalar_type
		or new.scalar_value is not old.scalar_value
		or new.core_role is not old.core_role
		or new.parent_role is not old.parent_role
		or new.owner_role is not old.owner_role
		or new.ast is not old.ast
		or new.stmt_idx is not old.stmt_idx
		or new.process is not old.process
		or new.parent_frame is not old.parent_frame
		or new.persistent is not old.persistent
		or new.gc is not old.gc
	)
begin
	select raise(abort, 'root_role_cannot_be_updated: core-role rows cannot be updated');
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
	select object_pk from objects where primitive = 'f' and process = 1;


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
