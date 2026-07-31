-- Fiona database design.

-- Foreign-key enforcement is off by default in SQLite; turn it on so the
-- `references` clauses actually enforce existence at insert/delete time.
-- Per-connection setting — callers opening additional connections need to
-- set it again themselves.
pragma foreign_keys = on;

-- Recursive triggers are off by default. Turn them on so the purge trigger
-- can fire again on the cascade-deletes it itself causes, letting cleanup
-- propagate through the affected subgraph. Per-connection setting.
pragma recursive_triggers = on;

create table hsa (
	hsa_pk integer primary key autoincrement,
	type text not null check (type in ('h', 's', 'a')),
	st text check (st in ('s', 'n', 'b', 'u')),
	-- polymorphic; interpret via st
	value,
	-- st is required for scalars, forbidden for hashes and arrays.
	check (
		(type = 's' and st is not null) or
		(type in ('h', 'a') and st is null)
	),
	-- boolean scalars store value as 0 or 1. Uses `is` (not `in`) so that
	-- value=null cleanly evaluates to false — the `in` form would give
	-- NULL, which SQLite's CHECK accepts as passing.
	check (st != 'b' or value is 0 or value is 1),
	-- null scalars store value as null.
	check (st != 'u' or value is null),
	-- number scalars store value as an integer or float (either sign).
	check (st != 'n' or typeof(value) in ('integer', 'real')),
	-- string scalars store value as text.
	check (st != 's' or typeof(value) = 'text'),
	-- hash and array rows have no scalar value; structure lives in relationships.
	check (type = 's' or value is null)
);

-- every row is immutable; changes happen via insert + delete, never update.
create trigger hsa_no_update
before update on hsa
begin
	select raise(abort, 'hsa rows are immutable');
end;

-- the root hash cannot be deleted. it's always hsa_pk = 1 because it's
-- the first row inserted below.
create trigger hsa_no_delete_root
before delete on hsa
when old.hsa_pk = 1
begin
	select raise(abort, 'the root hsa row cannot be deleted');
end;

-- Seed the root hash. Every Fiona database starts with this row.
insert into hsa (type) values ('h');

create table relationships (
	rel_pk integer primary key autoincrement,
	-- on delete cascade so the purge trigger (below) can delete an hsa row
	-- and have its remaining relationships drop with it. Cascade also means
	-- a direct `delete from hsa where hsa_pk = X` silently removes X's
	-- edges instead of raising — direct hsa deletion isn't a supported user
	-- op (users delete relationships, GC handles hsa), so this is fine.
	parent integer not null references hsa(hsa_pk) on delete cascade,
	child integer not null references hsa(hsa_pk) on delete cascade,
	-- key is set for hash parents (Ruby-style ordered hashes: each entry
	-- is both keyed AND ordered), null for array parents. `index` is a
	-- SQL keyword, hence `idx`. `idx` is left untyped (BLOB affinity, no
	-- coercion) so `typeof(idx)` accurately reflects the caller's input
	-- when we enforce it via CHECK — integer-affinity would silently
	-- coerce '42' to 42, defeating the type guard.
	key text,
	-- idx is required for every relationship: arrays use it as position,
	-- hashes use it as insertion order (Ruby/Caspian semantics).
	idx not null,
	-- idx must be a non-negative integer. The shift triggers below use an
	-- arithmetic hop of OFFSET = 10^18 to avoid unique-constraint collisions
	-- while shifting a range; that only works if legitimate idx values stay
	-- well below OFFSET. There is deliberately no upper-bound CHECK because
	-- the parking step in the UPDATE-shift trigger transiently sets idx to
	-- (real + OFFSET), and a CHECK would fire against the trigger itself.
	check (typeof(idx) = 'integer'),
	check (idx >= 0),
	-- no two relationships from the same parent share a key or an idx.
	unique (parent, key),
	unique (parent, idx)
);

