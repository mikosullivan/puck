-- Every connection to a CVM database must run these two pragmas
-- immediately after opening. [ghi]
pragma foreign_keys = on;
pragma recursive_triggers = on;


-- ------------------------------------------------------------
-- Processes — call stack roots.
-- ------------------------------------------------------------

-- Holds the list of currently running processes.

create table processes (
	process_pk text primary key default (
		lower(
			substr(hex(randomblob(4)), 1, 8) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(6)), 1, 12)
		)
	),

	-- Completion flag. 0 = has frames left; 1 = finished. Default 0. [ghi]
	complete integer not null default 0 check (complete in (0, 1)),

	-- Message. Text. The caller reaps this into the return hash after run(). [ghi]
	message text default null
);

-- process_pk is immutable. [ghi]
create trigger processes_no_update
before update on processes
when new.process_pk is not old.process_pk
begin
	select raise(abort, 'processes_pk_immutable: processes.process_pk is immutable');
end;

-- `complete` is one-way: 0 → 1 is allowed, 1 → 0 is not. Once a process
-- is marked complete the caller may reap it at any point; reverting the
-- flag would let a reaped-but-not-yet-deleted process look live again. [ghi]
create trigger processes_complete_no_reverse
before update on processes
when old.complete = 1 and new.complete = 0
begin
	select raise(abort, 'processes_complete_no_reverse: processes.complete cannot go from 1 back to 0');
end;


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
	-- [ghi]
	primitive text not null check (primitive in ('o', 'h', 'a', 'f')),

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
	-- index below. [ghi]
	core_role text check (core_role in ('e', 'c', 'u')),

	-- Role-tree parentage. Non-root roles set this. Immutable via
	-- objects_role_parent_immutable. [ghi]
	role_parent text references objects(object_pk) on delete cascade,

	-- Pointer to the role that created this row. Required for non-role
	-- rows (see objects_owner_role_required_on_non_roles). Roles may
	-- also carry it (cache and user are owned by engine). No cascade. [ghi]
	owner_role text references objects(object_pk),

	-- CaspM tree as JSON text. Set on real frames (primitive='f',
	-- gc null), null on everything else — markers (primitive='f',
	-- gc=1) and non-frames. A marker carries no code; it's a
	-- bookkeeping row that the walker dispatches to the GC routine,
	-- not to ast-walking. Immutable once set (objects_ast_immutable). [ghi]
	ast text
		check (
			(primitive = 'f' and gc is null and ast is not null)
			or
			(ast is null and (primitive != 'f' or gc = 1))
		),

	-- Current position within the frame's ast. Set on real frames
	-- (primitive='f', gc null), null on markers and non-frames.
	-- Parallels the ast column check: a marker has no code and no
	-- position; the walker dispatches it to GC, not to statement
	-- walking. Mutable (walker advances by +1 per statement dispatched). [ghi]
	stmt_idx integer
		check (
			(primitive = 'f' and gc is null and stmt_idx >= 0)
			or
			(stmt_idx is null and (primitive != 'f' or gc = 1))
		),

	-- FK to processes for frame 0 (and any marker that replaced it).
	-- Frame-only. Frames are destroyed when finished — no null-on-pop
	-- transition; the row goes away instead. [ghi]
	process_pk text
		references processes(process_pk)
		check (process_pk is null or primitive = 'f'),

	-- Sub-frame → parent-frame FK. Frame-only. No cascade. Every frame
	-- has exactly one parent — either a parent_frame or a process_pk,
	-- never both, never neither. Enforced by the mutual-exclusion check
	-- on this column. [ghi]
	parent_frame text
		references objects(object_pk)
		check (parent_frame is null or primitive = 'f')
		check (primitive != 'f'
			or (parent_frame is not null and process_pk is null)
			or (parent_frame is null and process_pk is not null)),

	-- Bucket / stack back-refs on collection rows. If set, this row is
	-- the bucket / stack for the referenced full object. At most one
	-- per collection. Cascades on owner delete. [ghi]
	bucket_for text unique references objects(object_pk) on delete cascade
		check (bucket_for is null or primitive = 'h'),
	stack_for  text unique references objects(object_pk) on delete cascade
		check (stack_for  is null or primitive = 'a')
		check (bucket_for is null or stack_for is null),

	-- Owner-side denormalization of bucket_for / stack_for. Set once by
	-- the denormalize triggers below; then immutable via objects_no_update. [ghi]
	bucket_pk text unique
		check (bucket_pk is null or primitive = 'f' or (primitive = 'o' and scalar_type is null)),
	stack_pk  text unique
		check (stack_pk  is null or primitive = 'f' or (primitive = 'o' and scalar_type is null)),

	-- Persistence pin. Rows with `persistent = 1` are kept alive. [ghi]
	persistent integer check (persistent = 1),

	-- GC marker flag. A row with gc = 1 is a marker in the frame stack —
	-- not an actual Caspian call. Frames-only; markers carry no bucket,
	-- no stack. Only 1 or null. [ghi]
	gc integer
		check (gc = 1)
		check (gc is null or primitive = 'f')
		check (gc is null or bucket_pk is null)
		check (gc is null or stack_pk is null),

	-- GC scratch: mark from the drain's retrace pass. Null in the common case. [ghi]
	needs_trace integer check (needs_trace = 1),

	-- GC scratch: callback-order index. Null in the common case. [ghi]
	in_trace integer check (in_trace > 0),

	-- Human-readable label. Informational; no query path reads it. [ghi]
	debug text
);

