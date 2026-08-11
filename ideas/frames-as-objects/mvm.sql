pragma foreign_keys = on;

-- Recursive triggers are ON. SQLite permits a manual trigger's
-- INSERT / UPDATE / DELETE to fire further manual triggers, and
-- turning OFF just to enforce non-recursion turned out to be more
-- work than the discipline it saved. We accept the setting but
-- treat non-recursion as a design principle: if propagation needs
-- to happen across rows or tables, do it explicitly in Lua rather
-- than lean on trigger chains. FK cascades are a separate mechanism
-- and their after-triggers fire regardless — mark triggers on
-- relationships continue to fire during bulk DELETEs.
pragma recursive_triggers = on;

-- ############################################################################
-- # Mikobase                                                                 #
-- ############################################################################

-- ------------------------------------------------------------
-- current_process: per-connection runtime state (TEMP table).
-- ------------------------------------------------------------
-- Simple key/value store for per-connection process state. TEMP
-- table: created fresh with each connection open, disappears
-- cleanly when the connection closes. Matches "one running
-- process per connection" — pause = close = current_process
-- vanishes; revive = new connection = fresh current_process
-- populated from persistent state in `main`.
--
-- Currently expected keys:
--   'current_process_pk' → integer, the active call stack's process_pk
--
-- More keys land as the engine grows to need them.
--
-- Because this is a TEMP table, the main schema file (run once
-- at DB creation) can't define it — it needs to be created every
-- time a connection opens. Companion setup file or engine-side
-- code applies this DDL:
--
--     create temp table current_process (
--         key text primary key,
--         value
--     );

create table objects (
	-- Primary key is a UUID4-shaped hex string generated at INSERT
	-- time from SQLite's ChaCha20-backed randomblob(). Built
	-- manually (the uuid() extension isn't compiled into stock
	-- SQLite builds); the expression yields a 36-char hyphenated
	-- lowercase string like 'a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5'
	-- — cryptographically random 128 bits with the standard
	-- UUID hyphen positions. See the "Design consideration:
	-- UUIDs as primary keys?" section for the trade-offs
	-- accepted.
	object_pk text primary key default (
		lower(
			substr(hex(randomblob(4)), 1, 8) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(6)), 1, 12)
		)
	),

	-- User marker. Exactly one row across the whole table can
	-- carry `user = 1` (enforced by UNIQUE + CHECK). Every other
	-- row leaves it null. Set at INSERT and immutable — the seed
	-- creates the user row with this set, nothing else ever gets
	-- it. Finding the user row is `select object_pk from objects
	-- where user` (truthy check; only user is non-null so the
	-- UNIQUE index picks it up directly).
	user integer unique check (user = 1),

	-- Role parentage. If set, this row is a role and role_parent
	-- points at its parent role. Null on the root role (user row)
	-- and on every non-role object. Immutable at INSERT — a role
	-- can't be reparented; that's what buys the schema-level
	-- cycle-freeness (a row can only reference a row that already
	-- exists, and no existing row can be repointed at a newer row).
	--
	-- Combined with the FK's `on delete cascade`, this column
	-- gives the role tree its own self-maintaining subsystem:
	-- single parent (one column, one value), cycle-free
	-- (immutability + insert-order), cascade cleanup (parent
	-- delete drops the subtree), and root-safety (the existing
	-- objects_no_delete_root_role trigger keeps user undeletable).
	--
	-- Roles are anchored in uspace via the uspace view's
	-- `where role_parent is not null` branch — the tree's rows
	-- are structurally pinned by the FK, not by general
	-- reachability. Role bucket contents still trace normally.
	--
	-- The schema also enforces "role_parent must point at a row
	-- that is itself a role" via the objects_role_parent_must_be_role
	-- BEFORE INSERT trigger below. INSERT-only (role_parent is
	-- immutable, so once a row is validated as a role at insert
	-- time, it stays a role for its lifetime). One indexed lookup
	-- per role insertion; roles are rare, so cost is negligible.
	role_parent text references objects(object_pk) on delete cascade,

	-- Row-kind discriminator. NOT NULL, no default: MVM's write
	-- code names the row kind at INSERT time. Exactly one of:
	--   'o' → object (full object, or scalar primitive if scalar_type is set)
	--   'h' → HashPrimitive
	--   'a' → ArrayPrimitive
	primitive text not null check (primitive in ('o', 'h', 'a')),

	-- Scalar type. Only meaningful when primitive = 'o'. When set,
	-- this row is a scalar primitive; when null on a primitive =
	-- 'o' row, this row is a plain full object with a bucket +
	-- stack.
	--   's' string, 'n' number, 'b' boolean, 'u' null
	scalar_type text
		check (scalar_type in ('s', 'n', 'b', 'u'))
		check (primitive = 'o' or scalar_type is null),

	-- Scalar value. Meaningful only when `scalar_type` is set.
	-- Declared `blob` for no-affinity storage — SQLite doesn't
	-- coerce values in blob-affinity columns, so integers, reals,
	-- text, and null land in the row as their native type. The
	-- per-scalar-type shape checks below enforce the actual
	-- type-per-scalar_type rule. Checks use `is` (not `in`) so
	-- null cleanly evaluates to false — the `in` form would give
	-- NULL which SQLite's CHECK accepts as passing, silently
	-- letting null booleans through.
	scalar_value blob
		check (scalar_type is null or scalar_type != 'b' or scalar_value is 0 or scalar_value is 1)
		check (scalar_type is null or scalar_type != 'u' or scalar_value is null)
		check (scalar_type is null or scalar_type != 'n' or typeof(scalar_value) in ('integer', 'real'))
		check (scalar_type is null or scalar_type != 's' or typeof(scalar_value) = 'text')
		check (scalar_type is not null or scalar_value is null),

	-- Role back-references. If bucket_for is set, this row is the
	-- bucket of the referenced full object; it must be a
	-- HashPrimitive. If stack_for is set, this row is the stack of
	-- the referenced full object; it must be an ArrayPrimitive. At
	-- most one may be set (a row can't be both a bucket and a
	-- stack). Full objects, scalars, and standalone container
	-- primitives (root, internal storage) leave both null.
	--
	-- FKs use ON DELETE CASCADE: deleting the owner deletes its
	-- bucket and stack in one shot via FK, no trigger required.
	--
	-- UNIQUE on each column: each owner has at most one bucket and
	-- one stack. SQLite doesn't consider nulls in UNIQUE
	-- constraints, so many rows with these columns null don't
	-- collide.
	bucket_for text unique references objects(object_pk) on delete cascade
		check (bucket_for is null or primitive = 'h'),
	stack_for  text unique references objects(object_pk) on delete cascade
		check (stack_for  is null or primitive = 'a')
		check (bucket_for is null or stack_for is null),

	-- Denormalized owner-side back-links to the bucket and stack.
	-- Redundant with the bucket_for / stack_for columns on the
	-- collection rows (looking up a bucket via bucket_for is already
	-- indexed), but having the link directly on the owner row lets
	-- queries and dispatch paths skip a join. Nullable — plain full
	-- objects that don't yet have their bucket / stack lazily
	-- created leave these null.
	--
	-- Set-once by the objects_denormalize_bucket / _stack triggers
	-- when the corresponding collection is inserted; immutable
	-- afterward via objects_no_update. No FK — the trigger keeps
	-- the denormalization in sync, and adding FK cascade in the
	-- reverse direction of bucket_for would fight the cascade we
	-- already have.
	--
	-- CHECK: only plain full objects (primitive = 'o' AND scalar_type null)
	-- can carry these columns.
	-- UNIQUE: no two owners share a bucket or stack — redundant with
	-- the bucket_for / stack_for UNIQUE, but a good safety net for
	-- the denormalization.
	bucket_pk integer unique
		check (bucket_pk is null or (primitive = 'o' and scalar_type is null)),
	stack_pk  integer unique
		check (stack_pk  is null or (primitive = 'o' and scalar_type is null))
);