-- Indexes for the common lookup directions: children of a parent, and
-- parents of a child (multiple-parent case per Fiona's graph semantics).
create index relationships_parent on relationships (parent);
create index relationships_child on relationships (child);

-- Enforce that parent references a hash or array (not a scalar) and that
-- `key` matches the parent's type: hashes require key, arrays forbid it.
-- `idx` is required for both and enforced via the NOT NULL column
-- constraint, which fires whether or not this trigger runs. SQLite CHECK
-- constraints can't do subqueries; cross-table rules go in a trigger.
create trigger relationships_check_types
before insert on relationships
begin
	select case
		when (select type from hsa where hsa_pk = new.parent) not in ('h', 'a')
			then raise(abort, 'relationships.parent must reference a hash or array')
		when (select type from hsa where hsa_pk = new.parent) = 'h' and new.key is null
			then raise(abort, 'hash-parented relationships must set key')
		when (select type from hsa where hsa_pk = new.parent) = 'a' and new.key is not null
			then raise(abort, 'array-parented relationships must not set key')
	end;
end;

-- Immutability: every column is immutable except idx, which can shift as
-- items are inserted or reordered within an array.
create trigger relationships_no_update
before update on relationships
begin
	select case
		when new.rel_pk is not old.rel_pk
			then raise(abort, 'relationships.rel_pk is immutable')
		when new.parent is not old.parent
			then raise(abort, 'relationships.parent is immutable')
		when new.child is not old.child
			then raise(abort, 'relationships.child is immutable')
		when new.key is not old.key
			then raise(abort, 'relationships.key is immutable')
	end;
end;

-- Idx-shift on INSERT. If the incoming row's idx collides with an existing
-- sibling, shift the sibling (and everything at higher idx) up by 1 to make
-- room. Uses a two-phase arithmetic hop through the safe range (idx +
-- 10^18) so the intermediate state never violates the unique constraint.
-- New record: no parking needed (the row doesn't exist yet), so this
-- trigger is simpler than its UPDATE counterpart.
create trigger relationships_shift_on_insert
before insert on relationships
when exists (
	select 1 from relationships
	where parent = new.parent and idx = new.idx
)
begin
	-- Phase 1: hop the colliding + subsequent rows into the safe range.
	update relationships set idx = idx + 1000000000000000000
	where parent = new.parent and idx >= new.idx;
	-- Phase 2: hop them back, offset by +1. Net effect: shifted up by 1.
	update relationships set idx = idx - 999999999999999999
	where parent = new.parent and idx >= 1000000000000000000;
end;

-- Idx-shift on UPDATE OF idx (move an existing record). The moved row
-- currently sits at OLD.idx, which is inside the range that needs to shift
-- — so we first PARK the moved row at (OLD.idx + 10^18), out of the way,
-- then do a direction-aware range shift of the siblings between OLD.idx
-- and NEW.idx, and finally the outer UPDATE overwrites the parked row's
-- idx with NEW.idx. Direction-aware so density is preserved (siblings
-- outside the [OLD.idx, NEW.idx] range are untouched).
create trigger relationships_shift_on_update
before update of idx on relationships
when new.idx <> old.idx and exists (
	select 1 from relationships
	where parent = old.parent and idx = new.idx and rel_pk <> old.rel_pk
)
begin
	-- Park the moved row.
	update relationships set idx = old.idx + 1000000000000000000
	where rel_pk = old.rel_pk;
	-- Hop the intervening siblings into the safe range.
	update relationships set idx = idx + 1000000000000000000
	where parent = old.parent
		and rel_pk <> old.rel_pk
		and (
			(new.idx < old.idx and idx between new.idx and old.idx - 1)
			or (new.idx > old.idx and idx between old.idx + 1 and new.idx)
		);
	-- Hop back with direction-aware offset: +1 for up-move (shift siblings
	-- up by 1), -1 for down-move (shift siblings down by 1).
	update relationships set idx =
		idx - 1000000000000000000 + case when new.idx < old.idx then 1 else -1 end
	where parent = old.parent
		and idx >= 1000000000000000000
		and rel_pk <> old.rel_pk;
	-- The moved row stays parked; the outer UPDATE overwrites it to NEW.idx.
end;

-- Garbage collection. After any relationship deletion, purge hsa rows that
-- no longer trace back to root. Runs a full reachability sweep from root
-- (hsa_pk = 1); anything unreachable is deleted. The delete cascades to
-- remove each removed row's remaining edges, which re-fires this trigger
-- (requires pragma recursive_triggers = on). Iterations converge quickly:
-- once the unreachable set is gone, the next fire's CTE finds nothing to
-- delete and recursion stops. Correct under cycles because reachability
-- from root is graph-shape-agnostic — a fully-detached cycle simply never
-- makes it into `reachable`.
create trigger relationships_purge_after_delete
after delete on relationships
begin
	delete from hsa
	where hsa_pk not in (
		with recursive reachable(hsa_pk) as (
			select 1
			union
			select r.child from relationships r
			join reachable on r.parent = reachable.hsa_pk
		)
		select hsa_pk from reachable
	);
end;