-- Partial index for reachability queries over pinned rows. [ghi]
create index objects_persistent on objects(persistent) where persistent = 1;

-- Partial indexes for the drain's worklist / callback-order walks. [ghi]
create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;

-- Base immutability for objects. Per-column triggers below handle
-- core_role, role_parent, owner_role, and ast. [ghi]
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
		when new.bucket_for is not old.bucket_for
			then raise(abort, 'objects_bucket_for_immutable: objects.bucket_for is immutable')
		when new.stack_for is not old.stack_for
			then raise(abort, 'objects_stack_for_immutable: objects.stack_for is immutable')
		when old.bucket_pk is not null and new.bucket_pk is not old.bucket_pk
			then raise(abort, 'objects_bucket_pk_write_once: objects.bucket_pk is write-once')
		when old.stack_pk is not null and new.stack_pk is not old.stack_pk
			then raise(abort, 'objects_stack_pk_write_once: objects.stack_pk is write-once')
	end;
end;

-- Bucket / stack are lazily created by the Lua write layer (no auto-provision). [ghi]

-- ------------------------------------------------------------
-- Denormalization triggers — keep owner-side bucket_pk / stack_pk
-- in sync with collection-side bucket_for / stack_for. [ghi]
-- ------------------------------------------------------------

-- On bucket INSERT: write the new bucket's pk into the owner's bucket_pk. [ghi]
create trigger objects_denormalize_bucket
after insert on objects
when new.bucket_for is not null
begin
	update objects set bucket_pk = new.object_pk where object_pk = new.bucket_for;
end;

-- Same for stack. [ghi]
create trigger objects_denormalize_stack
after insert on objects
when new.stack_for is not null
begin
	update objects set stack_pk = new.object_pk where object_pk = new.stack_for;
end;

-- ------------------------------------------------------------
-- Refs: parent-to-child object edges. Parents must be container
-- primitives ('h' or 'a'). [ghi]
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

-- Only container primitives can be parents in refs. [ghi]
create trigger refs_parent_must_be_primitive_container
before insert on refs
when (select primitive from objects where object_pk = new.parent) not in ('h', 'a')
begin
	select raise(abort, 'parent_must_be_primitive_container: only container primitives can be parents');
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
-- Frame ast validation triggers.
-- ------------------------------------------------------------

