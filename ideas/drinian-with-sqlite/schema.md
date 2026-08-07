# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_schema",
	"role": "Drinian's SQLite schema. `objects` table holds row shapes discriminated by a single `primitive` column — false (full object), 'h' (HashPrimitive), 'a' (ArrayPrimitive). Scalars are a variant of `primitive = false` distinguished by `st` (scalar type). HashPrimitives serving as buckets carry `bucket_for` back-pointing at their owner; ArrayPrimitives serving as stacks carry `stack_for`. Only container primitives can be parents in `relationships`. GC uses three-column scratch (needs_trace / in_trace / del).",
	"status": "iterating 2026-08-07 — separate bucket_for / stack_for columns naming role explicitly"
}}
~~~

Started 2026-08-07 from Fiona's current schema. Adapting as design decisions land.

## Design summary

Every Drinian row falls into one of these shapes, discriminated by `primitive`, `st`, `bucket_for`, and `stack_for`:

| Row shape | primitive | st | sv | bucket_for | stack_for |
|-----------|-----------|-----|-----|------------|-----------|
| HashPrimitive (standalone / root / internal) | `'h'` | null | null | null | null |
| HashPrimitive serving as a bucket | `'h'` | null | null | set | null |
| ArrayPrimitive (standalone / internal) | `'a'` | null | null | null | null |
| ArrayPrimitive serving as a stack | `'a'` | null | null | null | set |
| Plain full object (Hash, Array, MyClass, …) | `false` | null | null | null | null |
| StringPrimitive | `false` | `'s'` | text | null | null |
| NumberPrimitive | `false` | `'n'` | integer/real | null | null |
| BooleanPrimitive | `false` | `'b'` | 0/1 | null | null |
| NullPrimitive | `false` | `'u'` | null | null | null |

Rules baked into the schema:

- `primitive` is NOT NULL and has no default — every insert names the kind at creation time.
- Only container primitives (`primitive in ('h', 'a')`) can be parents in `relationships` — full objects and scalars can't have references directly; full objects reach their contents through their bucket / stack.
- **Role-shape alignment.** A row with `bucket_for` set must be a HashPrimitive (`primitive = 'h'`); a row with `stack_for` set must be an ArrayPrimitive (`primitive = 'a'`). An array can't be a bucket; a hash can't be a stack.
- **At most one role per row.** At most one of `bucket_for` / `stack_for` may be set on any given row. A row can't be both a bucket and a stack — enforced by `check (bucket_for is null or stack_for is null)`.
- **At most one bucket and one stack per owner.** `bucket_for` and `stack_for` are each `UNIQUE` — no two rows can be a bucket for the same owner (or a stack for the same owner). Null-null pairs don't collide because SQLite treats null as distinct in UNIQUE.
- Plain full objects auto-provision a bucket (HashPrimitive with `bucket_for` set) and stack (ArrayPrimitive with `stack_for` set) via an INSERT trigger.
- Deleting a full object cascades via FK to delete its bucket + stack (`bucket_for` and `stack_for` FKs have ON DELETE CASCADE). No cleanup trigger.
- **`objects` is effectively immutable.** All identity columns (`object_pk`, `primitive`, `st`, `sv`, `bucket_for`, `stack_for`) can never change. The only freely-mutable state is GC scratch (`needs_trace`, `in_trace`, `del`). Enforced by `objects_no_update`.
- Scalars are single-row leaves — a StringPrimitive is one row with `primitive = false`, `st = 's'`, `sv = <text>`.

## Schema

~~~sql
-- Drinian database design. One `objects` table holds row shapes
-- discriminated by the `primitive` column:
--   'h'   → HashPrimitive (hash-shaped primitive container)
--   'a'   → ArrayPrimitive (array-shaped primitive container)
--   false → not a primitive collection. Either a plain full object
--           (with an auto-provisioned bucket + stack) or a scalar
--           primitive (with a scalar type in `st` and value in `sv`).
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

-- Recursive triggers are on so mark triggers fire on FK
-- cascade-deletes during the drain's bulk DELETE FROM objects. Depth
-- stays bounded because the mark triggers' action is a plain UPDATE
-- with no cascade.
pragma recursive_triggers = on;

-- ------------------------------------------------------------
-- Meta table
-- ------------------------------------------------------------

create table meta (
	key text primary key,
	value text
);

insert into meta (key, value) values ('schema', '6.0');

-- ------------------------------------------------------------
-- Objects: primitive containers, plain full objects, scalars.
-- ------------------------------------------------------------