-- Role tree: partial index over just the role rows. The uspace
-- view's `where role_parent is not null` branch walks this;
-- role-tree traversal queries (find children of X) use it too.
create index objects_role_parent on objects(role_parent) where role_parent is not null;

-- Immutability rules:
--   Fully immutable from INSERT: object_pk, primitive, scalar_type, scalar_value,
--   bucket_for, stack_for, user, role_parent.
--   Write-once (null → value, then locked): bucket_pk, stack_pk.
--   Freely mutable: persistent, GC scratch (needs_trace, in_trace).
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
		when new.user is not old.user
			then raise(abort, 'objects_user_immutable: objects.user is immutable')
		when new.role_parent is not old.role_parent
			then raise(abort, 'objects_role_parent_immutable: objects.role_parent is immutable (no role reparenting)')
		when old.bucket_pk is not null and new.bucket_pk is not old.bucket_pk
			then raise(abort, 'objects_bucket_pk_write_once: objects.bucket_pk is write-once')
		when old.stack_pk is not null and new.stack_pk is not old.stack_pk
			then raise(abort, 'objects_stack_pk_write_once: objects.stack_pk is write-once')
	end;
end;

-- The user row (marked `user = 1`) is the root role and cannot
-- be deleted. Every MVM database starts with user seeded,
-- and nothing above the language layer can remove it. Non-root
-- uspace anchors are freely deletable (that's how an object
-- leaves user space in the first place). The role tree is
-- expressed as bucket contents rooted at user; the tree's
-- integrity is engine-side code, not schema-level enforcement.
create trigger objects_no_delete_root_role
before delete on objects
when old.user
begin
	select raise(abort, 'root_role_cannot_be_deleted: the user row cannot be deleted');
end;

