# Features the custom schema enables

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_features",
	"role": "concrete wins the SQLite-based Drinian schema unlocks that a generic object store or in-memory hash cannot: bidirectional lookups, materialized ancestor paths, rich introspection via SQL, snapshot-as-database, Big Processes, full-process rollback, snapshot diffing, SQL-as-debugger-protocol, JSON queries into CaspM, FTS5, schema-enforced invariants, and event-driven propagation via UDFs",
	"status": "extracted from ideas/drinian-with-sqlite/index.md § Features the custom schema enables per issue #1459"
}}
~~~

The point of doing a custom schema (vs. layering on Fiona) is that we can shape SQLite around Drinian's specific needs and pick up features that a generic object store can't. Concrete wins:

## Bidirectional lookup on every relationship

The reference graph is normally a walk: given a target, walking backward through the `references` hash is O(N). With an index on both columns of every reference-carrying table, it's O(log N) both directions:

- **`refs(target_pk)` index** — "who references this object?" — orphan detection, cycle checks, uspace reachability.
- **`buckets(value_object_pk)` index** — "who holds this in their bucket?" — finds every parent hash containing this value.
- **`platters(class_pk)` index** — "all instances of class X" — introspection queries in one shot.
- **`objects(role_pk)` index** — "everything owned by user role" — cross-role audit becomes a filter.

Every reachability question — the heart of GC and debugging — becomes a set operation instead of a graph walk.

## Materialized ancestor paths on the roles tree

`roles.path` stores `.1.5.7.` for a role two hops under the chain 1 → 5 → 7. Maintained by triggers. Then:

- **Ancestor check.** `where '.1.5.' like Y.path || '%'` — one indexed LIKE.
- **All descendants of X.** `where path like X.path || X.id || '.%'` — indexed prefix scan.
- **Depth.** `length(path) - length(replace(path, '.', ''))` — no walk needed.

Replaces walking parent pointers with prefix-indexed lookups.

## Rich introspection as SQL

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

## The database IS the snapshot

Because Drinian's state lives entirely in SQLite, snapshots are trivial: the database file itself is the snapshot. No JSON export, no format spec, no `to_json` on every class, no reserialization pass at snapshot time.

