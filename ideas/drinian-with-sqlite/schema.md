# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_schema",
	"role": "Drinian's SQLite schema. `objects` table holds row shapes discriminated by a single `primitive` column — 'o' (object), 'h' (HashPrimitive), 'a' (ArrayPrimitive). Scalars are a variant of `primitive = 'o'` distinguished by `scalar_type` (scalar type). HashPrimitives serving as buckets carry `bucket_for` back-pointing at their owner; ArrayPrimitives serving as stacks carry `stack_for`. Only container primitives can be parents in `relationships`. Buckets and stacks are both lazy — Lua write layer creates them on demand. Scalars with no bucket/stack take a fast dispatch path through the built-in class for their `scalar_type` type. Uspace membership is derived dynamically from the `uspace` view over the anchor tables (locals, frame_amber, frame_delegations, frame columns) — no stored flag. GC uses two-column scratch (needs_trace / in_trace) — the drain deletes directly, and RESTRICT on relationships.child raises loudly if incoming references remain at delete time. Event registrations live in dedicated `instance_listeners` / `class_listeners` tables outside `relationships` — bookkeeping, not graph — with weak-ref lifetime via FK cascade.",
	"status": "iterating — added objects_role_parent_must_be_role trigger; the schema now enforces every part of the role-tree invariant except naming (single parent, cycle-free, cascade cleanup, root safety, parent-is-a-role)"
}}
~~~

Started 2026-08-07 from Fiona's current schema. Adapting as design decisions land.

## Design summary

Every Drinian row falls into one of these shapes, discriminated by `primitive`, `scalar_type`, `bucket_for`, and `stack_for`. One orthogonal pair sits alongside every row — omitted from the table for readability:

- **`source_pk` + `line`** (nullable pair) — the value's birth line in source. `source_pk` FKs a row in the `sources` registry. Both fields together or both null; immutable after INSERT (birth line doesn't change when the value moves).

Uspace membership is derived by the `uspace` view — a global UNION over anchor sources (root role, locals, frame_amber, frame_delegations, frame columns) across all frames in all processes. Not a stored column; always reflects current state.

| Row shape | primitive | scalar_type | scalar_value | bucket_for | stack_for |
|-----------|-----------|-----|-----|------------|-----------|
| HashPrimitive (standalone / root / internal) | `'h'` | null | null | null | null |
| HashPrimitive serving as a bucket | `'h'` | null | null | set | null |
| ArrayPrimitive (standalone / internal) | `'a'` | null | null | null | null |
| ArrayPrimitive serving as a stack | `'a'` | null | null | null | set |
| Plain full object (Hash, Array, MyClass, …) | `'o'` | null | null | null | null |
| StringPrimitive | `'o'` | `'s'` | text | null | null |
| NumberPrimitive | `'o'` | `'n'` | integer/real | null | null |
| BooleanPrimitive | `'o'` | `'b'` | 0/1 | null | null |
| NullPrimitive | `'o'` | `'u'` | null | null | null |

Rules baked into the schema:

