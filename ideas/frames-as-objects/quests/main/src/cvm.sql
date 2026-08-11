-- Every connection to a CVM database must run these two pragmas
-- immediately after opening. Both are per-connection settings in
-- SQLite (default OFF, not persisted with the DB file) — the pragmas
-- below only take effect on the connection that applies the schema.
-- Every subsequent connection opens with both OFF and has to enable
-- them again, or the CVM's FK constraints and trigger design are
-- dead letters at runtime.
--
-- Any tool opening a CVM file — the engine, the sqlite3 CLI, another
-- host reading the file — runs these two pragmas as its first act.
-- See src/engine/cvm.lua for the reference implementation:
-- mvm.open() sets both with specific error ids
-- (cvm_pragma_fk_failed, cvm_pragma_recursive_triggers_failed) on
-- failure. Any CVM tool without an equivalent pair of pragma calls
-- is broken by construction. [ghi]
pragma foreign_keys = on;

-- Recursive triggers are ON. SQLite permits a manual trigger's
-- INSERT / UPDATE / DELETE to fire further manual triggers, and
-- turning OFF just to enforce non-recursion turned out to be more
-- work than the discipline it saved. We accept the setting but
-- treat non-recursion as a design principle: if propagation needs
-- to happen across rows or tables, do it explicitly in Lua rather
-- than lean on trigger chains. FK cascades are a separate mechanism
-- and their after-triggers fire regardless — mark triggers on
-- refs continue to fire during bulk DELETEs. [ghi]
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
--  [ghi]

create table objects (
	-- Primary key is a UUID4-shaped hex string generated at INSERT
	-- time from SQLite's ChaCha20-backed randomblob(). Built
	-- manually (the uuid() extension isn't compiled into stock
	-- SQLite builds); the expression yields a 36-char hyphenated
	-- lowercase string like 'a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5'
	-- — cryptographically random 128 bits with the standard
	-- UUID hyphen positions. See the "Design consideration:
	-- UUIDs as primary keys?" section for the trade-offs
	-- accepted. [ghi]
	object_pk text primary key default (
		lower(
			substr(hex(randomblob(4)), 1, 8) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(6)), 1, 12)
		)
	),

	-- Persistence pin. Rows with `persistent = 1` are kept alive by
	-- whatever reachability system the host layers on top; CVM's
	-- uspace view unconditionally includes them, and any future host
	-- with its own uspace-equivalent should honor the same flag.
	-- Nullable and freely mutable — a row can be pinned and later
	-- unpinned. CHECK restricts the value to 1 (truthy) or null; the
	-- partial index below only holds the pinned rows, so lookups over
	-- pinned objects touch just the entries that matter. [ghi]
	persistent integer check (persistent = 1),
	
	-- Row-kind discriminator. NOT NULL, no default: CVM's write
	-- code names the row kind at INSERT time. Exactly one of:
	--   'o' → object (full object, or scalar primitive if scalar_type is set)
	--   'h' → HashPrimitive
	--   'a' → ArrayPrimitive
	-- [ghi]
	primitive text not null check (primitive in ('o', 'h', 'a')),

	-- Scalar type. Only meaningful when primitive = 'o'. When set,
	-- this row is a scalar primitive; when null on a primitive =
	-- 'o' row, this row is a plain full object with a bucket +
	-- stack.
	--   's' string, 'n' number, 'b' boolean, 'u' null
	-- [ghi]
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
	-- [ghi]
	scalar_value blob
		-- Booleans ('b'): value must be exactly 0 (false) or 1 (true).
		-- No other integers, no reals, no strings. `is` (not `=`)
		-- avoids null-value quirks. [ghi]
		check (scalar_type is null or scalar_type != 'b' or scalar_value is 0 or scalar_value is 1)
		-- Nulls ('u'): value must itself be SQL null. A scalar-null
		-- object exists as a row; its "value" isn't stored as
		-- anything, it's null-in-the-database. [ghi]
		check (scalar_type is null or scalar_type != 'u' or scalar_value is null)
		-- Numbers ('n'): value must be a SQLite integer or real. Both
		-- flavors count as "number" at the Caspian level; the runtime
		-- distinguishes as needed via typeof(scalar_value). [ghi]
		check (scalar_type is null or scalar_type != 'n' or typeof(scalar_value) in ('integer', 'real'))
		-- Strings ('s'): value must be SQLite text. No blobs disguised
		-- as strings, no numeric values that happen to stringify. [ghi]
		check (scalar_type is null or scalar_type != 's' or typeof(scalar_value) = 'text')
		-- Non-scalars: if scalar_type is null (this row isn't a scalar
		-- at all), scalar_value must also be null. Prevents leftover
		-- values on non-scalar rows. [ghi]
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
	-- collide. [ghi]
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
	-- the denormalization. [ghi]
	bucket_pk integer unique
		check (bucket_pk is null or (primitive = 'o' and scalar_type is null)),
	stack_pk  integer unique
		check (stack_pk  is null or (primitive = 'o' and scalar_type is null)),

	-- GC scratch: 1 means this row is a candidate the drain should
	-- trace from. Null in the common case. Hosts that layer a
	-- garbage-collection pass on top of Mikobase set this to mark
	-- rows for retracing; CVM's mark trigger writes it after
	-- relationship deletes. 1-or-null; CHECK doesn't fire on null so
	-- no `is null or` guard is needed. [ghi]
	needs_trace integer check (needs_trace = 1),

	-- GC scratch: positive integer giving the order the drain's
	-- callback loop fires against this row. Null in the common case.
	-- Written by the host's GC pass; CVM stamps it inside the drain
	-- to sequence callbacks. >0-or-null; CHECK doesn't fire on null
	-- so no `is null or` guard is needed. [ghi]
	in_trace integer check (in_trace > 0),

	-- Human-readable label for the row. Populated by the engine
	-- (or by hand during debugging) so a state snapshot self-describes
	-- what each row is meant to be. Purely informational — no query
	-- path reads it. Permanent feature of the schema. Rendered as
	-- "comment" in walkthrough tables for readability. See the
	-- ideas/frames-as-objects/quests/debug-columns page for the
	-- design rationale and promotion coordination rule. [ghi]
	debug text
);