-- Every non-root role must name a parent that is itself a role.
-- "Is a role" = has user = 1 (root) OR has role_parent set
-- (non-root). BEFORE INSERT only — role_parent is immutable via
-- objects_no_update, so a row's role-ness is determined at insert
-- time and can't be silently stripped afterward. The WHEN clause
-- skips inserts with role_parent null (the common case). When it
-- does fire, one indexed lookup by pk verifies the target row.
create trigger objects_role_parent_must_be_role
before insert on objects
when new.role_parent is not null
begin
	select case
		when (
			select 1 from objects
			where object_pk = new.role_parent
				and (user = 1 or role_parent is not null)
		) is null
		then raise(abort, 'role_parent_must_be_role: role_parent must reference a row that is itself a role (root user row or a row with role_parent set)')
	end;
end;

-- A role cannot be its own parent. The must_be_role trigger above
-- already blocks this indirectly at INSERT — the referenced row
-- doesn't exist yet, so the SELECT for "is this a role" returns
-- nothing. But an explicit self-reference check is defense-in-depth
-- with a specific error ID for the diagnostic, and guards against
-- any future path that would allow the target row to be present at
-- check time (e.g., a bulk insert where the row lands first).
--
-- INSERT-only: role_parent is immutable via objects_no_update, so
-- the not-self invariant is set at creation and can't be broken.
create trigger objects_role_parent_not_self
before insert on objects
when new.role_parent is not null and new.role_parent = new.object_pk
begin
	select raise(abort, 'objects_role_parent_not_self: role_parent cannot equal object_pk (a role cannot be its own parent)');
end;

-- Deletion callback machinery (on_close / on_delete UDF hook)
-- deferred. When the engine needs to invoke Caspian-level cleanup
-- on object delete, a trigger + UDF will land here.

-- Role tree lives in the `role_parent` column. A row IS a role
-- iff it has role_parent set (non-root) or user = 1 (root). The
-- schema enforces:
--   Single parent — one column, one value.
--   Cycle-free — role_parent is immutable and INSERT requires
--     the target row to exist, so cycles are structurally
--     impossible.
--   Cascade cleanup — FK on delete cascade drops the subtree.
--   Root safety — objects_no_delete_root_role keeps user
--     undeletable.
--   Parent-is-a-role — objects_role_parent_must_be_role rejects
--     any insert whose role_parent points at a non-role row.
-- What the schema does NOT check: naming, uniqueness of role
-- names, class-ownership rules — all Lua.
--
-- Roles still live in the object graph as ordinary rows with
-- their own bucket and stack. role_parent is an additional
-- pointer, not a replacement for bucket/stack — it's what makes
-- role lifetime independent of bucket-graph reachability.

-- ------------------------------------------------------------
-- Bucket + stack: lazily created by the Lua write layer.
-- ------------------------------------------------------------
-- Neither bucket nor stack is auto-provisioned by trigger. The Lua
-- write API creates them on demand via ensure_bucket(obj_pk) and
-- ensure_stack(obj_pk) — the first field write creates the bucket,
-- the first class-extension or shadow creates the stack. Objects
-- that live briefly and touch neither save the row + constraint
-- cost entirely.

-- ------------------------------------------------------------
-- Denormalization triggers — keep owner-side bucket_pk / stack_pk
-- in sync with collection-side bucket_for / stack_for.
-- ------------------------------------------------------------

-- When a bucket is inserted (HashPrimitive with bucket_for set),
-- write the new bucket's object_pk into the owner's bucket_pk. The
-- owner's bucket_pk was null; this null→value transition is
-- allowed by objects_no_update, and after it lands the field is
-- locked.
create trigger objects_denormalize_bucket
after insert on objects
when new.bucket_for is not null
begin
	update objects set bucket_pk = new.object_pk where object_pk = new.bucket_for;
end;

-- Same for stack.
create trigger objects_denormalize_stack
after insert on objects
when new.stack_for is not null
begin
	update objects set stack_pk = new.object_pk where object_pk = new.stack_for;
end;

-- ------------------------------------------------------------
-- Relationships: parent-to-child object edges.
-- ------------------------------------------------------------
-- Every row is an object-to-object edge. The parent must be a
-- container primitive ('h' or 'a') — full objects and scalars
-- cannot be parents. Enforced by trigger below.

create table relationships (
	rel_pk  integer primary key autoincrement,

	parent  text not null references objects(object_pk) on delete cascade,
	-- child uses ON DELETE RESTRICT so deleting an object with
	-- incoming references raises rather than silently nulling those
	-- references. Loud beats silent. If the trace was accurate and
	-- an object is unreferenced, the RESTRICT check passes; if
	-- something (typically an on_close-created edge) added a new
	-- incoming reference between mark and sweep, the delete raises
	-- and the exception propagates to whatever transaction wraps
	-- the operation.
	child   text not null references objects(object_pk) on delete restrict,

	-- Hash-style entries store a text `key`. Array-style entries
	-- leave key null and use idx as position. Class-level dispatch
	-- (HashPrimitive vs ArrayPrimitive) interprets which is which;
	-- storage does not care.
	key     text,

	-- idx is required for every row: array-style entries use it as
	-- position, hash-style entries use it as insertion order for
	-- iteration.
	idx     integer not null check (idx >= 0),

	-- No two relationships from the same parent share a key or idx.
	-- Null-key rows (array-style) don't collide on the (parent, key)
	-- constraint because SQLite doesn't consider nulls in UNIQUE
	-- constraints.
	unique (parent, key),
	unique (parent, idx)
);