create table objects (
	object_pk integer primary key autoincrement,

	-- Row-kind discriminator. NOT NULL, no default: Drinian's write
	-- code names the row kind at INSERT time. SQLite treats `false`
	-- as an alias for 0.
	--   false → full object (not a primitive collection)
	--   'h'   → HashPrimitive
	--   'a'   → ArrayPrimitive
	primitive not null check (primitive in (false, 'h', 'a')),

	-- Scalar type. Only meaningful when primitive = false. When set,
	-- this row is a scalar primitive; when null on a primitive =
	-- false row, this row is a plain full object with a bucket +
	-- stack.
	--   's' string, 'n' number, 'b' boolean, 'u' null
	st text check (st in ('s', 'n', 'b', 'u')),
	check (primitive = false or st is null),

	-- Scalar value. Meaningful only when `st` is set. Per-st shape
	-- checks use `is` (not `in`) so null cleanly evaluates to false
	-- — the `in` form would give NULL which SQLite's CHECK accepts
	-- as passing, silently letting null booleans through.
	sv,
	check (st is null or st != 'b' or sv is 0 or sv is 1),
	check (st is null or st != 'u' or sv is null),
	check (st is null or st != 'n' or typeof(sv) in ('integer', 'real')),
	check (st is null or st != 's' or typeof(sv) = 'text'),
	check (st is not null or sv is null),

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
	-- one stack. SQLite treats null as distinct in UNIQUE, so many
	-- rows with these columns null don't collide.
	bucket_for integer unique references objects(object_pk) on delete cascade,
	stack_for  integer unique references objects(object_pk) on delete cascade,
	check (bucket_for is null or primitive = 'h'),
	check (stack_for  is null or primitive = 'a'),
	check (bucket_for is null or stack_for is null),

	-- Transient GC scratch. All three are 1 or null — CHECK doesn't
	-- fire on null, so no `X is null or` guard is needed.
	--
	-- needs_trace: 1 means this row is a candidate seed the drain
	-- should trace from. in_trace: positive integer giving the order
	-- the drain's callback loop fires against this row (see
	-- specs/on-gc.md). del: 1 means the drain has determined this
	-- row is dead and it will be removed by the bulk DELETE at the
	-- end of the GC pass.
	needs_trace integer check (needs_trace = 1),
	in_trace    integer check (in_trace > 0),
	del         integer check (del = 1)
);

create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;
create index objects_del         on objects(del)         where del = 1;

-- All identity columns are immutable from INSERT: object_pk,
-- primitive, st, sv, bucket_for, stack_for. The only freely-mutable
-- columns are the GC scratch trio (needs_trace, in_trace, del).
create trigger objects_no_update
before update on objects
begin
	select case
		when new.object_pk is not old.object_pk
			then raise(abort, 'objects_pk_immutable: objects.object_pk is immutable')
		when new.primitive is not old.primitive
			then raise(abort, 'objects_primitive_immutable: objects.primitive is immutable')
		when new.st is not old.st
			then raise(abort, 'objects_st_immutable: objects.st is immutable')
		when new.sv is not old.sv
			then raise(abort, 'objects_sv_immutable: objects.sv is immutable')
		when new.bucket_for is not old.bucket_for
			then raise(abort, 'objects_bucket_for_immutable: objects.bucket_for is immutable')
		when new.stack_for is not old.stack_for
			then raise(abort, 'objects_stack_for_immutable: objects.stack_for is immutable')
	end;
end;

-- Root is always object_pk = 1 — seeded below. It cannot be deleted.
-- It can be updated only for in_trace: the drain's propagation walk
-- lands in_trace on root, and the alive check reads root's in_trace
-- directly. needs_trace on root is never valid — root can never be a
-- legitimate seed, so letting it get marked would cause the drain to
-- spin. (Deferred: the uspace question — currently root is a single
-- pk=1 anchor; will be replaced by a uspace-flag mechanism later.)
create trigger objects_no_delete_root
before delete on objects
when old.object_pk = 1
begin
	select raise(abort, 'root_cannot_be_deleted: the root object cannot be deleted');
end;

create trigger objects_root_no_needs_trace
before update on objects
when old.object_pk = 1 and new.needs_trace
begin
	select raise(abort, 'root_cannot_be_marked: the root object cannot have needs_trace set');
end;

-- Seed root: a standalone HashPrimitive at object_pk = 1 with
-- bucket_for / stack_for null. Every Drinian database starts with
-- this row. Root is not a full object so it doesn't auto-provision
-- a bucket + stack.
insert into objects (primitive) values ('h');

-- ------------------------------------------------------------
-- Auto-provision buckets and stacks for plain full objects.
-- ------------------------------------------------------------

-- On INSERT of a plain full object (primitive = false AND st null),
-- create its bucket (HashPrimitive with bucket_for = new.object_pk)
-- and its stack (ArrayPrimitive with stack_for = new.object_pk).
-- The bucket and stack rows themselves don't fire this trigger —
-- their primitive is 'h' / 'a', which the WHEN clause excludes — so
-- no recursion. The owner row is not touched after its INSERT: the
-- FK direction (bucket/stack point at owner) means all linkage
-- lives on the newly-inserted rows.
create trigger objects_auto_provision_bucket_and_stack
after insert on objects
when new.primitive = false and new.st is null
begin
	insert into objects (primitive, bucket_for) values ('h', new.object_pk);
	insert into objects (primitive, stack_for)  values ('a', new.object_pk);
end;

-- ------------------------------------------------------------
-- Relationships: parent-to-child object edges.
-- ------------------------------------------------------------
-- Every row is an object-to-object edge. The parent must be a
-- container primitive ('h' or 'a') — full objects and scalars
-- cannot be parents. Enforced by trigger below.

create table relationships (
	rel_pk  integer primary key autoincrement,

	parent  integer not null references objects(object_pk) on delete cascade,
	child   integer not null references objects(object_pk) on delete cascade,

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
	-- constraint because SQLite treats null as distinct in UNIQUE.
	unique (parent, key),
	unique (parent, idx)
);

create index relationships_parent on relationships(parent);
create index relationships_child  on relationships(child);

-- Only container primitives ('h' or 'a') can be parents. Full
-- objects (primitive = false) and scalar primitives cannot appear
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
-- Skip if the old child was root (never a valid mark target).
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
when old.child <> 1
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- On UPDATE OF child: mark the OLD child when the slot is swung
-- to a different object. `is not` handles null-vs-value correctly
-- where `<>` would silently no-op on null.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child <> 1 and old.child is not new.child
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;
~~~