-- Partial index over just the pinned rows. Reachability queries
-- like uspace's `where persistent = 1` branch hit this directly. [ghi]
create index objects_persistent on objects(persistent) where persistent = 1;

-- Partial indexes over the GC-scratch columns. The drain's worklist
-- walks needs_trace; the callback-order pass walks in_trace. Both
-- are almost always empty at rest — the partial predicate keeps the
-- indexes tiny. [ghi]
create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;

-- Immutability rules:
--   Fully immutable from INSERT: object_pk, primitive, scalar_type,
--     scalar_value, bucket_for, stack_for.
--   Write-once (null → value, then locked): bucket_pk, stack_pk.
--   Freely mutable: persistent, needs_trace, in_trace.
-- CVM adds more columns (user, role_parent, ast, owner_role) with
-- their own immutability / mutability rules; CVM installs its own
-- triggers over there. [ghi]
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

-- Deletion callback machinery (on_close / on_delete UDF hook)
-- deferred. When the engine needs to invoke Caspian-level cleanup
-- on object delete, a trigger + UDF will land here. [ghi]

-- ------------------------------------------------------------
-- Bucket + stack: lazily created by the Lua write layer.
-- ------------------------------------------------------------
-- Neither bucket nor stack is auto-provisioned by trigger. The Lua
-- write API creates them on demand via ensure_bucket(obj_pk) and
-- ensure_stack(obj_pk) — the first field write creates the bucket,
-- the first class-extension or shadow creates the stack. Objects
-- that live briefly and touch neither save the row + constraint
-- cost entirely. [ghi]

-- ------------------------------------------------------------
-- Denormalization triggers — keep owner-side bucket_pk / stack_pk
-- in sync with collection-side bucket_for / stack_for. [ghi]
-- ------------------------------------------------------------

