-- Drinian database design. One `objects` table holds row shapes
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

-- ------------------------------------------------------------
-- Drinian marker table
-- ------------------------------------------------------------
-- The presence of this table signals "this database can be used as
-- Drinian." A generic SQLite file has no `drinian` table; a Drinian
-- database always does. Any Drinian tool can check for this table's
-- existence before treating the file as a Drinian store, and any
-- database that carries it is committing to the Drinian schema.
--
-- Append-only: once a row is inserted, it cannot be updated or
-- deleted. Every entry is a permanent birth-record. If we ever need
-- something mutable, it goes in a different table.

create table drinian (
	key text primary key,
	value text
);

create trigger drinian_no_update
before update on drinian
begin
	select raise(abort, 'drinian_append_only: drinian is append-only; no updates allowed');
end;

create trigger drinian_no_delete
before delete on drinian
begin
	select raise(abort, 'drinian_append_only: drinian is append-only; no deletes allowed');
end;

insert into drinian (key, value) values ('schema', '6.0');

-- ------------------------------------------------------------
-- Sources: source-location registry.
-- ------------------------------------------------------------
-- Per requirements/drinian § Source-location tagging: every value
-- and every frame can carry a back-pointer to where it came from
-- in source. The registry sits here, one row per distinct source.
-- Value rows and frame rows carry a source_pk + line pair pointing
-- back.
--
-- Loose on purpose. `type` is a free-form discriminator (currently
-- expected values include 'file' and 'url', more as they come up)
-- with no schema-enforced enum — new source shapes land without
-- schema change. `path` is free-form text. No UNIQUE, no
-- immutability trigger; duplicates and updates are permitted while
-- we're still working out what wants pinning down. Constraints
-- tighten as the semantics settle.

create table sources (
	source_pk integer primary key autoincrement,
	type text not null,
	path text not null
);

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

	-- Persistent flag. If set (`persistent = 1`), the object is
	-- unconditionally in uspace — GC leaves it alone regardless of
	-- whether anything else anchors it. Null (the default) means
	-- normal reachability rules apply. Freely mutable via
	-- ordinary UPDATE (subject to the CHECK); an object can be
	-- pinned and later unpinned. Provisional shape — see where it
	-- goes.
	persistent integer check (persistent = 1),

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

	-- Row-kind discriminator. NOT NULL, no default: Drinian's write
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
		check (stack_pk  is null or (primitive = 'o' and scalar_type is null)),

	-- Source-location tagging. Per requirements/drinian §
	-- Source-location tagging: a value's src is its birth line.
	-- source_pk names the file / URL in the sources table; line is
	-- the 1-based line number. Both nullable and omitted together
	-- for values with no source line — engine internals,
	-- hand-written CaspM fixtures, truly source-less
	-- metaprogramming output. Both immutable after INSERT: a
	-- value's birth line doesn't change when the value moves
	-- through assignments or calls.
	source_pk integer references sources(source_pk) on delete restrict,
	line integer
		check (line is null or line > 0)
		check ((source_pk is null and line is null) or (source_pk is not null and line is not null)),

	-- AST body (function / method / closure). CaspM tree serialized
	-- as SQLite JSONB — the binary JSON format introduced in SQLite
	-- 3.45.0. JSON1 functions query into it transparently
	-- (json_extract, etc.) without full parse. Null on objects that
	-- aren't callables. Mutable — the engine reads the current
	-- value on each call and thaws it into Lua-native form
	-- attached to the frame, so an update to `ast` takes effect on
	-- the next call (hot-patch / metaprogramming friendly, no
	-- cache-invalidation dance).
	ast blob,

	-- Transient GC scratch. Both are 1 or null — CHECK doesn't
	-- fire on null, so no `X is null or` guard is needed.
	--
	-- needs_trace: 1 means this row is a candidate seed the drain
	-- should trace from. in_trace: positive integer giving the order
	-- the drain's callback loop fires against this row (see
	-- specs/on-gc.md).
	--
	-- No `del` column — the drain deletes objects directly instead
	-- of a mark-then-bulk-delete pattern. If an object still has
	-- incoming references at delete time (e.g., an on_close created
	-- a new one), the RESTRICT FK on relationships.child raises,
	-- and the exception propagates like any other. Loud beats
	-- silent.
	needs_trace integer check (needs_trace = 1),
	in_trace    integer check (in_trace > 0)
);

create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;
-- Role tree: partial index over just the role rows. The uspace
-- view's `where role_parent is not null` branch walks this;
-- role-tree traversal queries (find children of X) use it too.
create index objects_role_parent on objects(role_parent) where role_parent is not null;

