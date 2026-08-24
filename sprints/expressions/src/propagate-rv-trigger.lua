--[[
{
	"module":  "propagate-rv-trigger",
	"role":    "Sprint prototype: SQL trigger that propagates a reaping frame's rv to its parent. On DELETE of a frame with a parent, sets parent's rv to whatever the child's rv was (or to null if the child had no rv). Uses the existing bucket-key + refs machinery — rv is stored as a ref from the frame's bucket with key='rv' pointing at any object. Trigger fires BEFORE DELETE so all of the deleting frame's refs are still queryable. Written as a Lua module exposing the trigger SQL as a string constant, plus an `install` helper for tests / demos.",
	"exports": {
		"SQL":     "the CREATE TRIGGER statement as a string",
		"install": "(db) -> installs the trigger on the given SQLite db handle; raises on failure"
	}
}
]]

--[[
# `propagate-rv-trigger`

BEFORE-DELETE trigger on `objects` that propagates rv from a
reaping frame to its parent. Fires whenever a frame is deleted and
has a parent (i.e., excludes the process cap, which has no parent).

## Behavior

For each such delete:

1. **Delete parent's existing rv ref** (if any). This handles both:
   - Child had an rv → we're about to insert a new one; the old
     one has to go first (the `unique (parent, key)` constraint on
     refs would reject a second entry with key='rv').
   - Child had no rv → parent's rv becomes implicitly null
     (absence-based representation).

   The DELETE also fires the standard
   `refs_mark_needs_trace_after_delete` on the old rv value, so
   the value gets swept if nothing else references it.

2. **Insert new rv ref on parent's bucket** — but only if the
   child had an rv. The subquery for the child's rv is empty when
   the child had no bucket or no rv ref, in which case the INSERT
   ... SELECT produces zero rows and does nothing.

## Walking-skeleton limitation

Assumes **parent's bucket already exists.** If the parent hasn't
touched a local yet (`ensure_own_scope` hasn't fired), its bucket
isn't there, and the trigger's INSERT silently no-ops (subquery
returns 0 rows). Under the current handlers this isn't an issue —
by the time a nested frame could reap under a parent, the parent
has already dispatched at least one command and materialized its
bucket. Later work would extend the trigger to materialize the
parent bucket on demand.

## Cap behavior

The `WHEN old.frame_parent IS NOT NULL` guard excludes the cap
(which has no parent). Nothing to propagate to, so the cap-reap
path just falls through without firing this trigger.

## Cross-check with existing triggers

- `frames_child_delete_sets_parent_gc` (rule 3) also fires on child
  delete — it sets parent's gc to 1. This trigger and that one are
  independent; both fire, in unspecified order among BEFORE-triggers
  and cap-exempt guards. Neither depends on the other.
- `frames_delete_requires_no_child` (rule 8) fires FIRST (before
  cascades or this trigger), so we know the deleting frame is a
  leaf.
]]

local M = {}

M.SQL = [[
create trigger frames_child_delete_propagates_rv
before delete on objects
when old.control = 'f'
	and old.frame_parent is not null
begin
	-- Step 1: delete parent's existing rv ref (if any).
	-- Handles both "child had rv, replacing" and "child had no rv,
	-- reset to implicitly null" cases uniformly.
	delete from refs
	where key = 'rv'
	  and parent in (
		select r.child from refs r
		join objects h on h.object_pk = r.child and h.base = 'h'
		where r.parent = old.frame_parent
	);

	-- Step 2: insert new rv ref on parent's bucket if child had one.
	-- Silent no-op if either the child had no rv or the parent had
	-- no bucket (subquery produces zero rows in either case).
	insert into refs (parent, child, key, idx)
	select
		parent_bucket.pk,
		child_rv.value_pk,
		'rv',
		coalesce(
			(select max(idx) from refs where parent = parent_bucket.pk),
			-1
		) + 1
	from (
		select r.child as pk
		from refs r
		join objects h on h.object_pk = r.child and h.base = 'h'
		where r.parent = old.frame_parent
	) as parent_bucket
	cross join (
		select r2.child as value_pk
		from refs r1
		join objects hc on hc.object_pk = r1.child and hc.base = 'h'
		join refs r2 on r2.parent = r1.child and r2.key = 'rv'
		where r1.parent = old.object_pk
	) as child_rv;
end;
]]

--[[
## `install` — apply the trigger to a db handle

Executes the SQL against the given SQLite db handle. Raises on
failure (with the db's own errmsg for diagnostic detail).
]]
function M.install(db)
	local rc = db:exec(M.SQL)

	if rc ~= 0 then
		error('propagate_rv_trigger_install_failed: ' .. db:errmsg())
	end

	return true
end

return M
