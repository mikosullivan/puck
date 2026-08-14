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


-- ------------------------------------------------------------
-- Objects.
-- ------------------------------------------------------------

-- **code change**
-- Every column that used to be added via ALTER TABLE now lives directly
-- in this CREATE TABLE. The old Mikobase-vs-CVM split earned less than
-- it cost; one CVM story reads simpler.
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

	-- CaspM tree as JSON text. Biconditional with primitive='f'.
	-- Immutable once set (objects_ast_immutable). [ghi]
	ast text
		check ((primitive = 'f' and ast is not null)
			or (primitive != 'f' and ast is null)),

	-- Current position within the frame's ast. Frame-only. Mutable. [ghi]
	stmt_idx integer
		check (stmt_idx is null or (stmt_idx >= 0 and primitive = 'f')),

	-- FK to processes for frame 0. Set on push, nulled on pop. Sub-frames
	-- leave this null and use frame_parent instead. Frame-only. [ghi]
	process_pk text
		references processes(process_pk)
		check (process_pk is null or primitive = 'f'),

	-- Sub-frame → parent-frame FK. Frame-only. No cascade. [ghi]
	frame_parent text
		references objects(object_pk)
		check (frame_parent is null or primitive = 'f'),

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

-- refs rows are immutable; rebind is delete + insert. [ghi]
create trigger refs_no_update
before update on refs
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

-- BEFORE INSERT: reject non-array or non-JSON ast on frame rows. [ghi]
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

-- Advancing a frame's stmt_idx clears any child frames it pushed —
-- atomic at the SQL layer, no Lua-side savepoint needed. [ghi]
create trigger frames_delete_children_after_stmt_idx_update
after update of stmt_idx on objects
when new.primitive = 'f'
begin
	delete from objects where frame_parent = new.object_pk and primitive = 'f';
end;


-- ------------------------------------------------------------
-- Indexes for the role / ownership / frame columns.
-- ------------------------------------------------------------

-- **code change**
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

-- **code change**
-- First branch matches only the engine (core_role = 'e', root of the
-- core-role tree). Cache, user, and every runtime-added role reach the
-- view via the second branch (they all have role_parent set).
create view roles as
	select object_pk from objects where core_role = 'e'
	union
	select object_pk from objects where role_parent is not null;


-- ------------------------------------------------------------
-- Immutability triggers for the role columns (core_role,
-- role_parent, owner_role). Below the roles view because they
-- reference role concepts. [ghi]
-- ------------------------------------------------------------

-- **code change**
-- Renamed from `objects_user_immutable`. Core-role is set at INSERT
-- and never changes.
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

-- **code change**
-- Seeds three core-role rows: engine (root), cache, user (both children
-- of engine via role_parent, and owned by engine via owner_role). All
-- three are HashPrimitives and pinned. Seeded before the ownership
-- triggers below, so any grandfathering is transparent.

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

-- **code change**
-- XOR clause dropped. Roles CAN also carry owner_role (cache and user
-- do). Remaining rule: non-role rows must have owner_role set.
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

-- **code change**
-- Guards ANY core-role row (engine, cache, user) — not just the user seed.
create trigger objects_no_delete_root_role
before delete on objects
when old.core_role is not null
begin
	select raise(abort, 'root_role_cannot_be_deleted: core-role rows cannot be deleted');
end;

-- **code change**
-- Same guard scope as the delete version — any core-role row.
create trigger objects_no_update_root_role
before update on objects
when old.core_role is not null
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

-- Registrations are immutable; change = delete + insert. [ghi]
create trigger instance_listeners_no_update
before update on instance_listeners
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
begin
	select raise(abort, 'class_listeners_no_update: rows are immutable');
end;


-- When frame 0 of a process is deleted, flip processes.complete = 1.
-- Bundles mark-complete + delete-frame into one atomic SQL operation. [ghi]
create trigger processes_complete_after_frame_0_delete
after delete on objects
when old.primitive = 'f' and old.process_pk is not null
begin
	update processes set complete = 1 where process_pk = old.process_pk;
end;


-- ------------------------------------------------------------
-- Frame-column indexes.
-- ------------------------------------------------------------

-- Frames currently on a stack. Only frame 0 carries process_pk;
-- sub-frames chain via frame_parent. [ghi]
create index objects_frame_on_stack on objects(process_pk)
	where primitive = 'f' and process_pk is not null;

-- Child-of-frame walk: given a frame pk, find its child sub-frame. [ghi]
create index objects_frame_by_parent on objects(frame_parent)
	where primitive = 'f' and frame_parent is not null;


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
