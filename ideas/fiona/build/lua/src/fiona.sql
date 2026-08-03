-- Fiona database design. Collections (h/a) live in the collections
-- table. Scalars live inline in the relationships table via st +
-- scalar columns. Each relationship is EITHER a collection-edge
-- (child set, st null) OR a scalar-carrying row (child null, st +
-- scalar set).

pragma foreign_keys = on;

-- Recursive triggers are on so mark triggers fire on FK cascade-deletes
-- during the drain's bulk DELETE FROM collections. Depth stays bounded
-- because the mark triggers' action is a plain UPDATE with no cascade.
pragma recursive_triggers = on;

-- ------------------------------------------------------------
-- Meta table
-- ------------------------------------------------------------

create table meta (
	key text primary key,
	value text
);

insert into meta (key, value) values ('schema', '2.0');

-- ------------------------------------------------------------
-- Collections: hashes and arrays.
-- ------------------------------------------------------------

create table collections (
	collection_pk integer primary key autoincrement,
	type text not null check (type in ('h', 'a')),
	-- Transient GC scratch. needs_trace is null (unset) or 1 (marked as
	-- a candidate seed). in_trace is null (not currently traced) or a
	-- positive integer that gives the order the drain's callback loop
	-- fires against this row — see specs/on-gc.md.
	needs_trace integer check (needs_trace is null or needs_trace = 1),
	in_trace    integer check (in_trace    is null or in_trace     > 0)
);

create index collections_needs_trace on collections(needs_trace) where needs_trace = 1;
create index collections_in_trace    on collections(in_trace)    where in_trace   is not null;

-- Identity (collection_pk, type) is immutable. needs_trace / in_trace
-- are the only mutable columns.
create trigger collections_no_update
before update on collections
begin
	select case
		when new.collection_pk is not old.collection_pk
			then raise(abort, 'collections.collection_pk is immutable')
		when new.type is not old.type
			then raise(abort, 'collections.type is immutable')
	end;
end;

-- Root is always collection_pk = 1 — seeded below. It cannot be
-- deleted. It can be updated only for in_trace: the drain's
-- propagation UPDATE walks upward and lands in_trace on root, and
-- the alive check reads root's in_trace directly. needs_trace on
-- root is never valid — root can never be a legitimate seed, so
-- letting it get marked would cause the drain to spin.
create trigger collections_no_delete_root
before delete on collections
when old.collection_pk = 1
begin
	select raise(abort, 'the root collection cannot be deleted');
end;

create trigger collections_root_no_needs_trace
before update on collections
when old.collection_pk = 1 and new.needs_trace
begin
	select raise(abort, 'the root collection cannot have needs_trace set');
end;

-- Seed root. Every Fiona database starts with this row.
insert into collections (type) values ('h');

-- ------------------------------------------------------------
-- Relationships: parent-to-either-a-child-collection-or-a-scalar edges.
-- Exactly one of `child` (collection reference) or `st` (scalar-type
-- discriminator) must be set. The `(child xor st)` invariant is
-- enforced by CHECK below; per-st scalar-shape rules follow.
-- ------------------------------------------------------------