create index relationships_parent on relationships(parent);
create index relationships_child  on relationships(child);

-- Only container primitives ('h' or 'a') can be parents. Full
-- objects (primitive = 'o') and scalar primitives cannot appear
-- as parent — they don't have references. Full objects route
-- through their bucket / stack.
create trigger relationships_parent_must_be_primitive_container
before insert on relationships
when (select primitive from objects where object_pk = new.parent) not in ('h', 'a')
begin
	select raise(abort, 'parent_must_be_primitive_container: only HashPrimitives and ArrayPrimitives can be parents in relationships');
end;

-- All identity + content columns are immutable. Rebinding an edge
-- (swinging child from one object to another, moving to a different
-- key, whatever) is expressed as delete + insert, not in-place update.
-- Immutability means the mark trigger only needs to fire on DELETE —
-- there's no in-place UPDATE OF child to cover.
create trigger relationships_no_update
before update on relationships
begin
	select case
		when new.rel_pk is not old.rel_pk
			then raise(abort, 'relationships_pk_immutable: relationships.rel_pk is immutable')
		when new.parent is not old.parent
			then raise(abort, 'relationships_parent_immutable: relationships.parent is immutable')
		when new.child is not old.child
			then raise(abort, 'relationships_child_immutable: relationships.child is immutable')
		when new.key is not old.key
			then raise(abort, 'relationships_key_immutable: relationships.key is immutable')
		when new.idx is not old.idx
			then raise(abort, 'relationships_idx_immutable: relationships.idx is immutable')
	end;
end;

-- ############################################################################
-- MVM
-- ############################################################################

-- MVM database design. One `objects` table holds row shapes
-- discriminated by the `primitive` column:
--   'h' → HashPrimitive (hash-shaped primitive container)
--   'a' → ArrayPrimitive (array-shaped primitive container)
--   'o' → object. Either a plain full object (with bucket + stack
--         reachable via bucket_for / stack_for on separate rows)
--         or a scalar primitive (with a scalar type in `scalar_type` and
--         value in `scalar_value`).
--
-- A HashPrimitive serving as a bucket carries `bucket_for` pointing
-- at its owner; an ArrayPrimitive serving as a stack carries
-- `stack_for`. Standard SQL "child references parent" idiom — ON
-- DELETE CASCADE from the owner cleans up bucket + stack via FK; no
-- cleanup trigger needed.
--
-- Only container primitives can be parents in the `relationships`
-- table. Full objects hold their contents in their bucket + stack;
-- scalars have no contents at all.

