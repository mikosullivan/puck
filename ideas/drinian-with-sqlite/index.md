# Drinian with SQLite

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite",
	"role": "brainstorm space for using SQLite directly as Drinian's storage layer — a purpose-built schema shaped around Drinian's fields, not layered on top of Fiona. Companion to ideas/fiona-as-drinian/ which explores routing through Fiona as an intermediate.",
	"status": "sketching 2026-08-07 — table shapes proposed; not committed"
}}
~~~

An alternative to `ideas/fiona-as-drinian/`. Instead of routing Drinian through Fiona's generic object-store schema, model each Drinian field as a table directly. Shape the schema around Drinian's needs.

## Design principles

1. **Everything is an object; ID space is shared.** `objects` is the identity table for the whole runtime. Things that used to want their own top-level namespace (srcs, asts, roles, refs, primitives) become sidecars — a table keyed by `objects(id)` carrying whatever extra columns the class needs. One ID scheme, one autoincrement.
2. **Cascade delete for GC.** `on delete cascade` on child tables so orphan removal propagates automatically — no separate GC pass at the app level.
3. **Comprehensive constraints.** `check`, `foreign key`, `unique` wherever an invariant can be expressed at schema level. Push validation into the DB.
4. **IDs as integers.** Regular SQLite autoincrement. No shared string-counter table; the string-integer convention from Drinian's requirements spec was mostly a serialization / snapshot detail that autoincrement handles natively.
5. **Lowercase SQL.** Project convention.

## Tables