-- When a bucket is inserted (HashPrimitive with bucket_for set),
-- write the new bucket's object_pk into the owner's bucket_pk. The
-- owner's bucket_pk was null; this null→value transition is
-- allowed by objects_no_update, and after it lands the field is
-- locked. [ghi]
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
-- Relationships: parent-to-child object edges.
-- ------------------------------------------------------------
-- Every row is an object-to-object edge. The parent must be a
-- container primitive ('h' or 'a') — full objects and scalars
-- cannot be parents. Enforced by trigger below. [ghi]

create table refs (
	ref_pk  integer primary key autoincrement,

	parent  text not null references objects(object_pk) on delete cascade,
	-- child uses ON DELETE RESTRICT so deleting an object with
	-- incoming references raises rather than silently nulling those
	-- references. Loud beats silent. If the trace was accurate and
	-- an object is unreferenced, the RESTRICT check passes; if
	-- something (typically an on_close-created edge) added a new
	-- incoming reference between mark and sweep, the delete raises
	-- and the exception propagates to whatever transaction wraps
	-- the operation. [ghi]
	child   text not null references objects(object_pk) on delete restrict,

	-- Hash-style entries store a text `key`. Array-style entries
	-- leave key null and use idx as position. Class-level dispatch
	-- (HashPrimitive vs ArrayPrimitive) interprets which is which;
	-- storage does not care. [ghi]
	key     text,

	-- idx is required for every row: array-style entries use it as
	-- position, hash-style entries use it as insertion order for
	-- iteration. [ghi]
	idx     integer not null check (idx >= 0),

	-- Human-readable label for the row. Populated by the engine
	-- (or by hand during debugging) so a state snapshot self-describes
	-- what each relationship is meant to be. Purely informational —
	-- no query path reads it. Permanent feature of the schema.
	-- Rendered as "comment" in walkthrough tables for readability.
	-- Same treatment as objects.debug — see the
	-- ideas/frames-as-objects/quests/debug-columns page for the
	-- design rationale and promotion coordination rule. [ghi]
	debug text,

	-- No two refs from the same parent share a key or idx.
	-- Null-key rows (array-style) don't collide on the (parent, key)
	-- constraint because SQLite doesn't consider nulls in UNIQUE
	-- constraints. [ghi]
	unique (parent, key),
	unique (parent, idx)
);

create index refs_parent on refs(parent);
create index refs_child  on refs(child);

-- Only container primitives ('h' or 'a') can be parents. Full
-- objects (primitive = 'o') and scalar primitives cannot appear
-- as parent — they don't have references. Full objects route
-- through their bucket / stack. [ghi]
create trigger refs_parent_must_be_primitive_container
before insert on refs
when (select primitive from objects where object_pk = new.parent) not in ('h', 'a')
begin
	select raise(abort, 'parent_must_be_primitive_container: only HashPrimitives and ArrayPrimitives can be parents in refs');
end;

-- The whole refs row is immutable. Rebinding an edge
-- (swinging child from one object to another, moving to a different
-- key, whatever) is expressed as delete + insert, not in-place
-- update. Immutability means the mark trigger only needs to fire on
-- DELETE — there's no in-place UPDATE OF child to cover. [ghi]
create trigger refs_no_update
before update on refs
begin
	select raise(abort, 'refs_immutable: refs rows are immutable');
end;

-- ------------------------------------------------------------
-- Mark trigger — the trace's worklist populator. [ghi]
-- ------------------------------------------------------------

