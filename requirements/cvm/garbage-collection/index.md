# Garbage collection

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm_garbage_collection",
	"role": "CVM's garbage collection — the schema-level mark triggers that set needs_trace = 1 as reference-drops happen, plus the Lua-side trace routine that drains marked rows, determines reachability against the uspace view, and either clears the mark (row proven live) or deletes the row (row proven orphaned).",
	"status": "in progress — mark trigger inventory + outer/inner loop skeleton drafted; drain-loop details and cleanup still to come"
}}
~~~

GC is done by a Lua routine that consumes marks set by the mark triggers (see [Mark triggers](#mark-triggers) below). Each pass drains every row where `needs_trace = 1`, determines its reachability with respect to the `uspace` view (defined in [cvm.sql](../sql)), and either clears the row's mark (if it's still alive) or deletes it (if it's genuinely orphaned).

## Mark triggers

Every table in the schema that holds a pointer to an `objects` row is a potential source of orphaning — when the pointer changes or the row holding it goes away, the previously-pointed-at object might have just lost its last incoming reference. The schema attaches a mark trigger to each such source. Each trigger does one thing: set `needs_trace = 1` on the row that just lost the incoming pointer. That's the trigger's entire job — no trace call, no re-entry check, no other logic. Marking is schema-enforced; the actual drain is scheduled by the Lua write layer.

Mark triggers are idempotent: setting `needs_trace = 1` on a row that's already marked is a harmless no-op. Each trigger in the schema is annotated with a `[set-needs-trace]` comment prefix so `grep [set-needs-trace] src/engine/cvm/schema.sql` enumerates the whole inventory.

The current inventory:

- **`refs.child`.** `after delete` only — mark `old.child`. `refs.child` is immutable per the schema (see `refs_no_update`), so no update-time mark is needed; rebinding an edge is expressed as delete + insert, and the delete fires the mark. Under the frames-as-objects design, frames are `objects` rows (`primitive = 'f'`) and everything they anchor (locals, and eventually ambers, delegations, the closure capture link) is reachable through the standard `refs` walk. No separate frame-attached tables carrying their own pointers.

**Invariant to maintain:** every column that FKs to `objects(object_pk)` has a mark trigger covering the paths that can change that pointer — DELETE always, UPDATE OF that column when the column is mutable. A schema-scanning test in the walking-skeleton harness (enumerating FKs against `objects(object_pk)` via `PRAGMA foreign_key_list` and asserting each source column has a matching `[set-needs-trace]`-tagged trigger) will keep the inventory honest as the schema grows.

The current schema has eight FK columns pointing at `objects(object_pk)` — two self-references on `objects` (`role_parent`, `owner_role` — plus `parent_frame`, which references `objects` too but doesn't participate in reachability since sub-frame chaining is lifecycle, not object ownership); `refs.parent` and `refs.child`; and four listener columns (`instance_listeners.broadcaster` / `listener`, `class_listeners.class` / `listener`). Only `refs.child` carries a mark trigger. The others don't need one because they either (a) cascade-delete the pointing row — the child that triggered the cascade will have been collected by whatever fired that delete, so any downstream marks belong to that trace, not this one — or (b) are documented as weak-ref lifetime, meaning a listener registration does NOT count as a reachability edge (the two parties can be collected without unregistering; the FK cascade then cleans up the registration row on its own).

Ownership of a bucket or stack no longer needs its own column-tracked mark trigger — see [ownership](https://www.puck.uno/requirements/cvm/ownership). Owner→collection is a normal `refs` row, so when the owner is deleted the ref cascades and the standard `refs_mark_needs_trace_after_delete` fires on the collection. One machinery, one mark trigger, everywhere.

## Who calls the trace

The trace is invoked from within the Caspian implementation. Nothing in the database itself triggers a trace. The mark triggers set `needs_trace = 1` and stop; the trace only runs when Caspian's Lua-side write layer explicitly invokes it.

Where in the Caspian implementation those invocations happen is out of scope for this document. This document specifies what the trace DOES once invoked, not where it gets called from.

## needs_trace loop

The trace's outer loop. Each iteration picks one candidate object (a row where `needs_trace = 1`), processes it, and loops back for the next. The loop ends when no marks remain.

Stub — details of the iteration land here as we work through them.

## in_trace loop

The trace's inner loop, run once per candidate picked by the outer loop. It uses the `in_trace` column to track which rows are being examined for the current candidate's reachability, growing the set outward until either a uspace anchor is reached (candidate is alive) or the set stops growing (candidate is orphaned).

### Seed

The first thing the inner loop does is mark the candidate's `in_trace` column with `1`:

~~~sql
update objects set in_trace = 1 where object_pk = ?;
~~~

That row is now the starting point of the visited set. Subsequent expansion steps will pull additional rows into the set with successive `in_trace` values (`2`, `3`, ...) as the walk moves outward.

### Expand

The inner loop's core step: every object that references any row currently marked `in_trace` also becomes `in_trace`. Grow the visited set by one hop of parents.

Concretely — find every row in `refs` whose `child` is currently in the `in_trace` set, and mark those rows' `parent` objects with the next `in_trace` counter value:

~~~sql
update objects set in_trace = <next_counter>
where in_trace is null
    and object_pk in (
        select parent from refs
        where child in (select object_pk from objects where in_trace is not null)
    );
~~~

The `in_trace is null` guard prevents re-marking rows already in the visited set — that both stops us from double-counting and gives cycle safety for free (a cycle collapses when the walk revisits an already-marked row).

**The counter is incremented per iteration.** The seed sets `in_trace = 1`; the first expansion uses `2`; the next uses `3`; and so on. Each visited row's `in_trace` value records which iteration first pulled it into the set — hop 1 from the candidate is `2`, hop 2 is `3`, etc. That ordering isn't load-bearing for reachability (any distinct-non-null marker would suffice for cycle safety), but it makes snapshots of a mid-trace state legible: an inspector reading `in_trace = 5` on a row knows that row was reached at the fifth hop out from the candidate.

**The increment happens in the Lua layer, not in SQL.** The trace routine is Lua code (see [Who calls the trace](#who-calls-the-trace)) and holds the counter as a local variable that starts at `1` at seed time and increments before each expansion. The value is passed into the UPDATE as a bind parameter. SQL-side alternatives (a `(select max(in_trace) from objects) + 1` subquery, or a sequence row somewhere) would work but add cost for no benefit — the Lua routine already exists, already owns the trace's state, and Lua-local increments are free.

Each expansion adds one hop of parents to the visited set. The loop keeps expanding until a termination condition fires.

### Trace termination

The inner loop ends the moment either of two conditions holds. The outcome for the candidate depends on which one fired. Order of the checks doesn't matter — both are cheap (a single view lookup on one side, a Lua-side integer comparison on the other).

#### Uspace hit — candidate is alive

If any row currently marked `in_trace` appears in the `uspace` view, the candidate has a path to a uspace anchor. Detect with:

~~~sql
select 1 from uspace
where object_pk in (select object_pk from objects where in_trace is not null)
limit 1;
~~~

If this returns a row, terminate the inner loop with a live outcome. Cleanup follows.

#### No growth — candidate is orphaned

If the last `expand` step affected zero rows, the visited set is a closed subgraph — every ancestor reachable from the candidate has been visited and none of them is (or reaches) a uspace anchor. The candidate is genuinely orphaned; so is every other row currently marked `in_trace` (they're all in the same disconnected island). Detect via the changes-count returned by the UPDATE:

~~~lua
if db:changes() == 0 then
    -- terminate the inner loop with an orphaned outcome
end
~~~

The actual collection mechanism that fires once we've established this outcome — deleting the orphaned rows, running `on_close` hooks, handling cascades, ordering the cleanup — is deferred. This subsection only spec's the detection.

Stub — cleanup lands here as we work through it.