-- ------------------------------------------------------------
-- MVM's additions to the Mikobase `objects` table.
-- ------------------------------------------------------------
-- The base `objects` table is defined in the Mikobase section
-- above. MVM layers on the columns it needs by ALTER TABLE:
--
--   persistent  — pin flag for the uspace view (see below). If
--                 set, the object is unconditionally in uspace
--                 regardless of any other anchoring. Nullable and
--                 freely mutable — an object can be pinned and
--                 later unpinned.
--
--   ast         — CaspM tree for callables (function / method /
--                 closure), serialized as JSON text. Null on
--                 non-callables. Mutable — the engine reads the
--                 current value on each call and thaws it into
--                 Lua-native form attached to the frame, so an
--                 update takes effect on the next call (hot-patch
--                 / metaprogramming friendly). See the "AST storage:
--                 JSON, not JSONB" design note in requirements/mvm/
--                 for the rationale.
--
--   needs_trace — GC scratch: 1 means this row is a candidate the
--                 drain should trace from. Null in the common case.
--   in_trace    — GC scratch: positive integer giving the order
--                 the drain's callback loop fires against this row.
--                 Null in the common case. Both are 1-or-null / >0-
--                 or-null; CHECK doesn't fire on null so no `is
--                 null or` guard is needed.

alter table objects add column persistent integer
	check (persistent = 1);

alter table objects add column ast text;

alter table objects add column needs_trace integer
	check (needs_trace = 1);

alter table objects add column in_trace integer
	check (in_trace > 0);

-- Ownership. Every non-role object carries owner_role pointing at the
-- role that created it. The rule is XOR with role_parent: a row is
-- EITHER a role (role_parent set — the role tree case) OR owned by
-- one (owner_role set — every other object) — never both, never
-- neither, except the grandfathered user seed inserted just below
-- (BEFORE the enforcement triggers exist, so its role_parent = null,
-- owner_role = null state is preserved).
--
-- No `on delete cascade`: role deletion doesn't take its owned objects
-- with it. Deletion of a role that still owns things is a load-bearing
-- event and should be either restricted or explicitly handled by the
-- engine; the FK stays plain until that policy is spec'd.
alter table objects add column owner_role text references objects(object_pk);

create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;
create index objects_owner_role  on objects(owner_role)  where owner_role is not null;

-- Seed the root role. User is the root role: primitive = 'h'
-- (a HashPrimitive per current design), user = 1 marks it as root,
-- persistent = 1 for consistency (the row persists anyway via
-- `where user`), role_parent = null (root has no parent),
-- owner_role = null (grandfathered — this seed exists before the
-- ownership triggers below are created, so nothing checks it).
-- Its object_pk is a fresh UUID from the default.
insert into objects (primitive, user, persistent) values ('h', 1, 1);

-- ownership triggers — created AFTER the seed so the user row is
-- grandfathered. Every non-seed insert into objects must have
-- exactly one of role_parent / owner_role set.

-- XOR rule: a role cannot have an owner, and a non-role must have one.
-- "Is a role" uses the same definition as elsewhere in this schema:
-- `role_parent is not null OR user = 1`. Rows attempting to set
-- user = 1 are treated as roles for this check (the UNIQUE constraint
-- separately enforces "at most one user row").
create trigger objects_role_or_owner_role
before insert on objects
begin
	select case
		when (new.role_parent is not null or new.user = 1)
				and new.owner_role is not null
			then raise(abort, 'objects_role_or_owner_role: a role cannot have owner_role — roles have role_parent, other objects have owner_role, never both')
		when new.role_parent is null and new.user is null
				and new.owner_role is null
			then raise(abort, 'objects_role_or_owner_role: a non-role must have owner_role set — every non-role object must reference the role that created it')
	end;
end;

-- owner_role, when set, must reference an actual role (a row with
-- user = 1 or with role_parent set). Same shape as the existing
-- objects_role_parent_must_be_role trigger. INSERT-only — owner_role
-- is immutable at INSERT via the trigger below, so a row's owner
-- can't be silently repointed at a non-role after the fact.
create trigger objects_owner_role_must_be_role
before insert on objects
when new.owner_role is not null
begin
	select case
		when (
			select 1 from objects
			where object_pk = new.owner_role
				and (user = 1 or role_parent is not null)
		) is null
		then raise(abort, 'owner_role_must_be_role: owner_role must reference a row that is itself a role (root user row or a row with role_parent set)')
	end;
end;

-- owner_role is immutable at INSERT — no reparenting an object between
-- roles at runtime. Matches how role_parent is immutable via the
-- objects_no_update trigger; owner_role gets its own guard here
-- because that trigger lives in the Mikobase section (before this
-- column existed) and MVM layers additions on top.
create trigger objects_owner_role_immutable
before update of owner_role on objects
when new.owner_role is not old.owner_role
begin
	select raise(abort, 'objects_owner_role_immutable: owner_role is immutable (no reparenting an object to a different role)');
end;

-- An object cannot be its own owner. Same class of check as
-- objects_role_parent_not_self above; explicit defense-in-depth with
-- a specific error ID, and structurally: an object owning itself
-- would be a cycle in the ownership graph.
create trigger objects_owner_role_not_self
before insert on objects
when new.owner_role is not null and new.owner_role = new.object_pk
begin
	select raise(abort, 'objects_owner_role_not_self: owner_role cannot equal object_pk (an object cannot be its own owner)');
end;


-- ------------------------------------------------------------
-- MVM marker table
-- The presence of this table signals "this database can be used as
-- MVM." A generic SQLite file has no `mvm` table; a MVM
-- database always does. Any MVM tool can check for this table's
-- existence before treating the file as a MVM store, and any
-- database that carries it is committing to the MVM schema.
--
-- Append-only: once a row is inserted, it cannot be updated or
-- deleted. Every entry is a permanent birth-record. If we ever need
-- something mutable, it goes in a different table.
--
create table mvm (
	key text primary key,
	value text
);

create trigger mvm_no_update
before update on mvm
begin
	select raise(abort, 'mvm_append_only: mvm is append-only; no updates allowed');
end;

create trigger mvm_no_delete
before delete on mvm
begin
	select raise(abort, 'mvm_append_only: mvm is append-only; no deletes allowed');
end;

insert into mvm (key, value) values ('schema', '9.0');
---
-- MVM marker table
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- Mark triggers — the trace's worklist populator.
-- ------------------------------------------------------------

-- [set-needs-trace] On DELETE of a relationship: mark the old child.
-- No uspace filter — the drain's trace handles uspace membership
-- via the uspace view (uspace rows terminate the trace immediately
-- as alive, a cheap wasted iteration compared to a subquery on
-- every mark-trigger fire).
--
-- No corresponding UPDATE trigger — relationships.child is immutable
-- (see relationships_no_update). Rebinding an edge is expressed as
-- delete + insert; the delete fires this trigger.
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- ------------------------------------------------------------
-- Instance-level event listeners.
-- ------------------------------------------------------------
-- A listener registers to be called when a specific broadcaster
-- emits a specific event. Spec: requirements/events/index.
--
-- Registrations are bookkeeping, not graph edges — they live
-- outside `relationships` so GC does NOT count them as reachability.
-- Weak-ref lifetime falls out of ON DELETE CASCADE: when either
-- party's `objects` row is deleted (typically because GC decided it
-- was unreachable), the registration cascade-deletes.

create table instance_listeners (
	reg_pk integer primary key autoincrement,

	broadcaster text not null references objects(object_pk) on delete cascade,
	listener    text not null references objects(object_pk) on delete cascade,

	-- event and method names are inline text, not references to
	-- StringPrimitive objects. Interning is an engine-layer
	-- optimization if it turns out to matter; storage keeps it
	-- simple.
	event_name  text not null,
	method_name text not null,

	-- Idempotent: `.listen_to` called twice with the same combo is
	-- one registration, not two. The Lua write API uses INSERT OR
	-- IGNORE to swallow the collision silently.
	unique (broadcaster, event_name, listener, method_name)
);

-- Dispatch lookup: given a broadcaster + event, find its listeners.
create index instance_listeners_broadcaster on instance_listeners(broadcaster, event_name);

-- Unlisten-all lookup: given a listener, find all its rows.
create index instance_listeners_listener on instance_listeners(listener);

-- Registrations are add-or-remove-only. Every field is immutable
-- after INSERT; to change a registration, DELETE and INSERT.
create trigger instance_listeners_no_update
before update on instance_listeners
begin
	select raise(abort, 'instance_listeners_no_update: instance_listeners rows are immutable; delete and re-insert to change');
end;

-- ------------------------------------------------------------
-- Class-level event listeners.
-- ------------------------------------------------------------
-- Same shape as instance_listeners but keyed by class rather than a
-- specific broadcaster instance. When any instance of the class
-- (or a descendant, via the engine's ancestor-chain walk)
-- broadcasts the event, dispatch fires this registration. Classes
-- in Caspian are ordinary objects, so `class` targets `objects`
-- like any other reference. Spec:
-- requirements/events/listen-to-class.

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
	select raise(abort, 'class_listeners_no_update: class_listeners rows are immutable; delete and re-insert to change');
end;

-- ------------------------------------------------------------
-- Call stacks, frames, and local bindings.
-- ------------------------------------------------------------
-- Runtime execution state lives in dedicated tables outside
-- `objects`. Frames aren't user-visible objects (no class dispatch,
-- no bucket, no stack-of-platters) — they're highly structured
-- engine bookkeeping and get a purpose-built shape.
--
-- `processes` is plural: the schema accommodates multiple
-- execution contexts coexisting in one MVM file. Cases the
-- plural is ready for:
--   * Coroutines — cooperative yield / resume, each their own stack.
--   * Fork children — engine-granted opt-in concurrency.
--   * Multiple paused processes each waiting for their own resume
--     signal, coexisting in one file.
--   * Multiple concurrent instances of the same machine running
--     over one shared object graph — a real concurrency model
--     within one MVM, with semantics (row contention,
--     isolation, coordination) to work out but the storage
--     substrate ready.
--
-- No seed row — each engine creates its own processes row on
-- startup and records its pk in current_process. Multi-process
-- features will create additional rows here at runtime.

create table processes (
	process_pk integer primary key autoincrement
);

-- processes rows are immutable — once a process is created its
-- process_pk is fixed for the row's lifetime. Ending a process is
-- a DELETE, not an UPDATE.
create trigger processes_no_update
before update on processes
begin
	select raise(abort, 'processes_no_update: processes rows are immutable');
end;

-- No seed row. Every engine that opens a MVM file creates
-- its own row here at startup and records the pk in
-- current_process; on the very first run against a fresh DB
-- that pk will be 1 (autoincrement), but nothing pins it — a
-- reviving process picks up the pk from persistent state or
-- allocates a fresh one as appropriate.

create table frames (
	frame_pk integer primary key autoincrement,

	-- Which call stack this frame belongs to.
	process_pk integer not null references processes(process_pk) on delete cascade,

	-- Position within process_pk's stack. Top = MAX(idx) for that process_pk.
	-- Non-negative; strictly monotonic per process_pk (push assigns
	-- idx = MAX(idx)+1; pop removes the MAX row). Composite
	-- uniqueness on (process_pk, idx) is declared at the end of
	-- this table — SQLite's grammar requires table-level
	-- constraints after all column definitions.
	idx integer not null check (idx >= 0),

	-- Frame type. Deliberately narrow — this is a fundamental part
	-- of the runtime and each new value is a real design decision
	-- that changes what frames the engine has to reason about. Start
	-- with the one we're sure about (function_call, which covers
	-- source-level calls, method dispatch, closure invocation, and
	-- engine-invoked callables per CaspianJ § function_call) and
	-- add more values as concrete needs arise. Every addition goes
	-- through deliberate review; no ad-hoc extensions.
	--
	--   function_call — the invocation of a callable
	type text not null check (type in ('function_call')),

	-- ast — the CaspM tree this frame is currently executing,
	-- as JSON text (see requirements/mvm/ast-storage for the JSON /
	-- JSONB rationale). Copied into the frame at push time from
	-- whatever produced it — objects.ast for a call to a named
	-- callable, an if-atom's `action` subtree for a block invocation,
	-- the outer script's ast for frame 0.
	--
	-- The frame owns its ast: once copied, the frame's execution is
	-- independent of the source it came from. A callable object can
	-- be mutated or deleted without disturbing frames currently
	-- executing an earlier snapshot of its code. This carries the
	-- storage cost of ast duplication across live frames (see
	-- ast-storage for the size discussion); accepted for the
	-- semantic simplicity.
	ast text,

	-- Lexical parent link — the frame that owned the scope where
	-- THIS frame's code was DEFINED. Variable lookup walks this
	-- chain, not the physical call stack. Differs from the caller
	-- when a function is called from outside its defining scope.
	-- Null on top_level and engine-pushed frames. ON DELETE SET
	-- NULL: if the defining frame is popped and gone, the link
	-- goes stale (an engine-side concern, not a corruption).
	lexical_parent integer references frames(frame_pk) on delete set null,

	-- Loop / iteration state — deferred. Loops aren't designed yet
	-- (we haven't even gotten a script to frame 0), so nothing in
	-- the schema tracks iterator position or length. Whatever fields
	-- resumable iteration ends up needing get added when the loop
	-- design lands.

	-- Amber full-walk-stop marker. 1 → this frame called
	-- %amber.clear (or entered a %amber.clear do end block), so
	-- descendants see empty amber until the frame exits. null →
	-- this frame did not clear. See requirements/amber § Clear
	-- with .clear. Domain-specific hides live as tombstone rows in
	-- frame_ambers; this flag is the whole-surface stop.
	amber_cleared integer check (amber_cleared is null or amber_cleared = 1),

	-- Composite uniqueness — one frame per (process_pk, idx) slot.
	-- Table-level because it spans two columns; sits here to
	-- satisfy SQLite's grammar (table constraints after column
	-- definitions).
	unique (process_pk, idx)
);

-- Accelerates process-scoped queries: the FK cascade path
-- (deleting a `processes` row drops its frames) and every "all
-- frames for this process" walk (stack traversal, top-of-stack
-- lookup, pause serialization). Note: the `unique (process_pk,
-- idx)` above indexes process_pk as its leftmost column, so this
-- standalone index may be redundant for planning — kept as an
-- explicit declaration of the FK-cascade path until we've measured
-- whether the composite alone is enough.
create index frames_process_pk on frames(process_pk);

-- No mark-on-delete or mark-on-update triggers on frames itself —
-- with `method` gone (replaced by `ast` text), frames no longer carry
-- FK references to objects. Frame pop cascades frame_locals /
-- frame_delegations / frame_ambers automatically, and those cascades
-- fire their own mark triggers on the objects they reference.

create table frame_locals (
	-- Local variable bindings for a specific frame. Cascade-deletes
	-- with the frame — bindings live and die with their frame.
	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Variable name — inline text (no interning at storage level).
	name text not null,

	-- The object bound to this name. Plain reference: deleting a
	-- frame shouldn't delete objects the frame referenced, since
	-- they may be alive elsewhere.
	value_object text not null references objects(object_pk),

	primary key (frame_pk, name)
);

create index frame_locals_value on frame_locals(value_object);

-- [set-needs-trace] On DELETE of a frame_locals row (frame pop cascade
-- or explicit unbind): mark the object the local was pointing at.
create trigger frame_locals_mark_needs_trace_after_delete
after delete on frame_locals
begin
	update objects set needs_trace = 1 where object_pk = old.value_object;
end;

-- [set-needs-trace] On UPDATE OF value_object (variable rebinding
-- like `$foo = something_else`): mark the OLD target.
create trigger frame_locals_mark_needs_trace_after_update
after update of value_object on frame_locals
when old.value_object is not new.value_object
begin
	update objects set needs_trace = 1 where object_pk = old.value_object;
end;

-- ------------------------------------------------------------
-- Frame delegations — role permission grants.
-- ------------------------------------------------------------
-- A %role.delegate_to(X) do ... end block pushes a frame with
-- kind = 'delegate_to' and one row here per target role receiving
-- the elevation. Permission resolution walks the call stack
-- looking for matching (target_role == current_role_pk)
-- delegations. When the frame pops, the rows cascade with it —
-- the grant is gone without a separate cleanup step.
create table frame_delegations (
	frame_pk       integer not null references frames(frame_pk) on delete cascade,
	target_role text not null references objects(object_pk) on delete cascade,
	primary key (frame_pk, target_role)
);

create index frame_delegations_target_role on frame_delegations(target_role);

-- [set-needs-trace] On DELETE of a frame_delegations row (frame pop
-- cascade): mark the target role.
create trigger frame_delegations_mark_needs_trace_after_delete
after delete on frame_delegations
begin
	update objects set needs_trace = 1 where object_pk = old.target_role;
end;

-- [set-needs-trace] On UPDATE OF target_role: mark the OLD target.
-- In current use frame_delegations rows aren't rebound (the row is
-- inserted at delegate_to entry and cascades on frame pop), but the
-- trigger covers any future path that would repoint a row.
create trigger frame_delegations_mark_needs_trace_after_update
after update of target_role on frame_delegations
when old.target_role is not new.target_role
begin
	update objects set needs_trace = 1 where object_pk = old.target_role;
end;

-- ------------------------------------------------------------
-- Frame ambers — the frame-to-amber-instance bridge.
-- ------------------------------------------------------------
-- Each frame can hold any number of amber instances (each of which
-- is what the amber spec calls a "domain"). Every instance is a
-- regular row in `objects` — nothing amber-specific about its
-- shape; it's just a HashPrimitive holding whatever amber content
-- the developer put there. The instances don't carry their own
-- domain names — the name lives in this bridge as the key,
-- allowing the same instance to appear under different names in
-- different frames if the engine ever wants that.
--
-- One row per (frame_pk, domain) — a frame's amber for a given
-- domain is either present (this row exists) or not (no row).
-- Init/remove/grant semantics live above this level in the Lua
-- write layer; from the schema's perspective, this is a plain
-- keyed reference from frames to amber-instance objects.
--
-- The engine's amber resolver walks the frame stack in Lua,
-- consulting frame_ambers for the requested domain at each frame,
-- honoring `frames.amber_cleared` as the walk-stop and stopping
-- at role boundaries absent an explicit grant (grant mechanics
-- TBD; also Lua-side).
create table frame_ambers (
	frame_pk integer not null references frames(frame_pk) on delete cascade,
	domain text not null,
	amber text not null references objects(object_pk),
	primary key (frame_pk, domain)
);

create index frame_ambers_amber on frame_ambers(amber);

-- [set-needs-trace] On DELETE of a frame_ambers row (frame pop
-- cascade or explicit removal): mark the amber instance the row
-- pointed at.
create trigger frame_ambers_mark_needs_trace_after_delete
after delete on frame_ambers
begin
	update objects set needs_trace = 1 where object_pk = old.amber;
end;

-- [set-needs-trace] On UPDATE OF amber: mark the OLD instance.
create trigger frame_ambers_mark_needs_trace_after_update
after update of amber on frame_ambers
when old.amber is not new.amber
begin
	update objects set needs_trace = 1 where object_pk = old.amber;
end;

-- ------------------------------------------------------------
-- uspace — derived view of GC anchor set.
-- ------------------------------------------------------------
-- Membership in "uspace" is computed dynamically from actual
-- anchoring rather than stored as a column. Uspace is GLOBAL: an
-- object is in uspace if it's anchored by ANY frame in ANY
-- process. Under the shared-object-graph model, references from
-- any process count — GC sweeps only objects that no process
-- anchors.
--
-- An object is in uspace when it's:
--
--   * The root role (user, pk = 1).
--   * Held as a variable binding in any frame's frame_locals.
--   * A domain hash held in any frame's amber layer.
--   * The target of a role delegation on some frame.
--
-- Buckets and stacks are NOT in this list. They live inside their
-- owner via bucket_for / stack_for (ON DELETE CASCADE handles
-- owner-goes-so-bucket-goes at the FK level). Under normal
-- MVM ops nothing puts a bucket or stack row as a child in
-- the relationships table, so mark triggers never fire on them —
-- they never become GC candidates.
--
-- Roles (children of user in the role tree) aren't a special
-- case — they're regular objects reachable via relationships from
-- user's bucket → 'children' array → child roles. Standard trace
-- reaches them from user (which IS in uspace).
--
-- The listener registration tables (instance_listeners,
-- class_listeners) are deliberately NOT in the union — their FK
-- cascade is documented as weak-ref lifetime, so a listener
-- registration is not enough to keep either party alive.
--
-- Cost per check: one indexed lookup per union branch. Anchor
-- tables have small row counts in typical programs; the UNION is
-- cheap in practice.

create view uspace as
	-- Root role (the user row) is intrinsically uspace.
	select object_pk from objects where user
	union
	-- Objects flagged persistent — pinned regardless of other anchors.
	select object_pk from objects where persistent
	union
	-- Role tree: every non-root role. Combined with the `where user`
	-- branch above (which picks up the root), this covers every
	-- role. Uses the objects_role_parent partial index.
	select object_pk from objects where role_parent is not null
	union
	-- Frame variable bindings.
	select value_object from frame_locals
	union
	-- Amber instances (domains) referenced from a frame via the
	-- frame_ambers bridge. Each row's amber is one instance.
	select amber from frame_ambers
	union
	-- Roles being granted permissions via delegate_to blocks.
	select target_role from frame_delegations;