-- [set-needs-trace] On DELETE of a relationship: mark the old child.
-- Hosts that layer a garbage-collection pass on top of Mikobase read
-- objects.needs_trace to find rows to retrace after edge deletion;
-- this trigger keeps that scratch column populated as edges churn.
-- Hosts without a GC pass ignore the column — the write is cheap and
-- the partial objects_needs_trace index stays empty of consequence.
--
-- No filter on which parent-side space the row belongs to — the host's
-- drain decides membership (CVM's uspace view, another host's
-- equivalent). Terminating the trace on an alive row is a cheaper
-- wasted iteration than gating every mark-trigger fire on a subquery.
--
-- No corresponding UPDATE trigger — refs.child is immutable
-- (see refs_no_update). Rebinding an edge is expressed as
-- delete + insert; the delete fires this trigger. [ghi]
create trigger refs_mark_needs_trace_after_delete
after delete on refs
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- ############################################################################
-- CVM
-- ############################################################################

-- CVM database design. One `objects` table holds row shapes
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
-- Only container primitives can be parents in the `refs`
-- table. Full objects hold their contents in their bucket + stack;
-- scalars have no contents at all. [ghi]

-- ------------------------------------------------------------
-- CVM's additions to the Mikobase `objects` table.
-- ------------------------------------------------------------
-- The base `objects` table is defined in the Mikobase section
-- above. CVM layers on the columns it needs by ALTER TABLE;
-- each column's rationale sits with the statement below.

-- user: root-role marker. Exactly one row across the whole table
-- carries `user = 1`; every other row leaves it null. Set at INSERT
-- and immutable via objects_user_immutable below. The seed insert
-- further down creates the user row. Enforcement of "at most one"
-- is a partial unique index (inline UNIQUE isn't available on ALTER
-- TABLE ADD COLUMN in SQLite). [ghi]
alter table objects add column user integer
	check (user = 1);

-- role_parent: role-tree parentage. If set, this row is a non-root
-- role and role_parent points at its parent role. Null on the root
-- role (user row) and on every non-role object. Immutable via
-- objects_role_parent_immutable below — a role can't be reparented;
-- that's what buys the schema-level cycle-freeness (a row can only
-- reference a row that already exists, and no existing row can be
-- repointed at a newer row). [ghi]
alter table objects add column role_parent text
	references objects(object_pk) on delete cascade;

-- ast: CaspM tree for callables (function / method / closure),
-- serialized as JSON text. Null on non-callables. Mutable — the
-- engine reads the current value on each call and thaws it into
-- Lua-native form attached to the frame, so an update takes effect
-- on the next call (hot-patch / metaprogramming friendly). See the
-- "AST storage: JSON, not JSONB" design note in requirements/cvm/
-- for the rationale. [ghi]
alter table objects add column ast text;

-- lexical_parent: the enclosing scope for closures and their
-- invocation frames. On a closure-object: points at the frame
-- (objects row) the closure was defined in — that's what the
-- closure captured. On an invocation frame pushed from a closure
-- call: points at the closure's captured frame, so variable lookup
-- for names not in the frame's own bucket walks the chain up. On
-- non-scope-carrying rows (plain objects, frame 0, non-closure
-- function frames): null.
--
-- This is the field that makes closures work under frames-as-objects.
-- Because a closure holds an ordinary object-graph reference to its
-- captured frame, GC keeps that frame alive as long as the closure
-- does. When the defining function returns and its frame is popped
-- off the call stack, the frame ROW stays in the objects table —
-- unreachable from `processes`, but reachable from the closure,
-- and that's what ordinary reachability wants. See the closure
-- walkthrough at ideas/frames-as-objects/examples/closure/ for the
-- table snapshots that make this concrete.
--
-- Immutable at INSERT for a given row — the captured scope is set
-- at creation and never rebound. [ghi]
alter table objects add column lexical_parent text references objects(object_pk);

-- stmt_idx: current position within the row's `ast`. Frame-objects
-- use this to track which top-level statement they're about to
-- dispatch — 0 at push, incremented after each dispatch, back to
-- null (or unused) after the frame finishes. Non-frame objects
-- leave it null. Mutable — advances during execution. Non-negative
-- integer; null passes the CHECK unmarked.
--
-- Bookkeeping like this used to live in the frame's bucket as a
-- scalar entry hung off a refs row. Promoting stmt_idx
-- to a column saves three rows per frame (the scalar row, its
-- refs link, and the bucket entry) at the cost of one
-- column on every objects row — a good trade when frames are
-- pushed and popped often. [ghi]
alter table objects add column stmt_idx integer check (stmt_idx >= 0);

