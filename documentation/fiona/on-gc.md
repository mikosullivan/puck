# on_gc — close hooks, the drain, and the process flag

~~~vibecode
{"vibecode": {
	"doc": "documentation_fiona_on_gc",
	"role": "Design spec for Fiona's GC callback mechanism. Covers the per-db on_gc callback, the process temp table that gates callback-phase behavior, the auto-mark trigger that keeps new collections from surviving close hooks, and the in_trace numbering that gives parent-first callback ordering.",
	"status": "design — mechanism settled; ready to implement when the surrounding drain rework lands"
}}
~~~

Fiona fires a caller-registered callback per collection about to be deleted, in a defined order. The callback runs whatever cleanup the caller wants — Caspian's `on_close` machinery is the primary consumer, but Fiona itself is Caspian-ignorant: it hands over a hash / array about to die, the callback decides what "close" means.

Five pieces make this work:

- **The `process` temp table** — a general runtime-flag mechanism. One row for each mode the drain (or anything else) needs to signal.
- **The `in_gc_callback_phase` row** — presence in `process` means the drain is currently in its callback-firing phase.
- **The `in_trace_counter` row** — a drain-scoped counter (also in `process`) that vends the next `in_trace` number without a `max()` scan against the collections table.
- **The auto-mark trigger** — during the callback phase, any newly-created collection is auto-marked `in_trace` (using the counter) so it dies with the drain. Nothing new persists from inside a close hook.
- **`in_trace` as an incrementing integer** — the seed gets the counter's next value, propagation adds subsequent values in discovery order. Callbacks fire in ascending numeric order, which is parent-first (closer to the just-severed anchor point fires first).

The callback surface itself is one method:

`db:on_gc(fn)` — registers `fn`. One at a time; re-registering replaces. `db:on_gc(nil)` clears.

## The process table

A per-connection temp table holding runtime flags and their associated data. Not GC-specific — the pattern works for any runtime mode Fiona (or higher layers) needs to signal.

~~~sql
create temp table if not exists process (
	key text primary key,
	details
);
~~~

Row presence is the flag. `details` is untyped (SQLite affinity handles polymorphic values) and carries whatever data the consumer of that specific key expects.

The drain uses two keys:

| key | details |
| ---- | ---- |
| `in_gc_callback_phase` | *(unused — presence is the flag)* |
| `in_trace_counter` | integer — highest `in_trace` number handed out so far |

Other consumers can layer their own keys with their own detail shapes (`drain_iteration_count`, `snapshot_destination`, `debug_verbosity`, ...). Each consumer of a specific key knows what shape `details` should carry; the table itself doesn't enforce it.

**Lifecycle for the drain rows:**

- Drain enters → insert both rows: `insert into process (key, details) values ('in_gc_callback_phase', null), ('in_trace_counter', 0)`.
- Drain exits → delete both rows.
- Both are cheap (primary-key ops). The temp table dies with the connection, so a crashed process leaves no lingering flag.

**No SEQUENCE in SQLite.** SQLite has one auto-increment mechanism, `integer primary key autoincrement`, and it's tied to the primary key. There's no `create sequence` and no way to auto-vend numbers into a non-PK column directly. The `in_trace_counter` row is the standard SQLite emulation — a single-row counter that consumers read-and-increment via a trigger or explicit SQL. It's cheap (single PK-indexed row) and behaves like a sequence for our purposes.

## Auto-mark trigger

While the `in_gc_callback_phase` row exists in `process`, any new collection created via `insert into collections` gets `in_trace` set to the next value vended by `in_trace_counter`:

~~~sql
create temp trigger if not exists collections_auto_mark_during_gc
after insert on collections
when exists (select 1 from process where key = 'in_gc_callback_phase')
begin
	update process set details = details + 1
		where key = 'in_trace_counter';
	update collections set in_trace = (
		select details from process where key = 'in_trace_counter'
	) where collection_pk = new.collection_pk;