-- Immutability rules:
--   Fully immutable from INSERT: object_pk, primitive, scalar_type, scalar_value,
--   bucket_for, stack_for, user, role_parent, source_pk, line.
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
		when new.source_pk is not old.source_pk
			then raise(abort, 'objects_source_pk_immutable: objects.source_pk is immutable')
		when new.line is not old.line
			then raise(abort, 'objects_line_immutable: objects.line is immutable')
		when old.bucket_pk is not null and new.bucket_pk is not old.bucket_pk
			then raise(abort, 'objects_bucket_pk_write_once: objects.bucket_pk is write-once')
		when old.stack_pk is not null and new.stack_pk is not old.stack_pk
			then raise(abort, 'objects_stack_pk_write_once: objects.stack_pk is write-once')
	end;
end;

-- The user row (marked `user = 1`) is the root role and cannot
-- be deleted. Every Drinian database starts with user seeded,
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

-- Seed the root role. User is the root role: primitive = 'h'
-- for now (kept as a HashPrimitive per current design), user =
-- 1 marks it as root, persistent = 1 for consistency (the row
-- persists anyway via `where user`), role_parent = null (root
-- has no parent). Its object_pk is a fresh UUID from the
-- default.
insert into objects (primitive, user, persistent) values ('h', 1, 1);

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

-- Identity is (rel_pk, parent, key). Content — child, idx — is
-- mutable. Swinging child from one object to another is legal; the
-- mark trigger below catches the object-edge-severed case.
create trigger relationships_no_update
before update on relationships
begin
	select case
		when new.rel_pk is not old.rel_pk
			then raise(abort, 'relationships_pk_immutable: relationships.rel_pk is immutable')
		when new.parent is not old.parent
			then raise(abort, 'relationships_parent_immutable: relationships.parent is immutable')
		when new.key is not old.key
			then raise(abort, 'relationships_key_immutable: relationships.key is immutable')
	end;
end;

-- ------------------------------------------------------------
-- Mark triggers — the trace's worklist populator.
-- ------------------------------------------------------------

-- On DELETE of a relationship: mark the old child as needs_trace.
-- No uspace filter — the drain's trace handles uspace membership
-- via the uspace view (uspace rows terminate the trace
-- immediately as alive, a cheap wasted iteration compared to a
-- subquery on every mark-trigger fire).
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- On UPDATE OF child: mark the OLD child when the slot is swung to
-- a different object. `is not` handles null-vs-value correctly in
-- the WHEN clause where `<>` would silently no-op on null.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child is not new.child
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

	broadcaster_pk text not null references objects(object_pk) on delete cascade,
	listener_pk    text not null references objects(object_pk) on delete cascade,

	-- event and method names are inline text, not references to
	-- StringPrimitive objects. Interning is an engine-layer
	-- optimization if it turns out to matter; storage keeps it
	-- simple.
	event_name  text not null,
	method_name text not null,

	-- Idempotent: `.listen_to` called twice with the same combo is
	-- one registration, not two. The Lua write API uses INSERT OR
	-- IGNORE to swallow the collision silently.
	unique (broadcaster_pk, event_name, listener_pk, method_name)
);

-- Dispatch lookup: given a broadcaster + event, find its listeners.
create index instance_listeners_broadcaster on instance_listeners(broadcaster_pk, event_name);

-- Unlisten-all lookup: given a listener, find all its rows.
create index instance_listeners_listener on instance_listeners(listener_pk);

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
-- in Caspian are ordinary objects, so `class_pk` targets `objects`
-- like any other reference. Spec:
-- requirements/events/listen-to-class.

create table class_listeners (
	reg_pk integer primary key autoincrement,

	class_pk    text not null references objects(object_pk) on delete cascade,
	listener_pk text not null references objects(object_pk) on delete cascade,

	event_name  text not null,
	method_name text not null,

	unique (class_pk, event_name, listener_pk, method_name)
);

create index class_listeners_class    on class_listeners(class_pk, event_name);
create index class_listeners_listener on class_listeners(listener_pk);

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
-- execution contexts coexisting in one Drinian file. Cases the
-- plural is ready for:
--   * Coroutines — cooperative yield / resume, each their own stack.
--   * Fork children — engine-granted opt-in concurrency.
--   * Multiple paused processes each waiting for their own resume
--     signal, coexisting in one file.
--   * Multiple concurrent instances of the same machine running
--     over one shared object graph — a real concurrency model
--     within one Drinian, with semantics (row contention,
--     isolation, coordination) to work out but the storage
--     substrate ready.
--
-- No seed row — each engine creates its own processes row on
-- startup and records its pk in current_process. Multi-process
-- features will create additional rows here at runtime.

create table processes (
	process_pk integer primary key autoincrement
);