-- idx: stack position of this frame within its process. 0 for the
-- outermost frame; incremented for each nested call. Frame-objects
-- only; non-frame objects leave it null. Immutable at INSERT for a
-- given frame — a frame's stack position is fixed at push time.
-- Same trade as stmt_idx: promoting the idx reference out of a
-- bucket entry saves three rows per frame. Non-negative integer;
-- null passes the CHECK unmarked. [ghi]
alter table objects add column idx integer check (idx >= 0);

-- process: FK to the processes table for frame-objects. Declared
-- further down in this section, immediately after `create table
-- processes`, because SQLite validates FK targets at insert time
-- and the alter-table statement would fail here before processes
-- exists. See the block after `create table processes` for the
-- actual DDL and the design rationale. [ghi]

-- owner_role: ownership pointer for non-role objects. Every non-role
-- object carries owner_role pointing at the role that created it.
-- The rule is XOR with role_parent: a row is EITHER a role
-- (role_parent set — the role tree case) OR owned by one (owner_role
-- set — every other object) — never both, never neither, except the
-- grandfathered user seed inserted just below (BEFORE the enforcement
-- triggers exist, so its role_parent = null, owner_role = null state
-- is preserved).
--
-- No `on delete cascade`: role deletion doesn't take its owned objects
-- with it. Deletion of a role that still owns things is a load-bearing
-- event and should be either restricted or explicitly handled by the
-- engine; the FK stays plain until that policy is spec'd. [ghi]
alter table objects add column owner_role text references objects(object_pk);

-- ------------------------------------------------------------
-- Indexes for CVM's added columns.
-- ------------------------------------------------------------

-- User marker: partial unique index enforces "at most one user row"
-- (inline UNIQUE isn't available on ALTER TABLE ADD COLUMN in SQLite,
-- so the constraint moves to a partial index). `where user = 1` keeps
-- the index empty on the null rows — the index only ever has one
-- entry, which is what makes `select object_pk from objects where user`
-- (or `= 1`) a direct hit. [ghi]
create unique index objects_user on objects(user) where user = 1;

-- Role tree: partial index over just the non-root role rows. The
-- uspace view's `where role_parent is not null` branch walks this;
-- role-tree traversal queries (find children of X) use it too. [ghi]
create index objects_role_parent on objects(role_parent) where role_parent is not null;

create index objects_owner_role  on objects(owner_role)  where owner_role is not null;

-- ------------------------------------------------------------
-- Roles view — single source of truth for "what is a role."
-- ------------------------------------------------------------
-- A row is a role iff `user = 1` (the root role — the seed) OR
-- `role_parent is not null` (a non-root role in the tree). Two
-- triggers below check this condition when validating role_parent /
-- owner_role FK targets, and the uspace view unions from this view —
-- the definition factors out here so all three touch one source.
--
-- Written as UNION rather than `... where user = 1 or role_parent is
-- not null` because the OR form defeats index selection — SQLite's
-- planner can't split an OR across two different indexes, so it
-- would fall back to a full table scan for `select * from roles`.
-- UNION lets each branch use its own index: `user = 1` hits the
-- objects_user partial index, `role_parent is not null` hits the
-- objects_role_parent partial index. Verified by
-- tests/view-indexes.lua.
--
-- Trigger-time pk lookups (`select 1 from roles where object_pk = X`)
-- still short-circuit to the PK index inside each branch — SQLite
-- flattens the view query and pushes the pk predicate down. [ghi]
create view roles as
	select object_pk from objects where user = 1
	union
	select object_pk from objects where role_parent is not null;

-- ------------------------------------------------------------
-- Immutability triggers for the CVM-added role columns. Mikobase's
-- objects_no_update covers the base columns; user and role_parent
-- get their own guards here because those columns don't exist yet
-- when objects_no_update is created. Same pattern as
-- objects_owner_role_immutable further below.
-- ------------------------------------------------------------