The full schema lives in [schema.md](https://www.puck.uno/ideas/drinian-with-sqlite/schema) — pulled out so the tables can be read (and eventually run through `sqlite3`) without scrolling past the surrounding design prose.

Summary of what's there:

- **`objects`** — the identity table. `integer primary key autoincrement`. Every live thing has a row here. Includes `role_pk`, `src_pk` / `src_line`, the `handle_key` escape hatch for native resources, and the primitive slot (`pr_type` + `pr_val`) — non-null for primitive-class instances (strings, numbers, booleans, null); null for everything else. Both `pr_*` fields are immutable after insert; per-`pr_type` shape checks enforce that `pr_val` is the right SQLite type for its kind.
- **`buckets`** — per-object key-value hash. Values are object IDs. Primitives get their own object row via `pr_type` + `pr_val`, not inlined here.
- **`platters`** — per-object ordered stack of platters.

**Sidecar tables** keyed by `objects(id)`, one per class family that needs extra columns:

- **`refs`** — reference-class objects (variables, hash-elements). Row's id = ref-object's id; target_pk = current target.
- **`roles`** — role-class objects. Self-referencing tree with materialized `path`, plus the Trivet-style locks (`root_locked` / `moves_prohibited` / `allow_new_children`).
- **`srcs`** — src-registry-class objects (`kind` + `path`).
- **`asts`** — AST-class objects (`src_pk` + CaspM body as JSON).

**Runtime state tables:**

- **`call_stack`** — frames + in-flight exceptions, positional array.
- **`frame_locals`** — variable bindings per frame, cascade-drop on frame pop.
- **`gc_errors`** — `on_close` failure log.
- **`mutations`** — full mutation history (opt-in) enabling time-travel debugging.

Reverse indexes on `refs.target_pk`, `buckets.value_object_pk`, `platters.class_pk`, and `objects.role_pk` — the "custom-schema wins" story (see § Features below) leans on these for bidirectional graph traversal.

## GC

Adapted from Fiona's mark-and-drain model (`mikosullivan/fiona/src/fiona.sql`), applied to our `refs` table. The refs table carries three GC-scratch columns — `needs_trace`, `in_trace`, `del` — that route rows through a drain. Normal state: all three null.

### The states a ref can be in

- **Normal.** All three null.
- **Marked candidate.** `needs_trace = 1` — something changed that might have orphaned this ref's target; the drain needs to check.
- **Under evaluation.** `in_trace = <positive counter>` — the drain has picked it up and is walking outgoing edges to determine reachability. Counter preserves trace order.
- **Doomed.** `del = 1` — the drain determined the ref no longer points at reachable state; queued for removal.

Splitting `del` out from `in_trace` keeps each column's meaning crisp — `in_trace` genuinely means "being examined for liveness right now"; a doomed row isn't being examined, it's already decided.

### Drain flow

1. **Marking.** When a ref changes (delete, target repointed), mark triggers set `needs_trace = 1` on affected rows.
2. **Promotion.** The drain iterates `needs_trace = 1` rows, sets `in_trace = <next counter>`, clears `needs_trace`.
3. **Trace.** For each `in_trace` row, walk outgoing edges to check reachability from uspace roots. Reachable → clear `in_trace` (back to normal). Not reachable → clear `in_trace`, set `del = 1`.
4. **Cleanup.** `delete from refs where del = 1`. FK cascade fires on the objects the doomed refs were rows of, propagating removal through buckets, platters, other refs. Cascade fires more mark triggers, feeding more work into the drain.

The drain's "what's in-flight this round?" query:

~~~sql
select id from refs where del or in_trace is not null;
~~~

Bare `where del` catches only `del = 1` rows (SQLite truthiness: `del` is either 1 or null, and only 1 is truthy). `in_trace is not null` catches evaluation. Both branches together = "everything still in this round."

### Auto-mark during GC — the race-solver

While the drain's callback phase is active, any newly-inserted ref gets `del = 1` automatically:

~~~sql
create temp trigger refs_auto_mark_during_gc
after insert on refs
when exists (select 1 from process where key = 'in_gc_callback_phase')
begin
    update refs set del = 1 where id = new.id;
end;
~~~

This is what makes "new link to a dying object during GC" a non-problem. Without it, code trying to link to a currently-being-collected object mid-sweep creates a live ref that keeps the doomed object alive, and the invariants break. With it, the new ref inherits the sweep — it's born marked, doesn't survive the round, no engine-side synchronization required against GC.

Cascade delete under this model integrates naturally: a doomed ref's cleanup fires the FK cascade on its object row, which cascades through `buckets`, `platters`, and other refs that were held by that object. Each cascade delete generates more mark events, and the drain keeps working until no more marks remain.

### On_close hooks

Object deletion (via cleanup's cascade chain) fires `after delete on objects` triggers that call Lua UDFs. The UDF runs the object's `on_close` method (if any), records any failures to `gc_errors`, and continues — one bad handler doesn't break GC for other objects. Same guarantee Drinian's requirements spec calls out at [drinian § Object lifecycle](https://www.puck.uno/requirements/drinian/objects#object-lifecycle).

## Handle storage

The blocker for Fiona-as-Drinian — objects holding native handles (file descriptors, sockets, coroutines, C userdata) — is spec'd here via `objects.handle_key`. It's a nullable text column: for objects that carry a native handle, the column holds a key that resolves through an engine-side Lua registry to the actual handle. SQLite doesn't inspect the handle; it just keeps the row alive so the handle stays reachable.

That's the escape hatch — everything else is normal SQL, and the handle mechanism only pays cost for the specific objects that need it.

## Trivet-style tree enforcement on `roles`

The `roles` table carries `root_locked`, `moves_prohibited`, `allow_new_children` — boolean columns, one-way mutable, matching the property-idiom design from `ideas/lua/lua-trivet/#tree-manager`. Enforcement lives in triggers:

- `before update on roles` refuses `parent_pk` change when `moves_prohibited = 1`.
- `before insert on roles` refuses when the target parent has `allow_new_children = 0`.
- `before update on roles` refuses toggling any lock from locked → unlocked.
- `before_attach` / `before_detach` hooks fire via triggers calling Lua UDFs.

The `audit` method translates to a Lua-callable stored procedure that walks the roles table checking for cycles, orphans, and disagreements between `parent_pk` and the containment chain.

## Features the custom schema enables

The point of doing a custom schema (vs. layering on Fiona) is that we can shape SQLite around Drinian's specific needs and pick up features that a generic object store can't. Concrete wins:

### Bidirectional lookup on every relationship

The reference graph is normally a walk: given a target, walking backward through the `references` hash is O(N). With an index on both columns of every reference-carrying table, it's O(log N) both directions:

- **`refs(target_pk)` index** — "who references this object?" — orphan detection, cycle checks, uspace reachability.
- **`buckets(value_object_pk)` index** — "who holds this in their bucket?" — finds every parent hash containing this value.
- **`platters(class_pk)` index** — "all instances of class X" — introspection queries in one shot.
- **`objects(role_pk)` index** — "everything owned by user role" — cross-role audit becomes a filter.

Every reachability question — the heart of GC and debugging — becomes a set operation instead of a graph walk.

### Materialized ancestor paths on the roles tree

`roles.path` stores `.1.5.7.` for a role two hops under the chain 1 → 5 → 7. Maintained by triggers. Then:

- **Ancestor check.** `where '.1.5.' like Y.path || '%'` — one indexed LIKE.
- **All descendants of X.** `where path like X.path || X.id || '.%'` — indexed prefix scan.
- **Depth.** `length(path) - length(replace(path, '.', ''))` — no walk needed.

Replaces walking parent pointers with prefix-indexed lookups.

### Time-travel debugging via the mutations log

Triggers on every table push a row to `mutations` for every insert / update / delete. Then:

- **"What did state look like at time T?"** — apply the log up to T against a snapshot.
- **"What changed between A and B?"** — `select * from mutations where seq between A and B`.
- **"Who wrote to this row?"** — filter by `table_name` + `row_pk`.
- **Replay a bug** — restore from snapshot, replay mutations until the bug reproduces, inspect.

The log is opt-in — engines that want the overhead install the triggers; engines that don't skip them.

### Rich introspection as SQL

Every engine invariant is a query. Every runtime metric is a `select count`. No new engine code, no instrumentation pass — the schema IS the observability surface:

~~~sql
-- Every currently-alive closure
select o.id from objects o
join platters s on s.object_pk = o.id
where s.class_pk = (select id from objects where /* the closure class */);

-- Frames with iterator state
select position, iterator_state from call_stack where iterator_state is not null;

-- Roles with more children than allowed by convention
select parent_pk, count(*) from roles
where parent_pk is not null
group by parent_pk
having count(*) > 100;

-- The full ownership tree under a specific role
select * from objects where role_pk in (
    select id from roles where path like (
        select path || id || '.%' from roles where id = ?
    )
);
~~~

Anyone with a SQLite client can inspect any live runtime. No debugging protocol to design.

### The database IS the snapshot

Because Drinian's state lives entirely in SQLite, snapshots are trivial: the database file itself is the snapshot. No JSON export, no format spec, no `to_json` on every class, no reserialization pass at snapshot time.

To snapshot mid-execution: `.backup` the SQLite file (or copy it while WAL mode holds a consistent read). To revive: open the file. The file IS the state; the runtime picks up where it left off (once the engine's Lua-side handle registry is rebuilt from the `handle_key` slots, for objects that carry native resources).

That removes a category of design work that plagues the in-memory model — the snapshot / revive protocol Drinian's requirements spec calls out as post-V1 (`requirements/drinian/#future-snapshot-and-revive-post-v1-0`). Under SQLite, it's free.

### Big Processes

Long-term Caspian goal: processes that outlive their host. A Caspian program pauses across a blocking call (HTTP promise, agent yield, human approval), releases its host process entirely, and revives — potentially days later, potentially on a different host — with state exactly where it left off. See [requirements/drinian/#future-snapshot-and-revive-post-v1-0](https://www.puck.uno/requirements/drinian/#future-snapshot-and-revive-post-v1-0) for the aspirational shape.

Under SQLite Drinian this comes essentially for free:

- **Pause = close the database.** The file IS the process state. No serialization pass.
- **Revive = open the database.** Attach to the file, rebuild the Lua-side handle registry for any objects with `handle_key` set, resume execution.
- **Hosts are interchangeable.** Any host that can open SQLite (i.e., every host worth caring about) can revive any snapshot. No host-specific serialization.
- **Duration is unbounded.** A file paused today can revive next year. Filesystem-lifetime, not memory-lifetime.
- **Size is unbounded.** SQLite scales to terabytes. A Big Process holding accumulated state — a multi-year conversation with a user, a long-running workflow, an agent's cumulative memory — fits.
- **Coexistence is trivial.** Each Big Process is one SQLite file. Ten thousand paused processes = ten thousand small files on disk. No shared runtime, no memory pressure, no scheduling contention.
- **Interruption is safe.** WAL mode means a host crashing mid-pause doesn't corrupt state; the process revives from the last committed transaction.
- **Migration is trivial.** Copy the file to another host. Revive there. Same process.

Big Processes were Drinian's original vision (the whole post-V1 snapshot / revive story). Under SQLite the mechanics collapse to open / close / copy. Nothing exotic left to design.

### Full-process rollback via transactions

Because the entire Drinian state lives in one SQLite database, a SQL transaction spans everything — every object, every frame, every role, every ref. When the transaction rolls back, the whole process reverts to the state it had at `BEGIN`. No undo tracking. No shadow-state machinery. SQLite gives it to us free.

At the Caspian level this becomes a natural block construct:

~~~caspian
transaction as $transaction
	# do stuff — mutate state freely
	# decide you don't like it — abort
	$transaction.abort
end

# back at state before the transaction fired
~~~

Or implicit rollback via exception:

~~~caspian
transaction
	&risky_operation
	# if &risky_operation raises, the block exits abnormally,
	# the transaction implicitly rolls back, state is restored
end
~~~

Everything the block did — objects created, roles added, variables mutated, on_close hooks fired, GC events — reverts atomically. What was speculation is un-happened.

Use cases this unlocks:

- **Try-then-decide.** Explore a computation, look at the results, keep or discard.
- **What-if analysis.** Fork a Big Process's state via a transaction, run alternatives, compare, pick one, commit or roll back.
- **Undo for interactive tools.** Every user action wraps in a transaction; explicit undo is a rollback of the last N.
- **Test isolation.** Each test wraps in a rollback-only transaction. Test state can't leak into siblings.
- **Speculative execution.** Try an operation; see if it violates any invariants (via the schema's `check` constraints); roll back if it does.
- **Nested savepoints.** SQLite supports `savepoint` — arbitrary rollback checkpoints inside a transaction. `$transaction.save 'label' ... $transaction.rollback_to 'label'` maps to `savepoint` / `rollback to savepoint` directly.
- **Sanitizing on abnormal exit.** Wrap the whole main script in a transaction; commit on graceful exit; roll back on catastrophic failure. The database never sees a half-finished mutation.

This is one of those features that would be genuinely hard to build against an in-memory hash — you'd need shadow-state tracking or an undo log that the engine maintains itself. Under SQLite, it's `begin` / `rollback`. First-class support for "just kidding, back that out" as a Caspian language primitive.

### Snapshot diffing

Two SQLite snapshots of the same runtime can be diffed at the row level:

~~~sql
attach 'before.sqlite' as before;
select * from objects
except select * from before.objects;
-- rows in current that weren't in before
~~~

Attach two snapshots side-by-side and answer "what did this program actually do?" in one query. Useful for reproducing bugs against a known-good snapshot.

### Debugger is a SQL client

No custom debugger protocol. Any SQLite tool — CLI, DB Browser, custom Orlando pages — is a valid debugger. Reads are just queries; the runtime doesn't have to expose new endpoints for each new inspector.

### JSON queries into CaspM

CaspM stored as JSON in `asts.body` isn't opaque under SQLite — the JSON1 functions can query into it:

~~~sql
-- Every AST whose top-level call is `puts`
select id from asts where json_extract(body, '$.head.bwc') = 'puts';

-- All method bodies referencing a specific variable name
select id from asts where json_extract(body, '$..name') = 'user';
~~~

Not as clean as normalizing AST nodes into rows, but no per-node overhead and still queryable.

### Full-text search across the runtime

SQLite's FTS5 extension can index text columns. Then:

- **Search error messages** across `gc_errors.message`.
- **Search source paths** across `srcs.path`.
- **Search JSON-shaped columns** like `asts.body` or `call_stack.iterator_state` for keywords.

One extension, one virtual table, and the whole runtime becomes searchable.

### Constraint-based structural guarantees

Every invariant we expressed as a `check` constraint or foreign key becomes DB-enforced. Random or generated states either satisfy the schema (and are valid) or get rejected on write. SQLite itself is a property-based test harness for our runtime model.

### Event-driven propagation via Lua UDFs

Triggers can call Lua UDFs. That turns Drinian from a passive state store into a reactive system: state changes fire callbacks that update dependent state, invalidate caches, or dispatch Caspian-level logic. The engine's "next state" logic isn't imperative code that runs the transition — it's the DB itself reacting to the write.

Concrete cases:

- **Automatic path maintenance.** `after update on roles` where `parent_pk` changed fires a UDF that recomputes `roles.path` on the row (and cascade-updates paths on all its descendants). No app code has to remember to keep `path` in sync.
- **Reactive cache invalidation.** When an object's role changes, a UDF invalidates cached permission grants that referenced the old role. Cross-table dependencies expressed as triggers.
- **Caspian-level callbacks.** When an object of a specific class is created, a UDF dispatches to a registered Caspian method. `after insert on platters` filtered on `class_pk = <SomeClass>` fires `SomeClass:on_created` inside the engine.
- **Derived-view maintenance.** Materialized aggregates — role-descendant counts, active-frames histograms, orphan-candidate lists — get recomputed reactively via UDF triggers on the relevant tables.
- **Streaming observability.** Every mutation emits an event that a UDF hands to whatever subscribers are registered — inspectors, debuggers, tracing tools, external tools listening over pipes.

The shape change is fundamental: **the runtime becomes event-driven at the storage layer.** Every field mutation is a hook point. Adding a new derivation is one `create trigger` plus one UDF registration; no engine dispatch path needs updating. And because triggers fire inside the transaction, propagation is atomic — the derived state is consistent with the base state at every observation point.

## Trade-offs vs. in-memory hash

**Wins:**
- **Persistence for free.** SQLite storage is the file. Snapshot = fsync. Revive = open the file.
- **Constraints enforced at the DB level.** Foreign keys, checks, uniques catch bugs at write time regardless of which code path wrote.
- **Rich queries.** "Find all objects owned by user role" is a `where role_pk = X` — no reachability walk.
- **Handle isolation.** Native handles live in the `handle_key` escape hatch, not scattered across the in-memory graph.

**Costs:**
- **Per-op overhead.** Every runtime read/write is a SQL statement. Hot-path dispatch pays microseconds per op vs. nanoseconds for Lua-table access. Realistically requires an in-memory cache layer for hot state, syncing to SQLite at GC / snapshot / boundary points.
- **Value overhead.** Every primitive still needs an `objects` row + a `primitive_values` row + typically a stack platter. Storage cost per value is O(3 rows) minimum.
- **CaspM tree size.** ASTs stored as JSON blobs are compact but opaque to SQL. Storing them as normalized nested-collection graphs (like Fiona would) is queryable but expensive.
- **Schema evolution.** Any change to Drinian's shape requires a SQLite migration. In-memory hash just changes.

## Open questions

- **Concurrency model.** Caspian is single-threaded, but if we want to snapshot mid-execution or read from an inspector, we need at least a read consistency story. SQLite's WAL mode handles this fine but adds cost.
- **Where the app-level cache lives.** Every "hot state" implementation would look different depending on whether the engine caches at the row level, the object level, the frame level, or coarser.