-- No seed row. Every engine that opens a Drinian file creates
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

	-- Frame kind — the `action` field from requirements/drinian.
	-- Each value maps to a different structural role a frame can
	-- play. Fields below are conditionally meaningful per kind
	-- (documented inline); the engine's write layer enforces the
	-- kind → field discipline. Schema stays loose on cross-kind
	-- CHECK constraints to keep things simple.
	--
	--   top_level          — the outermost frame of a call stack
	--   method_call        — a dispatch into a method
	--   function_call      — a Caspian-source function call
	--   function_invocation — an engine invocation of a callable
	--   block              — a do-block scope
	--   if_block           — an if-body scope
	--   delegate_to        — a %role.delegate_to block (carries delegations)
	--   exception          — an in-flight raised exception
	--   on_close           — an engine-pushed on_close handler
	kind text not null check (kind in (
		'top_level', 'method_call', 'function_call', 'function_invocation',
		'block', 'if_block',
		'delegate_to', 'exception', 'on_close'
	)),

	-- Method dispatch info — meaningful on method_call,
	-- function_call, function_invocation, on_close frames.
	method_pk       text references objects(object_pk),
	method_class_pk text references objects(object_pk),

	-- Lexical parent link — the frame that owned the scope where
	-- THIS frame's code was DEFINED. Variable lookup walks this
	-- chain, not the physical call stack. Differs from the caller
	-- when a function is called from outside its defining scope.
	-- Null on top_level and engine-pushed frames. ON DELETE SET
	-- NULL: if the defining frame is popped and gone, the link
	-- goes stale (an engine-side concern, not a corruption).
	lexical_parent_pk integer references frames(frame_pk) on delete set null,

	-- Iterator state — meaningful on method_call frames for
	-- iteration methods (each, map, etc.). Together record where
	-- the iteration is so a suspended frame can resume from the
	-- right position.
	iterator_position integer check (iterator_position is null or iterator_position >= 0),
	iterator_of       integer
		check (iterator_of is null or iterator_of > 0)
		check ((iterator_position is null and iterator_of is null)
			or (iterator_position is not null and iterator_of is not null)),

	-- Exception details — meaningful on 'exception' frames only.
	-- exception_class_pk points at the exception's class object;
	-- exception_message is human-readable text carried alongside.
	exception_class_pk text references objects(object_pk),
	exception_message  text,

	-- Amber full-walk-stop marker. 1 → this frame called
	-- %amber.clear (or entered a %amber.clear do end block), so
	-- descendants see empty amber until the frame exits. null →
	-- this frame did not clear. See requirements/amber § Clear
	-- with .clear. Namespace-specific hides live in frame_amber
	-- with kind = 'remove'; this flag is the whole-surface stop.
	amber_cleared integer check (amber_cleared is null or amber_cleared = 1),

	-- Source-location for this frame — where in source the frame
	-- currently is. source_pk names the file / URL; line advances
	-- as the frame executes (the one column on `frames` where
	-- mutation is expected during a frame's lifetime).
	source_pk integer references sources(source_pk) on delete restrict,
	line      integer
		check (line is null or line > 0)
		check ((source_pk is null and line is null) or (source_pk is not null and line is not null)),

	-- Composite uniqueness — one frame per (process_pk, idx) slot.
	-- Table-level because it spans two columns; sits here to
	-- satisfy SQLite's grammar (table constraints after column
	-- definitions).
	unique (process_pk, idx)
);

create index frames_process_pk on frames(process_pk);

create table locals (
	-- Local variable bindings for a specific frame. Cascade-deletes
	-- with the frame — locals live and die with their frame.
	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Variable name — inline text (no interning at storage level).
	name text not null,

	-- The object bound to this name. Plain reference: deleting a
	-- frame shouldn't delete objects the frame referenced, since
	-- they may be alive elsewhere.
	value_object_pk text not null references objects(object_pk),

	primary key (frame_pk, name)
);

create index locals_value on locals(value_object_pk);

-- ------------------------------------------------------------
-- Frame delegations — role permission grants.
-- ------------------------------------------------------------
-- A %role.delegate_to(X) do ... end block pushes a frame with
-- kind = 'delegate_to' and one row here per target role receiving
-- the elevation. Permission resolution walks the call stack
-- looking for matching (target_role_pk == current_role_pk)
-- delegations. When the frame pops, the rows cascade with it —
-- the grant is gone without a separate cleanup step.
create table frame_delegations (
	frame_pk       integer not null references frames(frame_pk) on delete cascade,
	target_role_pk text not null references objects(object_pk) on delete cascade,
	primary key (frame_pk, target_role_pk)
);

create index frame_delegations_target_role on frame_delegations(target_role_pk);