-- User marker is set at INSERT (on the seed) and never changes. [ghi]
create trigger objects_user_immutable
before update of user on objects
when new.user is not old.user
begin
	select raise(abort, 'objects_user_immutable: objects.user is immutable');
end;

-- role_parent is set at INSERT and never changes — no role
-- reparenting. This immutability is load-bearing: it's what makes
-- the role tree cycle-free (a row can only reference a row that
-- already exists, and no existing row can be repointed at a newer
-- row). [ghi]
create trigger objects_role_parent_immutable
before update of role_parent on objects
when new.role_parent is not old.role_parent
begin
	select raise(abort, 'objects_role_parent_immutable: objects.role_parent is immutable (no role reparenting)');
end;

-- Seed the root role. User is the root role: primitive = 'h'
-- (a HashPrimitive per current design), user = 1 marks it as root,
-- persistent = 1 for consistency (the row persists anyway via
-- `where user`), role_parent = null (root has no parent),
-- owner_role = null (grandfathered — this seed exists before the
-- ownership triggers below are created, so nothing checks it).
-- Its object_pk is a fresh UUID from the default. [ghi]
insert into objects (primitive, user, persistent) values ('h', 1, 1);

-- ownership triggers — created AFTER the seed so the user row is
-- grandfathered. Every non-seed insert into objects must have
-- exactly one of role_parent / owner_role set. [ghi]

-- XOR rule: a role cannot have an owner, and a non-role must have one.
-- "Is a role" uses the same definition as elsewhere in this schema:
-- `role_parent is not null OR user = 1`. Rows attempting to set
-- user = 1 are treated as roles for this check (the objects_user
-- unique index separately enforces "at most one user row"). [ghi]
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

-- Every non-root role must name a parent that is itself a role.
-- "Is a role" is defined by the `roles` view above (user = 1 or
-- role_parent set). BEFORE INSERT only — role_parent is immutable
-- via objects_role_parent_immutable above, so a row's role-ness is
-- determined at insert time and can't be silently stripped
-- afterward. The WHEN clause skips inserts with role_parent null
-- (the common case). When it does fire, one pk-indexed lookup via
-- the roles view verifies the target row. [ghi]
create trigger objects_role_parent_must_be_role
before insert on objects
when new.role_parent is not null
begin
	select case
		when (select 1 from roles where object_pk = new.role_parent) is null
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
-- INSERT-only: role_parent is immutable via objects_role_parent_immutable,
-- so the not-self invariant is set at creation and can't be broken. [ghi]
create trigger objects_role_parent_not_self
before insert on objects
when new.role_parent is not null and new.role_parent = new.object_pk
begin
	select raise(abort, 'objects_role_parent_not_self: role_parent cannot equal object_pk (a role cannot be its own parent)');
end;

-- owner_role, when set, must reference an actual role. Uses the
-- `roles` view (defined above) as the single source of truth for
-- role-ness. Same shape as objects_role_parent_must_be_role.
-- INSERT-only — owner_role is immutable at INSERT via the trigger
-- below, so a row's owner can't be silently repointed at a non-role
-- after the fact. [ghi]
create trigger objects_owner_role_must_be_role
before insert on objects
when new.owner_role is not null
begin
	select case
		when (select 1 from roles where object_pk = new.owner_role) is null
		then raise(abort, 'owner_role_must_be_role: owner_role must reference a row that is itself a role (root user row or a row with role_parent set)')
	end;
end;

-- owner_role is immutable at INSERT — no reparenting an object
-- between roles at runtime. Matches how role_parent is immutable
-- via objects_role_parent_immutable above; owner_role gets its own
-- guard the same way, one column per trigger, since both columns
-- are CVM additions the Mikobase objects_no_update can't reach. [ghi]
create trigger objects_owner_role_immutable
before update of owner_role on objects
when new.owner_role is not old.owner_role
begin
	select raise(abort, 'objects_owner_role_immutable: owner_role is immutable (no reparenting an object to a different role)');