create table relationships (
	rel_pk  integer primary key autoincrement,
	parent  integer not null references collections(collection_pk) on delete cascade,
	-- Collection-edge slot: populated iff this row anchors a child
	-- collection. Nullable because scalar-carrying rows don't use it.
	-- FK cascade fires on collection delete during the drain's bulk
	-- DELETE, which in turn fires the mark trigger below.
	child   integer references collections(collection_pk) on delete cascade,
	-- Hash-parented relationships require key; array-parented forbid
	-- it. Enforced by the relationships_check_types trigger since
	-- CHECK can't reach across tables.
	key     text,
	-- idx is required for every row: arrays use it as position, hashes
	-- use it as insertion order.
	idx     not null,
	-- Scalar-carrying slot: `st` is the scalar-type discriminator
	-- ('s' string, 'n' number, 'b' boolean, 'u' null/undefined), and
	-- `scalar` is the polymorphic value. Both null means this row is a
	-- collection-edge; both set means a scalar row.
	st      text check (st in ('s', 'n', 'b', 'u')),
	scalar,

	-- Exactly one of {child} or {st + scalar}. Never both, never neither.
	-- The "both null" case is the classic bug this catches: a row with
	-- no destination at all is meaningless.
	check (
		(child is not null and st is null and scalar is null) or
		(child is null and st is not null)
	),

	-- Per-st scalar shape. These use `is` (not `in`) so null cleanly
	-- evaluates to false — the `in` form would give NULL which SQLite's
	-- CHECK accepts as passing, silently letting null booleans through.
	check (st is null or st != 'b' or scalar is 0 or scalar is 1),
	check (st is null or st != 'u' or scalar is null),
	check (st is null or st != 'n' or typeof(scalar) in ('integer', 'real')),
	check (st is null or st != 's' or typeof(scalar) = 'text'),

	-- idx must be a non-negative integer. The shift triggers park rows
	-- above 10^18 during range shifts, so legitimate idx values must
	-- stay well below OFFSET. Deliberately no upper-bound CHECK because
	-- the parking step transiently violates it and CHECK fires on
	-- trigger-initiated writes too.
	check (typeof(idx) = 'integer'),
	check (idx >= 0),

	-- No two relationships from the same parent share a key or idx.
	unique (parent, key),
	unique (parent, idx)
);

-- Lookup indexes. relationships_child is partial — scalar-carrying
-- rows have child = null and don't need to appear in the reverse
-- (child → parents) walk the trace does.
create index relationships_parent on relationships(parent);
create index relationships_child  on relationships(child) where child is not null;

-- Enforce hash/array key rule via trigger (CHECK can't do subqueries).
create trigger relationships_check_types
before insert on relationships
begin
	select case
		when (select type from collections where collection_pk = new.parent) = 'h' and new.key is null
			then raise(abort, 'hash-parented relationships must set key')
		when (select type from collections where collection_pk = new.parent) = 'a' and new.key is not null
			then raise(abort, 'array-parented relationships must not set key')
	end;
end;

-- Identity is (rel_pk, parent, key). Content — child, idx, st, scalar
-- — is mutable, including swinging a row between collection-edge and
-- scalar shape (update child from set to null while setting st, or
-- vice versa). The CHECK constraints enforce validity of any state,
-- and the mark trigger below catches the collection-edge-severed case.
create trigger relationships_no_update
before update on relationships
begin
	select case
		when new.rel_pk is not old.rel_pk
			then raise(abort, 'relationships.rel_pk is immutable')
		when new.parent is not old.parent
			then raise(abort, 'relationships.parent is immutable')
		when new.key is not old.key
			then raise(abort, 'relationships.key is immutable')
	end;
end;

-- Idx collisions from raw SQL INSERT / UPDATE OF idx fail with a
-- UNIQUE constraint error. The Lua API doesn't collide (set_hash_ref /
-- set_hash_scalar use max(idx) + 1 on insert; set_array_ref / set_array_scalar
-- UPDATE the row when the slot is occupied) so no shift-on-collision
-- machinery is needed at the schema level. Shift-down on explicit
-- delete_array_element lives in Lua as Db:_shift_down_array (two-phase
-- 10^18 hop, not a trigger).

-- ------------------------------------------------------------
-- Mark triggers — the trace's worklist populator.
-- ------------------------------------------------------------

-- On DELETE of a collection-edge relationship: mark the old child
-- collection as needs_trace. Skip if the old child was root (never a
-- valid mark target) or if the row was scalar-carrying (no collection
-- to mark).
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
when old.child is not null and old.child <> 1
begin
	update collections set needs_trace = 1 where collection_pk = old.child;
end;

-- On UPDATE OF child: mark the OLD collection when child is swung
-- away, including the case where the row transitions from
-- collection-edge to scalar-carrying (new.child becomes null). The
-- `is not` operator handles null-vs-null and null-vs-value correctly
-- where `<>` would silently no-op on null.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child is not null and old.child <> 1 and old.child is not new.child
begin
	update collections set needs_trace = 1 where collection_pk = old.child;
end;