end;
~~~

Both statements are primary-key hits — no scans, no aggregates. The counter is the sole source of truth for "next in_trace value," so auto-mark, seed insertion, and propagation all draw from the same well.

**Consequences:**

- A close hook that creates a new hash / array to hold intermediate work → the new collection is in-trace and dies with the drain. No leaked state.
- A close hook that creates a "wrapper" object trying to indirectly save something dying → the wrapper is in-trace, dies too. No indirect resurrection.
- New collections get their own callback (see [Delete-as-you-go](#delete-as-you-go)) — nested close semantics work by construction.

**After insert + update the just-inserted row** is the SQLite idiom here. `before insert` can't directly modify `new.column`; `after insert` with an update on `collection_pk = new.collection_pk` works cleanly. The `in_trace` assignment picks the next counter value, so the new collection sorts *after* any existing in-trace collections — its callback runs after the currently-firing one completes.

## The in_trace numbering

`in_trace` on a `collection` row is either null (not in a trace) or a positive integer. During a trace:

- The seed (collection whose incoming edge was directly severed) gets the counter's next value.
- Propagation walks backward through `relationships.child = seed` and adds each ancestor with the counter's subsequent values, in discovery order.
- If the trace completes and root isn't in the closure, the drain enters the callback phase.
- Callbacks fire in ascending `in_trace` order.

This gives **parent-first ordering**: the collection closest to the just-severed anchor point runs its close first, while the collections that depended on it for their anchoring are still alive. Their closes fire next.

**Cycle case.** Two collections referencing each other, neither is strictly parent-of-the-other. The numbering picks a consistent order (seed = N, back-referrer = N+1). Deterministic even for cycles, though the "parent-first" semantic is inherently ambiguous there.

**Counter is drain-scoped, monotonic across iterations.** The counter is initialized to 0 when the drain begins and grows monotonically until the drain exits. Each drain iteration's fresh trace picks up where the last one left off — iteration 1 might use values 1–3, iteration 2 uses 4–6, and so on. Within any single trace closure, the ordering guarantee is unchanged (the seed's number is the lowest of its closure). Across iterations, every `in_trace` value is unique for the life of the drain, which makes `gc_errors` entries independently identifiable by their `trace_order` field.

## The callback

### Signature

~~~lua
db:on_gc(function(collection)
    -- collection is a hash/array handle for the collection about to be deleted
end)
~~~

`collection` is the same proxy handle a caller gets from any other Fiona navigation — metatable-driven: `collection.foo`, `collection[3]`, `#collection`, `for k, v in pairs(collection)` all work. The handle's `type` field is 'h' or 'a'; its `pk` is the raw `collection_pk` if the callback wants it directly.

### When it fires

For each collection with `in_trace` set, the callback fires *before* the row is deleted. At callback time the collection still has:

- Its scalars readable.
- Its outgoing refs readable (higher-numbered in-trace targets are still there; they'll fire their own callbacks in due course).
- Its incoming refs already gone from the outside world — the trace's propagation walk found them all inside the trace.

### Delete-as-you-go

The drain re-queries for the current lowest-numbered in-trace row on every pass. Termination is the query returning nothing — not "consumed the initial set."

~~~lua
while true do
    local next_pk = self:_query_one(
        "select collection_pk from collections where in_trace is not null " ..
        "order by in_trace limit 1")

    if not next_pk then
        break
    end

    fire_callback_for(next_pk)                       -- may auto-mark new collections
    self:_exec("delete from collections where collection_pk = :pk", {pk = next_pk})
end
~~~

**Do not snapshot the in-trace set and iterate.** A callback can insert new collections during its run, and the auto-mark trigger stamps each of them with an `in_trace` value higher than any assigned before it. Those late arrivals belong in the same drain — their callbacks must fire too, and their rows must be deleted — but a caller that pre-loaded the initial in-trace set (`select ... where in_trace is not null` at loop entry, then a for-loop over the result) would miss them entirely. Re-querying every pass is what makes the set dynamic.

**Termination is naturally correct.** Each pass either (a) processes and deletes one row, shrinking the set by one, or (b) the callback auto-marks new rows, keeping the set non-empty; those get processed next. Eventually no new rows are created during a callback and the set drains to zero. The exit condition is "the query returned nothing," which is the same regardless of how many rows the callbacks added along the way.

**Nested drain composition falls out.** A close hook that creates a temp file-handle collection, uses it, then deletes it — the delete marks the file handle as needs_trace, which enters the drain's outer loop. Fine, the file handle's close fires (via this same mechanism) as its own drain iteration. Recursive close hooks work by construction because the whole thing is a fixed-point loop over a live set.

## Rules during close

The callback runs inside the drain's transaction. It has full read access to the database. Writes are allowed with the safety net of auto-mark:

**Anything the callback creates via `add_hash` / `add_array` is auto-marked `in_trace` and dies with the drain.** Consequences follow from that:

- **Scratch collections** — create, use, they clean themselves up. No explicit delete needed.
- **New persistent collections** — impossible during close. Any new collection is in-trace. Anchoring it under a live collection creates a ref that FK-cascades away when the collection dies. Silent no-op.
- **Modifying pre-existing collections** — allowed. Scalar updates on a live collection, appending scalars to a pre-existing array, deleting keys from a pre-existing hash — all fine, all persist.
- **Refs FROM live → dying** — write succeeds; drain deletes the target anyway; FK cascade cleans up the ref. Silent no-op. The callback's attempted "save" doesn't stick, but nothing zombies stay alive.
- **Refs between two dying collections** — fine, both going away, no lasting effect either way.

**No resurrection under any path.** If a close hook tries to save a dying collection by re-anchoring it, the write succeeds but the drain proceeds to delete the target. FK cascade removes the ref. The programmer's intent doesn't stick, but the system stays consistent — no zombie objects, no dangling refs at commit time.

**Silent no-op is the rule, not loud error.** Following Miko's "no nanny code" stance: attempts to persist state during close silently no-op rather than raising. Programmers discover this by testing and adapt. If a real workload later shows this bites in practice, a loud-rejection trigger can be added retroactively without changing storage semantics.

## Error handling

Each callback invocation runs inside a `pcall`. If it raises:

- Fiona catches the error.
- Records it in a `gc_errors` accumulator on the Db instance: `{collection_pk, message, trace_order}`.
- Continues to the next callback. One bad handler doesn't break GC for other collections.

`db:gc_errors()` returns the accumulator. Callers can inspect after the drain to see if anything went wrong. The list clears at the start of each drain.

This mirrors Drinian's `state.gc_errors` model — a long list is a smell. Programs that snapshot or log at shutdown can check `db:gc_errors()` before committing to see if cleanup was clean.

**Callbacks are not for correctness.** The rule "if the callback raised, cleanup didn't happen" applies. A resource that must be cleaned up (file handles, locks, external systems) needs a redundant path — try/finally in Caspian, or a program-shutdown sweep.

## Walkthrough

Concrete example. Root anchors a `logger` object which holds a reference to a `session` object. Session holds a back-reference to logger. Root also anchors a `writer` object (used for output). Both logger and session have `on_close` methods.

State before the drain:

~~~
collections: [root=1, logger=2, session=3, writer=4]
relationships:
  root.logger → logger        (rel 1)
  root.writer → writer        (rel 2)
  session.logger → logger     (rel 3, back-reference)
  logger.session → session    (rel 4)
~~~

Program does `db:delete_hash_element(1, "logger")` — cuts rel 1. Mark trigger fires on the logger row → logger gets `needs_trace = 1`.

**Drain enters.** `insert into process (key, details) values ('in_gc_callback_phase', null), ('in_trace_counter', 0)`.

**Drain iteration 1.**

Step 1: Pick seed. logger.

Step 2: Trace. Counter bumps to 1 → `logger.in_trace = 1`. Propagate: rows where `child = logger` → rel 3 (session references logger). Counter bumps to 2 → `session.in_trace = 2`. Propagate again: rows where `child = session` → rel 4 (logger references session, but logger is already in trace). Terminate.

Trace closure: `{logger: 1, session: 2}`. Counter is now 2.

Step 3: Alive check. Root's `in_trace` is null. Not alive.

Step 4: Delete-as-you-go loop.

**Iteration 4.1: logger (in_trace = 1) — lowest, fires first.**

Fiona wraps logger's `collection_pk` in a hash proxy, invokes the callback. The Caspian engine's on-gc handler looks up "what class instance is pk 2?" in its own registry — finds a `Logger` instance whose class defines an `on_close` method. Invokes `Logger.on_close(logger_handle)`.

`Logger.on_close` reads its state, decides to log a shutdown message. It does:

~~~lua
local msg = db:add_hash()
-- msg is now in_trace = 3 (auto-marked)

db:set_hash_scalar(msg, "text", "logger shutting down")
db:set_hash_scalar(msg, "level", "info")

-- Try to save msg under writer:
db:set_hash_ref(logger_handle.writer, "next_msg", msg)
-- Write succeeds. Row: (parent=writer, child=msg, key='next_msg')
~~~

msg was auto-marked at insert time — the trigger fired because `in_gc_callback_phase` is in `process`. The counter bumped from 2 to 3 and msg got `in_trace = 3`. The `set_hash_ref` operation succeeds — no resurrection trigger to raise, and the write inserts a new relationships row.

When logger's callback returns, Fiona deletes the logger row. FK cascade drops rels 1 (already deleted), 3, 4 — the outgoing / incoming edges.

**Iteration 4.2: session (in_trace = 2).**

Session's callback fires. It reads its state, does its own work. Returns. Fiona deletes the session row. Cascade drops any remaining session-adjacent relationships.

**Iteration 4.3: msg (in_trace = 3).**

msg was auto-marked during logger's callback. Its callback fires. If no class in the Caspian engine claims pk `msg_pk` as one of its instances (nothing was set up to associate a class with it — msg was just a bare hash), the on-gc handler is a no-op for it.

Fiona deletes msg. Cascade drops the `writer.next_msg` relationship. writer stays alive, but its `next_msg` field is now empty (the relationship was cleaned up by cascade).

**End of loop.** `select collection_pk from collections where in_trace is not null limit 1` returns nothing.

Step 5: Drain exits. `delete from process where key in ('in_gc_callback_phase', 'in_trace_counter')`.

Step 6: Drain exit check — assertion: no row has `needs_trace = 1` or `in_trace` set. Assertion passes. Commit the transaction.

**Final state:**

~~~
collections: [root=1, writer=4]
relationships:
  root.writer → writer
~~~

Logger, session, and msg are all gone. writer stayed alive but its `next_msg` attempt didn't persist — the message was a floating in-trace collection at write time, and by the time the drain got to it, cascade cleaned up the ref. The logger's *intent* to save the shutdown message didn't stick.

If the logger's designer wanted a persistent shutdown message, the correct pattern is to *modify a pre-existing collection*: append a scalar to an existing `root.shutdown_log` array, or set a scalar on an existing `root.last_shutdown` slot. Those writes go against non-in-trace targets and persist.

## Related

- `on_gc` on the Db class — Fiona API surface.
- `in_trace` column semantics and the drain algorithm — see [schema](./schema/) for the persistent + temp table structure.
- Drinian's `on_close` and `gc_errors` — the Caspian-side layer this hook feeds into.
- The `process` temp table is defined in [fiona-temp.sql](../../src/fiona/fiona-temp.sql) once implemented; its only current consumer is the GC flag.