end;

-- An object cannot be its own owner. Same class of check as
-- objects_role_parent_not_self above; explicit defense-in-depth with
-- a specific error ID, and structurally: an object owning itself
-- would be a cycle in the ownership graph. [ghi]
create trigger objects_owner_role_not_self
before insert on objects
when new.owner_role is not null and new.owner_role = new.object_pk
begin
	select raise(abort, 'objects_owner_role_not_self: owner_role cannot equal object_pk (an object cannot be its own owner)');
end;

-- The user row (marked `user = 1`) is the root role and cannot
-- be deleted. Every CVM database starts with user seeded, and
-- nothing above the language layer can remove it. Non-root uspace
-- anchors are freely deletable (that's how an object leaves user
-- space in the first place). [ghi]
create trigger objects_no_delete_root_role
before delete on objects
when old.user
begin
	select raise(abort, 'root_role_cannot_be_deleted: the user row cannot be deleted');
end;

-- Symmetric with the delete guard above. The per-column immutability
-- triggers already cover most of the user row's fields (object_pk,
-- primitive, scalars, bucket_for/stack_for from Mikobase's
-- objects_no_update, plus user, role_parent, owner_role from the CVM
-- guards above). This trigger closes the small remaining gap
-- (persistent, ast, needs_trace, in_trace on the user row) — no
-- caller should ever be flipping the root role's pin off, attaching
-- an ast to it, or marking it for trace. If a mark trigger ever
-- fires against the user row, that's the bug worth catching: the
-- user row shouldn't be appearing as a child of another container. [ghi]
create trigger objects_no_update_root_role
before update on objects
when old.user
begin
	select raise(abort, 'root_role_cannot_be_updated: the user row cannot be updated');
end;

-- Role tree summary. A row IS a role iff it has role_parent set
-- (non-root) or user = 1 (root). The schema enforces:
--   Single parent — one column, one value.
--   Cycle-free — role_parent is immutable and INSERT requires
--     the target row to exist, so cycles are structurally
--     impossible.
--   Cascade cleanup — FK on delete cascade drops the subtree.
--   Root safety — objects_no_delete_root_role + objects_no_update_root_role
--     keep the user row undeletable and unmutable.
--   Parent-is-a-role — objects_role_parent_must_be_role rejects
--     any insert whose role_parent points at a non-role row.
-- What the schema does NOT check: naming, uniqueness of role
-- names, class-ownership rules — all Lua.
--
-- Roles are anchored in uspace via the uspace view's role branch —
-- the tree's rows are structurally pinned by the FK, not by general
-- reachability. Role bucket contents still trace normally. [ghi]


-- ------------------------------------------------------------
-- Instance-level event listeners.
-- ------------------------------------------------------------
-- A listener registers to be called when a specific broadcaster
-- emits a specific event. Spec: requirements/events/index.
--
-- Registrations are bookkeeping, not graph edges — they live
-- outside `refs` so GC does NOT count them as reachability.
-- Weak-ref lifetime falls out of ON DELETE CASCADE: when either
-- party's `objects` row is deleted (typically because GC decided it
-- was unreachable), the registration cascade-deletes. [ghi]

create table instance_listeners (
	reg_pk integer primary key autoincrement,

	broadcaster text not null references objects(object_pk) on delete cascade,
	listener    text not null references objects(object_pk) on delete cascade,

	-- event and method names are inline text, not references to
	-- StringPrimitive objects. Interning is an engine-layer
	-- optimization if it turns out to matter; storage keeps it
	-- simple. [ghi]
	event_name  text not null,
	method_name text not null,

	-- Idempotent: `.listen_to` called twice with the same combo is
	-- one registration, not two. The Lua write API uses INSERT OR
	-- IGNORE to swallow the collision silently. [ghi]
	unique (broadcaster, event_name, listener, method_name)
);

-- Dispatch lookup: given a broadcaster + event, find its listeners. [ghi]
create index instance_listeners_broadcaster on instance_listeners(broadcaster, event_name);

