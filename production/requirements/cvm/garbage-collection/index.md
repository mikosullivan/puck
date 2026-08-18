# Garbage collection

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm_garbage_collection",
	"role": "CVM's garbage collection — the schema-level mark triggers that populate the needs_trace table as reference-drops happen, plus the Lua-side trace routine that drains marked rows, determines reachability against the uspace view, and either clears the mark (row proven live) or deletes the row (row proven orphaned).",
	"status": "specified — mark triggers landed with the trace-tables sprint; trace-routine implementation lives in a follow-on sprint"
}}
~~~

GC is done by a Lua routine that consumes marks set by the mark triggers (see [Mark triggers](#mark-triggers) below). Each pass drains every row in the `needs_trace` table for the current process, determines each object's reachability with respect to the `uspace` view (defined in [cvm.sql](../sql)), and either deletes the mark (object proven live) or deletes the object (proven orphaned).

## Mark triggers

Every table in the schema that holds a pointer to an `objects` row is a potential source of orphaning — when the pointer changes or the row holding it goes away, the previously-pointed-at object might have just lost its last incoming reference. The schema attaches a mark trigger to each such source. Each trigger does one thing: insert a row into `needs_trace` with `object_pk` set to the row that just lost the incoming pointer, `process_pk` set to `current_process_pk()` via the column's DEFAULT. That's the trigger's entire job — no trace call, no re-entry check, no other logic. Marking is schema-enforced; the actual drain is scheduled by the Lua write layer.

Mark inserts use `ON CONFLICT DO NOTHING` so same-process double-marks silently coalesce. The composite primary key `(process_pk, object_pk)` scopes marks to the running process — a different process dropping a ref to the same object writes a fresh row.

The current inventory:

- **`refs.child`.** `after delete` only — mark `old.child`. `refs.child` is immutable per the schema (see `refs_no_update`), so no update-time mark is needed; rebinding an edge is expressed as delete + insert, and the delete fires the mark. Under the frames-as-objects design, frames are `objects` rows (`primitive = 'f'`) and everything they anchor (locals, and eventually ambers, delegations, the closure capture link) is reachable through the standard `refs` walk. No separate frame-attached tables carrying their own pointers.

**Invariant to maintain:** every column that FKs to `objects(object_pk)` has a mark trigger covering the paths that can change that pointer — DELETE always, UPDATE OF that column when the column is mutable. A schema-scanning test in the walking-skeleton harness (enumerating FKs against `objects(object_pk)` via `PRAGMA foreign_key_list` and asserting each source column has a matching `[set-needs-trace]`-tagged trigger) will keep the inventory honest as the schema grows.

The current schema has eight FK columns pointing at `objects(object_pk)` — two self-references on `objects` (`parent_role`, `owner_role` — plus `parent_frame`, which references `objects` too but doesn't participate in reachability since sub-frame chaining is lifecycle, not object ownership); `refs.parent` and `refs.child`; and four listener columns (`instance_listeners.broadcaster` / `listener`, `class_listeners.class` / `listener`). Only `refs.child` carries a mark trigger. The others don't need one because they either (a) cascade-delete the pointing row — the child that triggered the cascade will have been collected by whatever fired that delete, so any downstream marks belong to that trace, not this one — or (b) are documented as weak-ref lifetime, meaning a listener registration does NOT count as a reachability edge (the two parties can be collected without unregistering; the FK cascade then cleans up the registration row on its own).

Ownership of a bucket or stack no longer needs its own column-tracked mark trigger — see [ownership](https://www.puck.uno/requirements/cvm/ownership). Owner→collection is a normal `refs` row, so when the owner is deleted the ref cascades and the standard `refs_mark_needs_trace_after_delete` fires on the collection. One machinery, one mark trigger, everywhere.

## Who calls the trace

The trace is invoked from within the Caspian implementation. Nothing in the database itself triggers a trace. The mark triggers insert into `needs_trace` and stop; the trace only runs when Caspian's Lua-side write layer explicitly invokes it.

Where in the Caspian implementation those invocations happen is out of scope for this document. This document specifies what the trace DOES once invoked, not where it gets called from.

## Trace state tables

The trace routine uses three tables — one persistent, two temp — to record what it's doing:

- **`needs_trace(process_pk, object_pk)`** — persistent, main schema, real FKs. The worklist. Populated by the mark triggers; drained by the outer loop. Persistent so a crash mid-run doesn't lose pending marks.
- **`traces(trace_pk, object_pk, done)`** — temp, per-connection. One row per trace run. `trace_pk` is a monotonic integer PK (AUTOINCREMENT). `object_pk` is the seed (the candidate the trace is proving live or orphaned). `done` is a 0/1 flag flipped once the trace terminates.
- **`in_trace(trace_pk, object_pk)`** — temp, per-connection. Composite PK on `(trace_pk, object_pk)`. Per-trace membership: one row per (trace, object) pair records that `object` was visited during `trace`.

The temp / persistent split matches the design intent — marks must survive restart; trace scratch doesn't. See [preflight.sql](../sql) for the temp-table declarations that recreate `traces` and `in_trace` on every connection open.

## needs_trace loop

The trace's outer loop. Each iteration picks one candidate from `needs_trace` scoped to the current process, runs a per-suspect backward-reachability trace against it (the inner loop), and disposes of the outcome. The loop ends when the process's `needs_trace` rows are all drained.

~~~lua
while true do
	-- Pick one candidate for the current process. Any row works;
	-- iteration order isn't load-bearing for correctness.
	local candidate = first(db,
		"select object_pk from needs_trace "
		.. "where process_pk = current_process_pk() limit 1")

	if candidate == nil then break end

	-- Kick off a fresh trace against this candidate.
	local trace_pk = first(db,
		"insert into traces (object_pk) values (?) returning trace_pk",
		candidate.object_pk).trace_pk

	-- Run the inner loop (see below). Returns 'live' or 'orphaned'.
	local outcome = run_trace(trace_pk, candidate.object_pk)

	if outcome == 'live' then
		-- Candidate is still reachable. Drop its mark; leave the
		-- object itself alone.
		db:exec("delete from needs_trace "
			.. "where process_pk = current_process_pk() "
			.. "and object_pk = '" .. candidate.object_pk .. "'")
	else
		-- Candidate is orphaned. Every row visited during this
		-- trace (including the candidate) is also orphaned — the
		-- closure is a disconnected island. Delete all of them.
		db:exec("delete from objects where object_pk in ("
			.. "select object_pk from in_trace "
			.. "where trace_pk = " .. trace_pk .. ")")
		-- The mark rows for these objects go with them via
		-- `needs_trace.object_pk ON DELETE CASCADE`.
	end

	-- Whichever branch we took, this trace run is done.
	db:exec("update traces set done = 1 where trace_pk = " .. trace_pk)
end
~~~

**The cascade does the mark cleanup.** When an orphaned object is DELETEd, any `needs_trace` rows referencing it — for any process — go with it (the `object_pk` FK cascades). Any `in_trace` rows referencing it (in any trace) also go via the equivalent temp cascade. The outer loop doesn't have to hand-delete marks.

**Any trace whose seed was an object we just deleted also gets swept.** In the current schema `traces.object_pk` also cascades on `objects` DELETE (via `objects_delete_cascades_scratch`, the temp cascade in preflight.sql). So if the outer loop's next iteration finds the same island through a different mark, it starts a fresh trace — no re-entry concerns.

## in_trace loop

The trace's inner loop — Bacon-Rajan-style per-suspect backward reachability. Walk UP the ref graph starting from the seed, growing the visited set one hop of parents at a time, until either a `uspace` anchor is hit (candidate is live) or the walk stops growing (candidate is orphaned).

The inner loop's state — which objects have been visited by this trace — lives entirely in `in_trace` rows keyed by the caller's `trace_pk`. Multiple concurrent traces (which the design doesn't currently need but the schema supports) can coexist without interfering.

### Seed

The first thing the inner loop does is record the candidate in `in_trace`:

~~~sql
insert into in_trace (trace_pk, object_pk) values (?, ?);
~~~

That row is the starting point of the visited set.

### Expand

The inner loop's core step: every object that references any row currently in `in_trace` (for this trace) gets added to `in_trace`. Grow the visited set by one hop of parents.

Concretely — find every row in `refs` whose `child` is currently in `in_trace` for this trace, and insert those rows' `parent` objects into `in_trace`:

~~~sql
insert or ignore into in_trace (trace_pk, object_pk)
select ?, refs.parent
from refs
join in_trace on in_trace.object_pk = refs.child
where in_trace.trace_pk = ?;
~~~

`INSERT OR IGNORE` skips rows already in `in_trace` for this trace — the composite PK guards it. That's both the double-count guard and cycle safety (a cycle collapses when the walk revisits an already-visited row).

Each expansion adds one hop of parents. The loop keeps expanding until a termination condition fires.

### Trace termination

The inner loop ends the moment either of two conditions holds. The outcome for the candidate depends on which one fired.

#### Uspace hit — candidate is alive

If any row currently in `in_trace` for this trace appears in the `uspace` view, the candidate has a path to a uspace anchor. Detect with:

~~~sql
select 1 from uspace
where object_pk in (
	select object_pk from in_trace where trace_pk = ?
)
limit 1;
~~~

If this returns a row, terminate the inner loop with a **live** outcome.

**Only the candidate is proven live.** The other rows in `in_trace` are just fellow-travelers along the closure — some of them may be genuinely orphaned, some may be reachable through different paths. The trace doesn't classify them; they'll get their own traces on later marks (or already have live ones). Only the seed's mark is dropped.

#### No growth — candidate is orphaned

If the last `expand` step affected zero rows, the visited set is a closed subgraph — every ancestor reachable from the candidate has been visited and none of them is (or reaches) a uspace anchor. The candidate is genuinely orphaned; so is every other row in `in_trace` for this trace (they're all in the same disconnected island). Detect via the changes-count returned by the INSERT:

~~~lua
if db:changes() == 0 then
	-- terminate the inner loop with an orphaned outcome
end
~~~

**The whole `in_trace` set is a proven-orphan subgraph.** The outer loop reads all of them and deletes them together. This is the case where the outer loop's `delete from objects where object_pk in (...)` sweeps more than just the seed.

## Cleanup

Cleanup happens at the outer loop's disposition step. Two paths:

- **Live outcome** — drop the mark row (`delete from needs_trace where process_pk = current_process_pk() and object_pk = seed`). Nothing else changes.
- **Orphaned outcome** — delete every object in `in_trace` for the trace. Cascades handle the rest: `needs_trace.object_pk ON DELETE CASCADE` sweeps the marks; `refs.parent ON DELETE CASCADE` sweeps outgoing refs; the ref-delete trigger inserts fresh marks for whatever those refs pointed AT (that's how the worklist grows during a sweep and drives subsequent iterations of the outer loop).

The `on_close` / on-collection callback path — user-code that runs when a specific object is being collected — attaches at the "delete every object in `in_trace`" step. Ordering, cascades within the callback chain, and callback error handling belong to a later sprint that specifies the callback contract itself.

The trace's own `traces` and `in_trace` rows go away when the outer loop advances (see the `update traces set done = 1` step and any subsequent `delete from traces where done = 1` housekeeping — the schema permits either sync deletion or lazy accumulation, whichever the implementer prefers).