-- BEFORE INSERT: reject non-array or non-JSON ast on real frame rows.
-- Skipped on markers (gc=1) — markers have ast=null by column-check
-- and this validator would raise on json_valid(null). [ghi]
create trigger objects_ast_valid_insert
before insert on objects
when new.primitive = 'f' and new.gc is null
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

-- A real frame is born with stmt_idx = 0. Only fires for real frames
-- (gc null); markers have stmt_idx = null by column check, so this
-- doesn't apply. Transitional rule, so it's a trigger, not a column
-- CHECK — a bulk-load with triggers off can install a frame at any
-- mid-state stmt_idx. [ghi]
create trigger frames_stmt_idx_starts_at_zero
before insert on objects
when new.primitive = 'f' and new.gc is null and new.stmt_idx is not 0
begin
	select raise(abort, 'frames_stmt_idx_must_start_at_zero: a real frame is born with stmt_idx = 0');
end;

-- stmt_idx moves +1 at a time. Skips and rewinds are rejected. A no-op
-- re-write of the same value is silently accepted — no advance semantics
-- fire (marker-required, marker-delete). WHEN gates on actual change so
-- the advance machinery only runs when something is really moving. [ghi]
create trigger frames_stmt_idx_advances_by_one
before update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx
	and new.stmt_idx is not old.stmt_idx + 1
begin
	select raise(abort, 'frames_stmt_idx_must_advance_by_one: stmt_idx moves +1 at a time');
end;

-- stmt_idx can only advance when the frame has a GC marker child ready
-- to be swept. Fires only on actual change; a no-op re-write is silently
-- accepted (no marker required). [ghi]
create trigger frames_stmt_idx_requires_marker_child
before update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx
	and not exists (
		select 1 from objects
		where parent_frame = new.object_pk and gc = 1
	)
begin
	select raise(abort, 'frames_stmt_idx_requires_marker_child: stmt_idx can only advance when a GC marker child is present to sweep');
end;

-- Advancing a frame's stmt_idx deletes its GC marker child in the same
-- SQL operation. WHEN gates on actual change — a no-op re-write MUST
-- NOT delete a marker (it would be an observable side effect from a
-- write that changed no data). [ghi]
create trigger frames_delete_marker_after_stmt_idx_update
after update of stmt_idx on objects
when new.stmt_idx is not old.stmt_idx
begin
	delete from objects where parent_frame = new.object_pk and gc = 1;
end;

-- `gc` is immutable. A row's marker-vs-real identity is set at INSERT
-- and never changes — flipping it in place would break drop-and-replace
-- (fires only on real-frame deletes) and the "markers have no bucket/
-- stack" invariant. Rejects only on actual change; a no-op re-write of
-- the same value is silently accepted. [ghi]
create trigger objects_gc_immutable
before update of gc on objects
when new.gc is not old.gc
begin
	select raise(abort, 'objects_gc_immutable: objects.gc is immutable');
end;

-- `parent_frame` is immutable. A frame's parent is set at INSERT and
-- never changes — reparenting a live frame would break the "frames are
-- destroyed when finished" invariant. Rejects only on actual change. [ghi]
create trigger objects_parent_frame_immutable
before update of parent_frame on objects
when new.parent_frame is not old.parent_frame
begin
	select raise(abort, 'objects_parent_frame_immutable: objects.parent_frame is immutable');
end;

-- `process_pk` is immutable. A frame 0 (or its replacement marker) is
-- anchored to a specific process at INSERT and never moves. Rejects
-- only on actual change. [ghi]
create trigger objects_process_pk_immutable
before update of process_pk on objects
when new.process_pk is not old.process_pk
begin
	select raise(abort, 'objects_process_pk_immutable: objects.process_pk is immutable');
end;