-- Unlisten-all lookup: given a listener, find all its rows. [ghi]
create index instance_listeners_listener on instance_listeners(listener);

-- Registrations are add-or-remove-only. Every field is immutable
-- after INSERT; to change a registration, DELETE and INSERT. [ghi]
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
-- requirements/events/listen-to-class. [ghi]

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
-- Processes — call stack roots.
-- ------------------------------------------------------------
-- Runtime execution state under the frames-as-objects model lives
-- as regular rows in `objects` (see the frame-shaped objects branch
-- of the objects table). The `processes` table stays as a small,
-- purpose-built root — each row is one call stack. Frames themselves
-- are ordinary objects that reference their process via a bucket
-- field or a dedicated FK (still to be worked out below). [ghi]
--
-- `processes` is plural: the schema accommodates multiple execution
-- contexts coexisting in one CVM file — coroutines, fork children,
-- multiple paused processes, or shared-object-graph concurrency.
--
-- No seed row — each engine creates its own processes row on
-- startup and records its pk in current_process. Multi-process
-- features will create additional rows here at runtime.

create table processes (
	process_pk integer primary key autoincrement
);

-- processes rows are immutable — once a process is created its
-- process_pk is fixed for the row's lifetime. Ending a process is
-- a DELETE, not an UPDATE. [ghi]
create trigger processes_no_update
before update on processes
begin
	select raise(abort, 'processes_no_update: processes rows are immutable');
end;

-- ------------------------------------------------------------
-- objects.process — frame → process FK, deferred to here.
-- ------------------------------------------------------------
-- Declared after `create table processes` so SQLite can resolve the
-- FK target. Every frame-object carries this pointing at its own
-- process row; non-frame objects leave it null. Immutable at INSERT
-- for a given frame — a frame doesn't migrate between processes.
--
-- Same trade as stmt_idx above: promoting the process reference out
-- of a bucket entry saves three rows per frame (the number-scalar
-- objects row, its refs link, and the bucket entry).
-- SQLite skips FK checks on null values, so a null on non-frame
-- rows costs nothing.
--
-- No cascade on delete — process teardown policy is a Caspian-level
-- concern to be spec'd. [ghi]
alter table objects add column process integer references processes(process_pk);

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
--   * Explicitly pinned via `persistent = 1`.
--   * A role (via the role_parent chain rooted at user).
--
-- Frame-object anchors — locals, ambers, delegations, lexical_parent
-- links reaching from live frame-objects — TBD. Under the
-- frames-as-objects model, frames are ordinary objects living in
-- `objects` and their reachability likely folds into the standard
-- object-graph trace rather than needing separate uspace branches.
-- [ghi]
--
-- Buckets and stacks are NOT in this list. They live inside their
-- owner via bucket_for / stack_for (ON DELETE CASCADE handles
-- owner-goes-so-bucket-goes at the FK level). Under normal
-- CVM ops nothing puts a bucket or stack row as a child in
-- the refs table, so mark triggers never fire on them —
-- they never become GC candidates.
--
-- Roles (children of user in the role tree) aren't a special
-- case — they're regular objects reachable via refs from
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
-- cheap in practice. [ghi]

create view uspace as
	-- Every role (root + non-root) — pulled from the `roles` view
	-- so uspace and the trigger-time role checks share one
	-- definition of role-ness. [ghi]
	select object_pk from roles
	union
	-- Objects flagged persistent — pinned regardless of other anchors.
	-- `= 1` (rather than truthy `where persistent`) so the
	-- objects_persistent partial index applies.  [ghi]
	select object_pk from objects where persistent = 1;

-- TODO: frame-object anchors — under the frames-as-objects model, live
-- frames anchor whatever their frame-bucket fields point at (locals,
-- ambers, delegations, lexical_parent). Shape TBD as this design
-- shakes out; expect additional UNION branches or a single "reachable
-- from processes via frame-chains" branch. [ghi]
