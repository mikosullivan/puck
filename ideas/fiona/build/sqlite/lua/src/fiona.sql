-- Fiona database design.

-- Foreign-key enforcement is off by default in SQLite; turn it on so the
-- `references` clauses actually enforce existence at insert/delete time.
-- Per-connection setting — callers opening additional connections need to
-- set it again themselves.
pragma foreign_keys = on;

-- Recursive triggers are off by default. Turn them on so that the mark
-- triggers below fire on the cascade-deletes produced by the drain step
-- of the Lua-side GC — that's what lets a bulk delete of the in_trace
-- set feed the next round of needs_trace candidates. Per-connection
-- setting.
pragma recursive_triggers = on;

-- Meta table: key/value settings about the database itself. For V1 the
-- only row is `schema`, which names the schema version this file was
-- built against. The key/value shape leaves room to add rows later
-- without a schema change.
create table meta (
	key text primary key,
	value text
);

insert into meta (key, value) values ('schema', '1.0');

create table hsa (
	hsa_pk integer primary key autoincrement,
	type text not null check (type in ('h', 's', 'a')),
	st text check (st in ('s', 'n', 'b', 'u')),
	-- polymorphic; interpret via st
	value,
	-- Transient GC scratch. Both are strictly null (not marked) or 1
	-- (marked) — the column-level CHECKs enforce that so an assertion at
	-- drain end can verify "everything is null" as a proxy for "nothing
	-- marked." Neither flag is ever meant to be observed as 1 outside a
	-- transaction: Lua-side drain runs before the outermost atomic()
	-- releases and clears both. Storing as null-or-1 (rather than 0/1)
	-- makes the partial index below empty in the resting state, so the
	-- seed-lookup query touches ≈zero index rows on the common no-orphan
	-- path.
	needs_trace integer check (needs_trace is null or needs_trace = 1),
	in_trace    integer check (in_trace    is null or in_trace    = 1),
	-- st is required for scalars, forbidden for hashes and arrays.
	check (
		(type = 's' and st is not null) or
		(type in ('h', 'a') and st is null)
	),
	-- boolean scalars store value as 0 or 1. Uses `is` (not `in`) so that
	-- value=null cleanly evaluates to false — the `in` form would give
	-- null, which SQLite's CHECK accepts as passing.
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

-- Partial indexes for the seed-lookup and bulk-clear queries the Lua
-- drain does. Both indexes are empty when nothing is marked, so
-- maintenance cost tracks the mark/clear volume, not the hsa row count.
create index hsa_needs_trace on hsa(needs_trace) where needs_trace = 1;
create index hsa_in_trace    on hsa(in_trace)    where in_trace    = 1;

-- Identity (hsa_pk, type) is immutable; everything else is content and
-- follows the CHECK constraints on the columns. In practice that means
-- scalars can freely UPDATE their st/value (change a counter, retype a
-- number to a string) but hashes and arrays can't grow st/value because
-- the CHECKs above forbid non-null st or value for type in ('h','a').
create trigger hsa_no_update
before update on hsa
begin
	select case
		when new.hsa_pk is not old.hsa_pk
			then raise(abort, 'hsa.hsa_pk is immutable')
		when new.type is not old.type
			then raise(abort, 'hsa.type is immutable')
	end;
end;

-- the root hash cannot be deleted. it's always hsa_pk = 1 because it's
-- the first row inserted below.
create trigger hsa_no_delete_root
before delete on hsa
when old.hsa_pk = 1
begin
	select raise(abort, 'the root hsa row cannot be deleted');
end;

-- Root is also never updateable. It's the anchor of the reachability
-- model — the drain must not mark it (needs_trace or in_trace), and its
-- identity/scalar fields already have nothing to change (root is a
-- hash, so st/value are null by construction). This trigger is the
-- belt-and-suspenders enforcement: any code path that tries to update
-- row 1 for any reason fails loudly, catching drain bugs that would
-- otherwise leave root wrongly marked at commit.
create trigger hsa_no_update_root
before update on hsa
when old.hsa_pk = 1
begin
	select raise(abort, 'the root hsa row cannot be updated');
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

-- Identity is (rel_pk, parent, key) — those spell out "which slot this
-- edge is." child is content (what the slot holds) and can change in
-- place; idx is position and is managed by the shift triggers below.
-- The purge_after_update_of_child trigger downstream keeps GC firing
-- when child changes so orphaned rows still get collected.
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

-- Shift-down on explicit `delete_array_element` lives in Lua now
-- (Db:delete_array_element → Db:_shift_down_array), using the same
-- two-phase 10^18 hop the shift-on-update trigger uses so no
-- dependency on the SQLite planner's UPDATE-row-processing order is
-- involved. Cascade deletes from the drain (removing an hsa row that
-- was a child of a surviving array parent) deliberately leave gaps
-- in that parent's idx values — sparse arrays are a valid Fiona
-- state, and the shift semantic ("arr.delete_at" behavior) belongs
-- to the explicit delete call, not to garbage-collection-triggered
-- cleanup.

-- GC dispatch — lightweight mark triggers. When a relationship is
-- deleted (or its child is swapped in place), mark the row's old child
-- as needs_trace = 1. The heavy lifting — walking the reference graph,
-- deciding what's reachable, and deleting the unreachable — lives in
-- the Lua drain (Db:_drain_needs_trace in fiona.lua), which runs before
-- the outermost atomic() releases its savepoint. That keeps trigger
-- depth constant (mark is a single UPDATE, no cascade) regardless of
-- how deep the resulting cleanup goes.
--
-- On cascade-deletes triggered by the drain's DELETE from hsa, these
-- same triggers fire (via pragma recursive_triggers = on) and add the
-- cascade-orphaned children to the needs_trace worklist. Depth stays
-- bounded because the mark trigger's action is a plain UPDATE with no
-- further cascade.
--
-- The root (hsa_pk = 1) is never a valid needs_trace target — the
-- delete of a relationship whose child is the root can only happen
-- inside root-anchoring restructuring, and the root always trivially
-- reaches itself. Skipping the mark on old.child = 1 keeps the drain
-- from spinning on a no-op seed.
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
when old.child <> 1
begin
	update hsa set needs_trace = 1 where hsa_pk = old.child;
end;

-- Same mark on child-swap. set_hash_element / set_array_element use
-- update rather than delete+insert for content changes, so the update
-- path needs its own trigger. new.child is safe (the row now points at
-- it — trivially reachable via this edge), so we only mark old.child.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child <> 1 and old.child <> new.child
begin
	update hsa set needs_trace = 1 where hsa_pk = old.child;
end;