-- Drop-and-replace. When a non-marker frame is deleted, a GC marker
-- is inserted in its place, inheriting the dropped frame's anchor
-- (parent_frame for a nested frame, process_pk for frame 0) and its
-- owner_role. Markers themselves don't trigger this — their drop is
-- final. AFTER (not BEFORE) DELETE so the outgoing row's slot in the
-- unique-child index is freed before the marker's INSERT takes it. [ghi]
create trigger frames_drop_and_replace
after delete on objects
when old.primitive = 'f' and old.gc is null
begin
	insert into objects
		(primitive, gc, ast, stmt_idx,
		 parent_frame, process_pk, owner_role)
	values
		('f', 1, null, null,
		 old.parent_frame, old.process_pk, old.owner_role);
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

-- Partial index on role_parent for role-tree traversal. [ghi]
create index objects_role_parent on objects(role_parent) where role_parent is not null;

create index objects_owner_role  on objects(owner_role)  where owner_role is not null;


-- ------------------------------------------------------------
-- Roles view — single source of truth for "what is a role."
-- ------------------------------------------------------------
-- Written as UNION rather than `where core_role = 'e' or role_parent
-- is not null` because the OR form defeats index selection — the
-- planner can't split an OR across two indexes. UNION lets each
-- branch use its own partial index. Verified by tests/view-indexes.lua. [ghi]

-- First branch matches only the engine (core_role = 'e', root of the
-- core-role tree). Cache, user, and every runtime-added role reach the
-- view via the second branch (they all have role_parent set). [ghi]
create view roles as
	select object_pk from objects where core_role = 'e'
	union
	select object_pk from objects where role_parent is not null;


-- ------------------------------------------------------------
-- Immutability triggers for the role columns (core_role,
-- role_parent, owner_role). Below the roles view because they
-- reference role concepts. [ghi]
-- ------------------------------------------------------------

-- core_role is set at INSERT and never changes. [ghi]
create trigger objects_core_role_immutable
before update of core_role on objects
when new.core_role is not old.core_role
begin
	select raise(abort, 'objects_core_role_immutable: objects.core_role is immutable');
end;

-- role_parent is set at INSERT and never changes. Load-bearing: this
-- immutability is what makes the role tree cycle-free. [ghi]
create trigger objects_role_parent_immutable
before update of role_parent on objects
when new.role_parent is not old.role_parent
begin
	select raise(abort, 'objects_role_parent_immutable: objects.role_parent is immutable (no role reparenting)');
end;

-- Seeds three core-role rows: engine (root), cache, user (both children
-- of engine via role_parent, owned by engine via owner_role). All three
-- are HashPrimitives and pinned. Seeded before the ownership triggers
-- below, so any grandfathering is transparent. [ghi]

-- Engine — root of the core-role tree.
insert into objects (primitive, core_role, persistent)
	values ('h', 'e', 1);

-- Cache — child of engine, owned by engine.
insert into objects (primitive, core_role, role_parent, owner_role, persistent)
	values ('h', 'c',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);

-- User — child of engine, owned by engine.
insert into objects (primitive, core_role, role_parent, owner_role, persistent)
	values ('h', 'u',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);

-- Roles may carry owner_role (cache and user are owned by engine).
-- Non-role rows must have owner_role set. [ghi]
create trigger objects_owner_role_required_on_non_roles
before insert on objects
begin
	select case
		when new.role_parent is null and new.core_role is null
				and new.owner_role is null
			then raise(abort, 'objects_owner_role_required: a non-role must have owner_role set')
	end;
end;

-- Every non-root role's role_parent must point at an existing role. [ghi]
create trigger objects_role_parent_must_be_role
before insert on objects
when new.role_parent is not null
begin
	select case
		when (select 1 from roles where object_pk = new.role_parent) is null
		then raise(abort, 'role_parent_must_be_role: role_parent must reference a role')
	end;
end;