- `primitive` is NOT NULL and has no default — every insert names the kind at creation time.
- Only container primitives (`primitive in ('h', 'a')`) can be parents in `relationships` — full objects and scalars can't have references directly; full objects reach their contents through their bucket / stack.
- **Role-shape alignment.** A row with `bucket_for` set must be a HashPrimitive (`primitive = 'h'`); a row with `stack_for` set must be an ArrayPrimitive (`primitive = 'a'`). An array can't be a bucket; a hash can't be a stack.
- **At most one role per row.** At most one of `bucket_for` / `stack_for` may be set on any given row. A row can't be both a bucket and a stack — enforced by `check (bucket_for is null or stack_for is null)`.
- **At most one bucket and one stack per owner.** `bucket_for` and `stack_for` are each `UNIQUE` — no two rows can be a bucket for the same owner (or a stack for the same owner). Rows where these columns are null don't collide because SQLite doesn't consider nulls in UNIQUE constraints.
- **Buckets and stacks are both lazy.** A plain full object gets neither at creation time. The Lua write layer creates them on demand — `ensure_bucket(obj_pk)` on the first field write, `ensure_stack(obj_pk)` on the first class-extension or shadow. Objects that live briefly and never need either save the row + constraint cost entirely. (Class dispatch for stack-less full objects is a design question we're deferring; probably a `class_pk` column when we get to it.)
- **Scalar fast path.** A scalar row (`primitive = 'o', scalar_type IS NOT NULL`) that has no bucket and no stack — no other row references it via `bucket_for` or `stack_for` — dispatches through the built-in class for its `scalar_type` type (StringPrimitive for `'s'`, NumberPrimitive for `'n'`, BooleanPrimitive for `'b'`, NullPrimitive for `'u'`). Scalars never auto-provision anything, so the fast path is the common case. Scalars that get extended (shadow methods, nested markers) fall back to full dispatch.
- Deleting a full object cascades via FK to delete its bucket (if present) + stack (`bucket_for` and `stack_for` FKs have ON DELETE CASCADE). No cleanup trigger.
- **Bucket / stack denormalization.** Owner rows also carry `bucket_pk` and `stack_pk` columns mirroring the collection-side `bucket_for` / `stack_for`. Redundant data — populated set-once by `objects_denormalize_bucket` / `_stack` triggers when the collection is inserted, then locked. Lets queries and dispatch skip a join.
- **`objects` is effectively immutable.** Identity columns (`object_pk`, `primitive`, `scalar_type`, `scalar_value`, `bucket_for`, `stack_for`) can never change. Denormalization columns (`bucket_pk`, `stack_pk`) are write-once. The only freely-mutable state is GC scratch (`needs_trace`, `in_trace`). Enforced by `objects_no_update`.
- Scalars are single-row leaves — a StringPrimitive is one row with `primitive = 'o'`, `scalar_type = 's'`, `scalar_value = <text>`.
- **Event listeners are bookkeeping, not graph.** Two dedicated tables — `instance_listeners` (for `.listen_to` registrations) and `class_listeners` (for `.listen_to_class`) — hold registration tuples. They live outside `relationships` so GC does NOT count them as reachability edges. Weak-ref lifetime falls out of `ON DELETE CASCADE`: when the broadcaster, class, or listener object is deleted, the registration cascade-deletes with it. Registration order is `reg_pk` (autoincrement). Composite `UNIQUE` on the tuple gives idempotent `.listen_to`.
- **Uspace is a global derived view, not a stored column.** `uspace` (view) unions the row-level anchor sources: root role (the user row), `locals.value_object_pk`, `frame_amber.namespace_hash_pk`, `frames.method_pk` / `method_class_pk` / `exception_class_pk`, and `frame_delegations.target_role_pk`. Any frame in any process contributes — shared object graph, so a reference from anywhere keeps the object alive. Membership is always current: when a frame pops and its anchor rows cascade, the previously-anchored objects drop out of the view automatically and become GC candidates. Roles (children of user in the tree) aren't a special case — they're regular objects reachable via relationships from user's bucket → 'children' array. Buckets and stacks aren't in the union either — they live inside their owner via bucket_for/stack_for cascade, and nothing normally makes them relationship children so they never become GC candidates. Listener registrations are NOT in the union — those are weak-ref by design.
- **Source-location tagging (`sources` + `source_pk` / `line`).** A dedicated `sources` table registers each file / URL that produces values or frames. Object rows and frame rows carry a `(source_pk, line)` pair back-pointing to their origin — the value's birth line, the frame's current line. Both null together when the source is unknown (engine internals, hand-written CaspM, source-less metaprogramming). On objects the pair is immutable; on frames the `line` advances as the frame executes.
- **AST storage on callables (`ast` column).** Function / method / closure objects carry their CaspM body in an `ast` blob column on `objects`, encoded as SQLite JSONB. The engine reads the current value on each call, thaws it to Lua-native form, and attaches the parsed tree to the frame executing it — no long-lived cache, no invalidation dance. Hot-patching an `ast` takes effect on the next call.
- **Roles are regular objects.** No schema-level role machinery — no `role_pk`, no `role_parent`, no dedicated triggers. User is seeded at pk = 1 (undeletable, intrinsic uspace root). Other roles are just objects held in user's role tree via bucket entries — each role carries a `'children'` array in its bucket pointing at its child roles. Tree invariants (single root, cycle prevention, ownership tracking) are enforced by engine-side code, not by the schema.
- **Call stack lives in dedicated tables.** Runtime frames don't fit the objects shape (no class dispatch, no bucket, no stack-of-platters), so they live in purpose-built tables: `processes` (plural), `frames`, `locals`, plus sidecars `frame_delegations` (role permission grants from `delegate_to` blocks), `frame_amber` (per-frame `%amber` namespace layer — init / remove / grant entries; `amber_cleared` on the frame is the full-surface walk-stop), and `captured_frames` (snapshot-by-reference of the frames below an in-flight exception).
- **Frame anchors are automatic via `uspace`.** Every frame-attached table (locals, frame_amber, frame_delegations, etc.) contributes to the uspace view. When a frame pops and its anchor rows cascade, the previously-anchored objects drop out of uspace automatically — no trigger to maintain, no engine-side release. The plural `processes` accommodates future features — coroutines, fork, multiple paused processes coexisting in one file, and **multiple concurrent instances of the same machine running over one shared object graph** — where each execution context is its own `processes` row. Concurrency semantics for the shared-graph case are language-level work; the storage substrate is ready. There's no seeded process — every engine creates its own `processes` row at startup and records the pk in the temp `current_process` table.
- **Rich frame kinds.** `frames.kind` covers the requirements' frame `action` values that we've settled on: `top_level`, `method_call`, `function_call`, `function_invocation`, `block`, `if_block`, `delegate_to`, `exception`, `on_close`. (Pause / revival isn't yet designed — no `'pause'` kind or pause-frame columns until it is.) Fields on `frames` are conditionally meaningful per kind (`method_pk` / `method_class_pk` on call frames, `iterator_position` / `iterator_of` on iteration frames, `exception_class_pk` / `exception_message` on exception frames). `lexical_parent_pk` on any frame links its scope's defining frame — variable lookup walks this chain, not the physical call stack.

## Schema

The DDL is displayed on its own page: [sql](sql).

The authoritative file is [src/drinian.sql](src/drinian.sql) — the sql page pulls it in via Orlando's `<!-- file: ... -->` directive so what you see rendered is always the latest committed version.

## GC drain algorithm

The drain runs on the Lua side, driven by the engine when memory pressure or an explicit trigger fires. It reads and mutates the GC scratch columns (`needs_trace`, `in_trace`) on `objects` and drives deletion via SQL. The whole pass wraps in a transaction so any RESTRICT FK violation rolls back atomically; the drain re-runs when conditions permit.

### Main loop — trace and sweep interleaved per candidate

~~~
while object = get_next_needs_trace() do
	run_trace(object)
end
~~~

**`get_next_needs_trace()`** — `SELECT object_pk FROM objects WHERE needs_trace = 1 LIMIT 1`. Hits the `objects_needs_trace` partial index; O(log n). Returns null when no candidates remain; loop terminates. Some candidates may already be gone (gobbled by a previous trace's cascade); the query just returns whatever's left.

**`run_trace(object)`**:

1. Stamp `in_trace = counter++` on the candidate.
2. Walk upward — `SELECT parent FROM relationships WHERE child = current_pk` — and stamp `in_trace` on each parent (skipping already-stamped rows — visited set).
3. **If any visited row is in `uspace`** (`SELECT 1 FROM uspace WHERE object_pk = ?`), the component is reachable. Clear `in_trace` across the component, clear `needs_trace` on any marked rows. Everything survives.
4. **Otherwise**, the component is dead. Delete in `in_trace` order:
   - Sever relationships first (parent OR child in the dead component). Required because `relationships.child` is `ON DELETE RESTRICT` — cyclic references would otherwise block deletion.
   - DELETE the object rows. Outgoing relationships cascade via `ON DELETE CASCADE` on parent.

Callback machinery (on_close and other per-delete engine hooks) is deferred — this section is a "loud + simple" drain today; callbacks will land alongside a new on-delete trigger when the design settles.

### Termination

Each iteration either clears `needs_trace` on the candidate (found alive) or deletes it (found dead). The count of `needs_trace = 1` rows strictly decreases per iteration. Cascade effects (deletes triggering the mark triggers on severed relationships) add more candidates, but the object graph is finite so the loop terminates.

### Failure modes

- **RESTRICT fires on delete.** Some row still has incoming references at delete time — trace missed something, or code between mark and sweep created a new edge. Transaction rolls back atomically. Whole GC pass undone. Whatever wrapper transaction (or catching mechanism) sits above the drain handles the exception.

## Design consideration: UUIDs as primary keys?

Currently every table uses `integer primary key autoincrement` for its pks — small sequential integers. Would switching to UUIDs earn its keep?

### What UUIDs would buy

- **Cross-database uniqueness.** Two independent Drinian databases could be merged without pk collision. Currently a snapshot from Process A and Process B both start at pk = 1; merging is a manual reconciliation task.
- **Distributed generation.** Multiple writers could allocate pks without coordinating. `autoincrement` is a single-writer-per-connection concept.
- **External reference stability.** An external system holding "object 42" as a reference to a specific Drinian object relies on that pk. Under integers, pks are stable within a single DB but not across DBs; UUIDs are stable everywhere.
- **Debugging trace disambiguation.** A log entry mentioning object 42 could mean many different objects across runs. A UUID is unambiguous.

Generation cost isn't the issue — SQLite ships a `uuid()` extension function (`ext/misc/uuid.c`) that generates UUID4 values directly. Not compiled into every SQLite build by default, but trivially includable, and roughly equivalent to a plain `randomblob(16)` in cost.

### What UUIDs would cost — even if we don't use their uniqueness features

Every table would pay:

- **Storage.** Sequential integers are 1–4 bytes each; UUIDs are 16 bytes (as blob) or 36 bytes (as text). Every FK column, every index, every `relationships` row (parent + child = two pk columns) roughly 5x its pk-related storage. Rough estimate for a 100K-object program: ~1–2 MB integer pks → ~5–10 MB UUID pks. Whole database roughly doubles or triples in size.
- **Index performance.** B-tree indexes hold fewer entries per page with larger keys. More page reads per lookup, more page faults for large scans.
- **B-tree write locality.** Sequential integers append to the end of the B-tree — a hot handful of pages. Random UUIDs scatter across the whole tree, dirtying many pages per write. Real-world write throughput drops noticeably (2–3x slower for insert-heavy workloads).
- **Rowid alias loss.** With `INTEGER PRIMARY KEY`, SQLite makes the pk column an alias for the internal rowid — zero storage overhead. With a UUID pk, either the table is `WITHOUT ROWID` (works but has other constraints and quirks) or the table carries both a rowid AND the pk (extra storage plus an extra lookup layer).
- **Human readability.** `role_pk = 1` scans instantly; `role_pk = '9c440335-a5fa-406a-8676-1da39a1a4617'` doesn't. All debugging output, snapshot inspection, and SQL prompts pay this cost forever.
- **JSON payload size.** Anywhere pks appear in JSON (the `ast` blob's structure, snapshot serialization), UUIDs make the payload larger.

### When UUIDs would earn their keep

- Merging Drinian files from different processes — multi-agent coordination, sync patterns.
- Long-lived external references to specific objects across DB lifetimes (bookmarks, permalinks, cross-system audit trails).
- Multi-writer scenarios without coordinated pk allocation — cross-process concurrent writes to one shared DB (a scenario the current design doesn't have and would need substantial other work to support).

### When they wouldn't

- V1 single-process, single-writer Drinian.
- Pause/resume within a single DB file lineage (the file survives — pks survive with it).
- Every scenario the current schema serves.

### The "cost if you don't use it" test

Feature tax is real and unrewarded for the common case. The scenarios where UUIDs help are outside V1 scope; the scenarios where they hurt are every read, every write, every trace, every scan.

### If we ever need cross-DB uniqueness

The cheapest way to add it later is an **optional UUID sidecar column** on `objects` (or a sidecar table keyed `object_pk → uuid`) — set on the specific objects that need cross-DB identity, null everywhere else. Pay per-use; keep the integer pk fast path for everything else.

### Randomness source: OS entropy vs SQLite's internal PRNG

Even if we accepted the storage / performance costs above, there's a policy question: **Caspian requires random-value generation (UUIDs, session tokens, etc.) to use OS-supplied entropy.** The Lua-side UUID library we already rely on calls the OS's random device (`/dev/urandom` on Linux) on every generation, for regulatory compliance and to keep predictable-PRNG bugs out of the security surface.

If we adopted UUIDs, we'd need to know: does SQLite's `uuid()` extension (or `randomblob()`) satisfy that constraint?

**What SQLite actually does.** SQLite's `sqlite3_randomness()` API — which backs `randomblob(N)`, `random()`, and (indirectly) the `uuid` extension — uses a ChaCha20 stream cipher as its internal PRNG. On the first call after library load, SQLite seeds the generator by reading bytes from `/dev/urandom` (or the platform equivalent). Subsequent calls generate bytes from the ChaCha20 stream — no further syscall.

So SQLite's generator is:

- **Cryptographically strong** — ChaCha20 is a modern crypto primitive.
- **OS-seeded** — the initial state comes from OS entropy.
- **Not "per-byte from OS entropy"** — generation runs from the internal cipher stream after the initial seeding.

**Whether that satisfies Caspian's requirement is interpretive.** Two readings:

- **Strict.** "Every random byte comes fresh from OS entropy." SQLite fails this — we'd need a Lua UDF that reads `/dev/urandom` per generation.
- **Pragmatic.** "The entropy source is OS-provided; generation is cryptographically strong." SQLite passes — its built-in is fine.

**Cost comparison:**

- **SQLite native** (`uuid()` or `randomblob(16)`): microseconds per generation, in-process ChaCha20, no syscall after startup seeding.
- **Lua UDF calling `/dev/urandom` per UUID:** syscall + Lua-callback overhead per generation. Order of magnitude slower than the SQLite native path (still fast in absolute terms, but noticeable at scale).

If we ever adopted UUIDs and interpreted the requirement strictly, the total UUID cost stacks: storage overhead (previous subsection) + slower generation (this one). If we interpret it pragmatically, only the storage overhead remains.

### Recommendation

Stay with integer pks. Feature tax is 2–3x storage and comparable performance overhead; the randomness-policy question adds another decision to resolve; benefit is a scenario we don't have yet. Revisit only if concrete workloads require it, and even then prefer a per-object opt-in via the sidecar approach.