To snapshot mid-execution: `.backup` the SQLite file (or copy it while WAL mode holds a consistent read). To revive: open the file. The file IS the state; the runtime picks up where it left off (once the engine's Lua-side handle registry is rebuilt from the `handle_key` slots, for objects that carry native resources).

That removes a category of design work that plagues the in-memory model — the snapshot / revive protocol Drinian's requirements spec calls out as post-V1 (`requirements/drinian/#future-snapshot-and-revive-post-v1-0`). Under SQLite, it's free.

## Big Processes

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

## Transferring consciousness

Moving a running Caspian process from one host to another is `cp`. The .sqlite file is the entire mind — every object, every reference, every frame, every variable binding, every role grant, every pending exception, every in-flight iterator. Copy the file, open it on the other side, resume. The process wakes up on the new substrate with continuity: it has no way to notice the switch, because nothing in its own state records where it was running.

That's not a metaphor stretched thin. It's what falls out of "all state in one file." Traditional runtimes distribute their state across host memory (the interpreter's structures), OS resources (file descriptors, sockets, threads), and language-level heap (whatever the program built up). Migrating a process means designing a serialization protocol for each of those layers, freezing atomically, transporting, and re-materializing on the other side. Every runtime attempts it eventually; none makes it easy. Under Drinian, the layers collapse — there's only the file.

What that unlocks:

- **Migrate for infrastructure reasons.** Drain a host for maintenance? Copy its live processes to another host. No process notices.
- **Migrate for performance reasons.** A Big Process that's outgrown its current host — memory pressure, disk I/O contention, geographic latency to its users — moves to a bigger host by file copy.
- **Migrate for cost reasons.** Cheap warehouse-tier hardware for cold processes, hot hardware for active ones. Reclassification is a file move.
- **Fork consciousness.** Copy the file twice; open both. Now the process is running in parallel on two hosts, each unaware of the other, each free to diverge. Reconcile later (or not).
- **Time-travel consciousness.** Keep periodic snapshots of the file. Revive an old snapshot on any host to explore what the process "would have done" from that point forward. The old copy is a live, mutable process — not a read-only replay.
- **Cross-language consciousness.** Any host that can register the engine's UDF set (see the [Lua-owner contract](index#the-lua-owner-contract)) can revive the file. That's currently Lua, but the boundary is "opens SQLite, registers UDFs," not "same Lua version."
- **Preserve consciousness across engine upgrades.** New engine version reads the same file, resumes execution against the same graph. As long as the schema is compatible (or has a migration path), the process outlives the software running it.

The one caveat: **`handle_key` state doesn't cross the wire.** Objects wrapping native resources — open sockets, file descriptors, allocated buffers, subprocess pids — carry a `handle_key` pointing at host-local state that lives outside the file. On migration, the receiving host either reconstitutes the underlying resource (reconnect the socket, reopen the file) or the object surfaces "handle unavailable" per its class's contract. The runtime plumbing is: same file, same objects, but the native-resource-backed slots need re-binding on wake. Pure-Caspian state — every hash, every array, every closure, every string, every role, every frame — transfers with zero loss.

The framing: the SQLite file is the process's mind; hosts are interchangeable bodies. Consciousness travels with the file.

### `%engine.transfer_mind()`

The engine talks to Drinian through a defined API — a consistent surface that any Drinian backend must implement. SQLite is one implementation; others can follow (in-memory, other embedded databases, distributed formats, network-backed) and be Drinians as long as they satisfy the same API.

That premise is what lets `%engine.transfer_mind()` sit at the language level: it moves a process's state between any two Drinians, not between two SQLite files specifically. Same-backend transfers (SQLite → SQLite) collapse to `cp` because the format is byte-identical, but the operation itself is defined against the API, not the file format. Different-backend transfers (SQLite → in-memory for testing; in-memory → SQLite to persist; anywhere → anywhere as backends multiply) work by construction.

**Mechanism.** Mid-execution, when a process calls `%engine.transfer_mind`: (1) spin up (or connect to) a destination — commonly a small microserver holding an empty SQLite database, reachable over a Unix domain socket for local transfers or HTTP for remote; (2) port state using SQLite's own export formats (`sqlite3_backup` API for live copy, `.dump` for SQL-textual) — no per-class serialization, no `to_json`, no snapshot format design; SQLite's machinery handles arbitrary schema, and every future addition to Drinian transfers for free; (3) swap the backend — the engine drops its local implementation and picks up the client backend pointed at the destination; (4) release the local Drinian — file closed, in-memory structures freed. Expensive in wall-clock time and IO, but no feature tax — nothing in the engine grows to accommodate transfer.

**Cost profile.** Only the porting step is expensive; the rest is trivial. Spinning up a destination microserver is O(schema size) — the microserver spawns, opens `:memory:`, applies the schema (kilobytes of DDL), starts listening. Milliseconds. Swapping backends is a pointer change. Releasing the local Drinian is a `close`. The irreducible cost is copying live state across the transport, proportional to how big the mind is. That decoupling means microservers can be pre-warmed — a supervisor pool keeps empty seeded microservers idle, eliminating even the spin-up cost — but that's an optimization, not a requirement.

**Handoff, not replication.** There is only ever one authoritative Drinian. `transfer_mind` doesn't duplicate the mind — it moves it. The source's local state goes away; the destination holds the only living copy. No two-copies-diverging problem, no reconciliation semantics, no consistency protocol to design. Consistent with the parent section's framing: `transfer_mind` moves the mind off this host. What stays here is the body (the engine process, still executing); what leaves is the mind (the Drinian).

**Why transfer-first-then-fork.** Fork alone against an in-memory Drinian gives each process its own independent copy of the state at fork time — parent and child can't coordinate through the object graph because they're touching two separate copies from then on. The concurrency story requires the state to live off-process first. Once the mind is in a microserver, forked children inherit the socket (not the database bytes), and every engine op travels to the single authoritative store. Shared object graph, no per-process divergence.

**After transfer, forking multiplies bodies against one mind.** With the mind moved to a microserver, forking the process becomes the concurrency story. Children inherit the socket file descriptor. Every forked engine is already configured to talk to the same Drinian.

~~~caspian
# Startup work runs against the default in-memory Drinian.
# ... whatever the process needs to prepare ...

# Set up a Unix-socket Drinian microserver and hand off state to it.
%engine.transfer_mind 'memory-server'

# Every engine op now travels over the socket. Local Drinian is gone.

# Fork ten workers. They inherit the socket automatically.
10.times do
	%forks.fork
end

# One process → eleven engines against one Drinian. Everything each
# of them touches through the object graph is visible to the others.
~~~

What falls out of that composition:

- **No mutex primitive at the Caspian level.** SQLite's transaction serialization is the concurrency primitive. `BEGIN IMMEDIATE` gives critical sections; regular transactions give optimistic concurrency. The [transaction feature](#full-process-rollback-via-transactions) doubles as the concurrency primitive.
- **Coordination is just objects.** Shared queue = a Caspian array in shared Drinian. Shared counter = a NumberPrimitive updated inside a transaction. Barrier = a shared hash with waiters incrementing a field. Idiomatic Caspian code, no concurrency-specific surface.
- **Fan-out patterns become natural.** Workers pop from a shared work queue, write results to a shared results hash, coordinate through shared listener registrations. No concurrency-library scaffolding.
- **Actor semantics without actors.** Processes communicate via shared state instead of message passing. Simpler mental model when sharing is what you want.

**Two realms per process.** Each engine now sees state in two places. The **shared realm** is everything in Drinian — every hash, every array, every closure's bucket, every role, every frame reachable through Drinian. All engines see the same values. The **host-local realm** is native resources referenced via `handle_key` — open sockets, file descriptors, subprocess pids, allocated buffers. Those live outside Drinian, in host memory. A file descriptor opened by process A isn't accessible to process B, even though the Caspian object wrapping it IS reachable through the shared Drinian. Reading such an object from any process gets you the object; using its methods to touch the underlying resource works only in the process that owns it. Same rule as `transfer_mind`'s own caveat — "shared object" doesn't imply "shared native resource."

**The socket is portable.** `transfer_mind` returns a handle to the socket it created (or connected to). That handle is a Caspian value: pass it as a method argument, store it in a bucket, write it to a file, send it over a Puck channel. Any process that receives the handle can attach to the same Drinian via the corresponding engine call, becoming another engine against the same shared state. Multi-stage patterns compose from that:

- **Late unification.** Parent forks children (each with its own independent copy of the state at fork-time). Later, parent transfers to a microserver and passes the socket back to the children; they attach and the family joins one shared Drinian, discarding their per-process copies.
- **Transfer, fork, re-transfer.** Process transfers its mind to microserver A, forks workers, one worker escalates and transfers to microserver B, forks a further set of workers. Multi-level trees of shared-state cohorts, each rooted at its own microserver.
- **Ad-hoc reconnection.** Restart a worker in a shared cohort: new process opens the socket handle from wherever it was persisted, attaches, rejoins the graph. No re-transfer needed.
- **Handoff without fork.** Process A transfers to microserver, hands the socket to process B, exits. Process B picks up where A left off — different host, different engine process, same Drinian.

The consistent-API premise makes all of that true by construction. The engine doesn't know or care what's on the other side of the API — Unix socket, HTTP, something else. Same calls, different backend.

## Full-process rollback via transactions

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

### Building fault-tolerant scripts

The transaction feature extends into a fault-protection primitive via the `catch: true` keyword (see [transactions](https://www.puck.uno/ideas/transactions/)). When a `catch: true` transaction encounters an uncaught exception, it captures the exception on the transaction object, rolls back the database, and lets execution continue past the block instead of unwinding. Combined with full-process rollback, this becomes the building block for fail-safe scripts:

~~~caspian
loop &request in $request_queue
	$tr = transaction(catch: true) as $transaction
		&process_request $request
	end

	if not $tr.committed?
		&log_failure $request, $tr.exception
		# state was rolled back cleanly; move on to the next request
	end
end
~~~

A single request that raises doesn't corrupt process state or crash the loop. Each iteration gets:

- **DB rollback.** Every object created, role added, ref repointed during the failed request reverts.
- **Exception containment.** The exception doesn't unwind past the transaction; the block returns a data-typed outcome the caller inspects.
- **Continuation.** The next iteration starts with clean state.

The pattern generalizes to any long-running loop, batch processor, event dispatcher, or supervisor. One transaction primitive; three benefits.

**Retry-with-backoff** falls out naturally:

~~~caspian
$attempt = 0

loop
	$tr = transaction(catch: true) as $t
		&risky_operation
	end

	if $tr.committed?
		break
	end

	$attempt = $attempt + 1

	if $attempt >= $max_attempts
		raise 'gave up after %$attempt attempts: %$tr.exception'
	end

	&sleep(backoff($attempt))
end
~~~

**Supervisor patterns** — the "keep this thing running no matter what" logic Erlang bakes into its runtime — become straightforward Caspian code, because the pieces already compose. Circuit breakers, bulkheads, and other resilience patterns build on the same substrate.

The design goal: make it easy to write Caspian scripts that ride out unexpected errors without leaving the DB in a partial state. Full-process rollback + `catch: true` covers the primitive; higher-level patterns become library concerns rather than language ones.

## Snapshot diffing

Two SQLite snapshots of the same runtime can be diffed at the row level:

~~~sql
attach 'before.sqlite' as before;
select * from objects
except select * from before.objects;
-- rows in current that weren't in before
~~~

Attach two snapshots side-by-side and answer "what did this program actually do?" in one query. Useful for reproducing bugs against a known-good snapshot.

## The debugger is a SQL client

Drinian's state lives entirely in a SQLite file. That file *is* the runtime — objects, frames, variable bindings, roles, listener registrations, GC scratch. Any tool that can open SQLite can inspect the runtime.

**Traditional debuggers ship a wire protocol.** Chrome DevTools Protocol, Debug Adapter Protocol, GDB's remote protocol — each is a versioned interface between the runtime and inspector tools. Every new debugger tool has to implement it. The runtime has to add endpoints for each new query pattern the ecosystem invents.

Under Drinian the "protocol" is SQL — a standard thousands of tools already speak. The runtime doesn't expose new endpoints for each new inspector; the schema IS the read endpoint. Adding a new dimension to inspect is a schema addition, not a protocol version bump.

**Live inspection while the process runs.** SQLite's WAL mode lets readers open the database concurrently with the writer, and readers see a consistent snapshot at their transaction's start. Point `sqlite3` at a running Caspian process's DB file, query state, get answers. No pause, no ptrace, no attach.

**Same interface for post-mortem.** A paused Big Process is a file on disk. Open it, run the same queries you'd run live, get the same shape of answer. No separate "core dump" format to design.

Tools that already work, no configuration needed:

- **`sqlite3` CLI.** Ships with every Linux distro. Ad-hoc queries against live or paused state, from any shell.
- **DB Browser for SQLite** and similar GUIs. Schema browser, table viewer, query builder — repurposed as a debugger with zero code.
- **Orlando pages.** The docs server can render SQL query results as pages — a custom dashboard is one Lua handler + one query.
- **Any language's SQLite bindings.** Automated tooling in Python, Lua, Rust — pick your language, all of them have well-worn SQLite libraries.

Examples of what each would be a custom debug-protocol endpoint in a traditional runtime:

~~~sql
-- The current call stack with variable bindings
select cs.position, cs.method, fl.name, fl.value_object_pk
from call_stack cs
left join frame_locals fl on fl.frame_pk = cs.rowid
order by cs.position;

-- Every listener registered on a specific broadcaster
select event_name, listener_pk, method_name
from instance_listeners
where broadcaster_pk = ?;

-- Objects marked for garbage collection right now
select object_pk, primitive from objects where del = 1;

-- Instances of a specific class
select object_pk from platters where class_pk = ?;

-- Roles owned by a specific user
select * from roles where path like ? || '.%';
~~~

Each of those is one query. No protocol design work. No wire format. Custom inspectors — watch-this-object dashboards, "surviving N GC cycles" alerts, invariant-check runners — are all "one query + a rendering layer."

Instrumentation flows the same way. If a debugger needs a piece of state the runtime doesn't expose yet, the fix is a new column or a new table (plus the engine writes that populate it). Existing debug tools automatically pick up the new field on the next query. No versioned protocol to negotiate, no client-side upgrade cycle.

## JSON queries into CaspM

CaspM stored as JSON in `asts.body` isn't opaque under SQLite — the JSON1 functions can query into it:

~~~sql
-- Every AST whose top-level call is `puts`
select id from asts where json_extract(body, '$.head.bwc') = 'puts';

-- All method bodies referencing a specific variable name
select id from asts where json_extract(body, '$..name') = 'user';
~~~

Not as clean as normalizing AST nodes into rows, but no per-node overhead and still queryable.

## Full-text search across the runtime

SQLite's FTS5 extension can index text columns. Then:

- **Search error messages** across `gc_errors.message`.
- **Search source paths** across `srcs.path`.
- **Search JSON-shaped columns** like `asts.body` or `call_stack.iterator_state` for keywords.

One extension, one virtual table, and the whole runtime becomes searchable.

## Constraint-based structural guarantees

Every invariant we expressed as a `check` constraint or foreign key becomes DB-enforced. Random or generated states either satisfy the schema (and are valid) or get rejected on write. SQLite itself is a property-based test harness for our runtime model.

## Event-driven propagation via Lua UDFs

Triggers can call Lua UDFs. That turns Drinian from a passive state store into a reactive system: state changes fire callbacks that update dependent state, invalidate caches, or dispatch Caspian-level logic. The engine's "next state" logic isn't imperative code that runs the transition — it's the DB itself reacting to the write.

Concrete cases:

- **Automatic path maintenance.** `after update on roles` where `parent_pk` changed fires a UDF that recomputes `roles.path` on the row (and cascade-updates paths on all its descendants). No app code has to remember to keep `path` in sync.
- **Reactive cache invalidation.** When an object's role changes, a UDF invalidates cached permission grants that referenced the old role. Cross-table dependencies expressed as triggers.
- **Caspian-level callbacks.** When an object of a specific class is created, a UDF dispatches to a registered Caspian method. `after insert on platters` filtered on `class_pk = <SomeClass>` fires `SomeClass:on_created` inside the engine.
- **Derived-view maintenance.** Materialized aggregates — role-descendant counts, active-frames histograms, orphan-candidate lists — get recomputed reactively via UDF triggers on the relevant tables.
- **Streaming observability.** Every mutation emits an event that a UDF hands to whatever subscribers are registered — inspectors, debuggers, tracing tools, external tools listening over pipes.

The shape change is fundamental: **the runtime becomes event-driven at the storage layer.** Every field mutation is a hook point. Adding a new derivation is one `create trigger` plus one UDF registration; no engine dispatch path needs updating. And because triggers fire inside the transaction, propagation is atomic — the derived state is consistent with the base state at every observation point.