-- role_parent cannot be self. Defense-in-depth with a specific error ID. [ghi]
create trigger objects_role_parent_not_self
before insert on objects
when new.role_parent is not null and new.role_parent = new.object_pk
begin
	select raise(abort, 'objects_role_parent_not_self: role_parent cannot equal object_pk');
end;

-- owner_role, if set, must point at an existing role. [ghi]
create trigger objects_owner_role_must_be_role
before insert on objects
when new.owner_role is not null
begin
	select case
		when (select 1 from roles where object_pk = new.owner_role) is null
		then raise(abort, 'owner_role_must_be_role: owner_role must reference a role')
	end;
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

-- Guards any core-role row. [ghi]
create trigger objects_no_delete_root_role
before delete on objects
when old.core_role is not null
begin
	select raise(abort, 'root_role_cannot_be_deleted: core-role rows cannot be deleted');
end;

-- Guards any core-role row (symmetric with the delete version). WHEN
-- gates on actual change to any column; a no-op re-write of a core-
-- role row is silently accepted. [ghi]
create trigger objects_no_update_root_role
before update on objects
when old.core_role is not null
	and (
		new.object_pk is not old.object_pk
		or new.primitive is not old.primitive
		or new.scalar_type is not old.scalar_type
		or new.scalar_value is not old.scalar_value
		or new.core_role is not old.core_role
		or new.role_parent is not old.role_parent
		or new.owner_role is not old.owner_role
		or new.ast is not old.ast
		or new.stmt_idx is not old.stmt_idx
		or new.process_pk is not old.process_pk
		or new.parent_frame is not old.parent_frame
		or new.bucket_for is not old.bucket_for
		or new.stack_for is not old.stack_for
		or new.bucket_pk is not old.bucket_pk
		or new.stack_pk is not old.stack_pk
		or new.persistent is not old.persistent
		or new.gc is not old.gc
		or new.needs_trace is not old.needs_trace
		or new.in_trace is not old.in_trace
		or new.debug is not old.debug
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


-- Process is complete when a process-anchored marker drops. Every real
-- frame gets replaced by a marker via drop-and-replace, so the marker
-- is always the last thing standing; firing on marker-drop-with-
-- process_pk is equivalent to "last frame gone" but doesn't have to
-- reason about trigger ordering. `not exists` guard is defense-in-
-- depth against any state that somehow leaves another frame behind. [ghi]
create trigger processes_complete_after_marker_drop
after delete on objects
when old.primitive = 'f' and old.gc = 1 and old.process_pk is not null
	and not exists (
		select 1 from objects
		where process_pk = old.process_pk and primitive = 'f'
	)
begin
	update processes set complete = 1 where process_pk = old.process_pk;
end;


-- ------------------------------------------------------------
-- Frame-column indexes.
-- ------------------------------------------------------------

-- One process-anchored frame per process. Frame 0 carries process_pk;
-- when it drops-and-replaces, the marker inherits that anchor and
-- takes the slot. Sub-frames chain via parent_frame, never
-- process_pk. Parallels objects_one_child_per_frame; together the two
-- indexes enforce "any parent (frame or process) has one child." [ghi]
create unique index objects_one_child_per_process on objects(process_pk)
	where primitive = 'f' and process_pk is not null;

-- Child-of-frame walk: given a frame pk, find its child sub-frame. [ghi]
create index objects_frame_by_parent on objects(parent_frame)
	where primitive = 'f' and parent_frame is not null;


-- ------------------------------------------------------------
-- uspace — derived view of GC anchor set. Cost per check: one
-- indexed lookup per union branch. [ghi]
-- ------------------------------------------------------------

create view uspace as
	-- Every role (root + non-root) — pulled from the roles view. [ghi]
	select object_pk from roles
	union
	-- Objects flagged persistent. [ghi]
	select object_pk from objects where persistent = 1
	union
	-- Frames currently on a process's stack. [ghi]
	select object_pk from objects where primitive = 'f' and process_pk is not null;