-- ------------------------------------------------------------
-- Frame amber — ambient per-frame namespaced context.
-- ------------------------------------------------------------
-- Backs the %amber surface (requirements/amber). Each row is one
-- namespace-specific entry in a frame's amber layer:
--
--   'init'   — frame init'd this namespace; namespace_hash_pk
--              points at the HashPrimitive that IS the namespace.
--              Reads in this frame and its descendants resolve to
--              that hash via the aggregate-hash walk.
--   'remove' — frame hid this namespace from its own view
--              downward (tombstone). Ancestor's namespace is
--              invisible from this frame until it exits.
--   'grant'  — frame granted this namespace across a role-boundary
--              call, with grant_read / grant_write permission
--              flags. Callee in the other role sees the namespace
--              via the grant during a single hop.
--
-- The full-surface walk-stop (%amber.clear) lives as the
-- amber_cleared column on `frames`, not in this table — .clear is
-- a frame-level state, not a namespace-specific entry.
--
-- The engine's amber resolver walks a frame's ancestors: it stops
-- at any frame with amber_cleared = 1, otherwise scans this table
-- for the requested namespace, honoring 'remove' tombstones,
-- 'init' hits, and 'grant' cross-boundary permissions.
--
-- Cascade-deletes with the frame — when the frame that added the
-- entry pops, the entry is gone. Block-form scopes (.init do end,
-- .grant do end) get their own transient frame that carries these
-- entries and pops at block exit.

create table frame_amber (
	entry_pk integer primary key autoincrement,

	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Namespace identifier (domain-shaped per amber spec).
	namespace text not null,

	kind text not null check (kind in ('init', 'remove', 'grant')),

	-- For 'init' entries: the HashPrimitive object that backs this
	-- namespace. Null otherwise.
	namespace_hash_pk text references objects(object_pk),

	-- For 'grant' entries: the read / write permissions the callee
	-- receives across the role boundary. Both are 0 or 1.
	grant_read  integer check (grant_read is null or grant_read in (0, 1)),
	grant_write integer check (grant_write is null or grant_write in (0, 1))
);

create index frame_amber_frame_pk  on frame_amber(frame_pk);
create index frame_amber_namespace on frame_amber(namespace);
create index frame_amber_hash_pk   on frame_amber(namespace_hash_pk) where namespace_hash_pk is not null;

-- Amber namespace hashes are held in uspace by the uspace
-- view (which unions frame_amber.namespace_hash_pk into the
-- membership set). No trigger needed to anchor them; when the
-- frame_amber row cascades away on frame pop, the hash drops out
-- of the view naturally and rejoins the GC candidate pool.

-- ------------------------------------------------------------
-- Captured stack — snapshot-by-reference for exception frames.
-- ------------------------------------------------------------
-- When an exception is raised, the engine snapshots the frames
-- below it into this table by reference (not by copy). The
-- captured references let a debugger or uncaught-error handler
-- see the stack that led to the raise, even after the frames
-- have popped during unwinding. See requirements/drinian §
-- Capture-by-reference for the cost model.
--
-- Cascade behavior: if the exception frame is deleted (exception
-- caught, or the whole call stack collapses), the captures go
-- with it. If a referenced frame is deleted (unwound past),
-- the row goes too — the capture becomes partial rather than
-- broken. That matches "point-in-time snapshot" semantics: what
-- survives is what's still there.
create table captured_frames (
	exception_frame_pk  integer not null references frames(frame_pk) on delete cascade,
	position            integer not null check (position >= 0),
	referenced_frame_pk integer not null references frames(frame_pk) on delete cascade,
	primary key (exception_frame_pk, position)
);

create index captured_frames_referenced on captured_frames(referenced_frame_pk);

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
--   * Held as a variable binding in any frame's locals.
--   * A namespace hash held in any frame's amber layer.
--   * The method being executed by some frame, or that method's
--     defining class.
--   * The exception class of an in-flight exception.
--   * The target of a role delegation on some frame.
--
-- Buckets and stacks are NOT in this list. They live inside their
-- owner via bucket_for / stack_for (ON DELETE CASCADE handles
-- owner-goes-so-bucket-goes at the FK level). Under normal
-- Drinian ops nothing puts a bucket or stack row as a child in
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
	select value_object_pk from locals
	union
	-- Amber namespace hashes referenced from a frame.
	select namespace_hash_pk from frame_amber where namespace_hash_pk is not null
	union
	-- Method being called + defining class, for every live frame.
	select method_pk from frames where method_pk is not null
	union
	select method_class_pk from frames where method_class_pk is not null
	union
	-- Exception class while an exception is in flight.
	select exception_class_pk from frames where exception_class_pk is not null
	union
	-- Roles being granted permissions via delegate_to blocks.
	select target_role_pk from frame_delegations;
