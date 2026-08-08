# Drinian with SQLite

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite",
	"role": "brainstorm space for using SQLite directly as Drinian's storage layer — a purpose-built schema shaped around Drinian's fields, not layered on top of Fiona. Companion to ideas/fiona-as-drinian/ which explores routing through Fiona as an intermediate.",
	"status": "sketching 2026-08-07 — table shapes proposed; not committed"
}}
~~~

An alternative to `ideas/fiona-as-drinian/`. Instead of routing Drinian through Fiona's generic object-store schema, model each Drinian field as a table directly. Shape the schema around Drinian's needs.

## The Lua-owner contract

Drinian's SQLite database is **always owned by a Lua process** (the engine) and never runs standalone. That's a load-bearing assumption throughout the design:

- **Lua UDFs are always available.** The engine registers UDFs on startup; triggers use them freely. Anything that needs to reach into app logic (fire `on_close`, dispatch a Caspian method, invalidate a cache, walk custom state, check a semantic invariant) becomes a UDF the engine registers.
- **Triggers can invoke app logic.** No need to express everything purely in SQL. GC drain callbacks, reactive propagation, cross-table cascades, semantic checks — all doable via triggers that call UDFs.
- **UDF hops break trigger recursion chains.** SQLite caps trigger recursion at `SQLITE_MAX_TRIGGER_DEPTH` (default 1000). A meaningful propagation chain — cascade delete triggering a mark triggering further cascades — can hit the ceiling on its own. Routing a step through a UDF resets the counter: writes the UDF issues run as fresh top-level statements, not nested inside the original trigger chain. That lets us build genuinely reactive state machines without stack limits. Discipline required: UDF hops must terminate. No unbounded UDF → trigger → UDF → trigger loops. Design each hop as a clear step in a finite propagation.
- **The DB can query the app.** UDFs can be registered as scalar or aggregate functions usable inside `select`, in trigger `when` clauses, and in `check` constraints if the semantic warrants it.
- **Big-Process revive rebuilds the connection deterministically.** Pause = close the file. Later revive = new Lua host opens the file, re-registers the same UDF set, rebuilds any in-memory Lua-side registry (e.g., the `handle_key` → native-handle map), resumes. The database doesn't survive without the Lua owner, but the pause/revive cycle is deterministic because every host reinstalls the same UDFs by the same protocol.
- **The database isn't portable to non-Lua contexts.** A bare `sqlite3` CLI can inspect Drinian for reads that don't hit a UDF, but anything mutating (which will always fire triggers, which will always call UDFs) needs the Lua host attached. That's the trade — SQLite storage plus Lua host is the contract, not SQLite alone.

Every design choice below leans on this. If a decision seems like "how do we express X in SQL alone?", the actual answer is "we don't — the trigger calls a UDF."

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

See [features](features) — the concrete wins from shaping SQLite around Drinian's specific needs (bidirectional lookups, materialized ancestor paths, SQL-as-debugger-protocol, Big Processes, full-process rollback via transactions, and more).


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
