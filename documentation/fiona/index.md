# Fiona

~~~vibecode
{"vibecode": {
	"doc": "documentation_fiona",
	"role": "Fiona — the SQLite-backed graph store that is Caspian's storage substrate. This page catalogs the callable method surface on a db handle; the [schema](./schema/) is the source of truth for tables, constraints, and triggers.",
	"status": "live spec"
}}
~~~

Fiona is Caspian's storage substrate — a SQLite-backed graph store where collections (hashes and arrays) live in the `collections` table and scalars live inline in the `relationships` table.

## Storage shape

Two base tables and a meta table:

- **`collections`** — one row per hash or array. Columns: `collection_pk` (identity), `type` (`'h'` or `'a'`), and the transient GC flags `needs_trace` / `in_trace`. Root is always `collection_pk = 1` and cannot be deleted.
- **`relationships`** — one row per edge, keyed by `rel_pk`. Each row is EITHER a **collection edge** (`child` set to another collection's pk; `st` and `scalar` null) OR a **scalar-carrying row** (`child` null; `st` in `s`/`n`/`b`/`u`; `scalar` holds the inline value). A CHECK constraint enforces the invariant — never both set, never both null. Hash-parented rows carry `key`; array-parented rows don't. Every row has `idx` (position for arrays, insertion order for hashes).
- **`meta`** — key/value settings about the database itself. V1 carries one row: `schema` naming the schema version.

Scalars live inline in relationships, not as separate collection rows. Consequences: the trace's reachability graph only ever walks collection edges; a hash with N scalar entries is N relationship rows and nothing else in collections; the "one collection reference OR one scalar" invariant is a row-level CHECK.

## Functions

Top-level functions — things you call before you have a `db` handle.

### `get_db`

Return a database handle backed by SQLite. Every method under [Methods](#methods) is called on this handle.

`get_db(path, mode) → db`

**`path`** — a Lua string identifying where the database lives:

- A filesystem path (e.g., `'./fiona.db'`, `'/var/data/fiona.db'`) — a persistent database file.
- The literal string `':memory:'` — an in-memory database that vanishes when the handle is released. Useful for tests and ephemeral computation. SQLite's own convention.

**`mode`** — a required short string specifying the access mode. One of:

- `'r'` — read-only. File must exist; the returned handle raises on any method that would modify the database.
- `'rw'` or `'wr'` — read-write. Both directions allowed. Combines with create-if-missing.

No default. Callers must specify explicitly — makes intent visible at every call site and prevents accidental writes to a database opened for reading. Convention borrowed from C's `fopen()` mode string.

**No write-only mode in V1.** `'w'` is deliberately not accepted, even though the C `fopen`-style vocabulary would suggest it. Every write to a Fiona database has to read the root collection first to resolve where the write lands, so a strict write-only handle would be unable to perform any operation Fiona actually exposes. Removing `'w'` from the accepted set is a conscious V1 choice, not an oversight — if a genuine append-only use case surfaces (bulk load, log-style ingestion) and can justify the root-read exception, `'w'` can be added back. Passing `'w'` today raises.

**`':memory:'` requires write permission.** An in-memory database starts empty and can't be populated without write access — opening one in `'r'` mode raises. Valid combinations for in-memory: `'rw'` or `'wr'` only.

**Startup logic.** `get_db` decides between three cases:

1. **Database has the Fiona schema** → open and use.
2. **Database has no tables** → apply the Fiona schema. Only valid in `'rw'` / `'wr'` mode; a fresh file opened in `'r'` mode raises.
3. **Database has tables but they're not Fiona's** → raise. Prevents silently corrupting an unrelated SQLite file or opening a foreign DB as if it were Fiona.

Concretely:

1. Open (or create) the SQLite file via lsqlite3. In `'rw'` / `'wr'` modes, SQLite creates the file if absent (matching its own default). In `'r'` mode, a missing file raises.
2. Inspect the schema — check whether `collections`, `relationships`, and `meta` tables are present. All three present → case 1. None present → case 2, apply the schema at [../../src/fiona/fiona.sql](../../src/fiona/fiona.sql). Any other combination → case 3, raise.
3. Set the required per-connection pragmas: `foreign_keys = on`, `recursive_triggers = on`.
4. Return the handle, tagged with the mode so its methods can enforce read/write restrictions.

**Schema matching depth.** Step 2 checks table presence by name only. Deeper verification (column types, constraint sets, trigger bodies) is not done at V1. If reliability of the name-only check ever becomes an issue, `get_db` can grow schema-fingerprint checking via `meta.schema`.

The tradeoff of auto-create is the "typo in the path silently produces an empty DB" case. Caller-side concern, not a `get_db` responsibility.

## Methods

### Creating collections

Create empty hashes and arrays. These are the only two calls that produce a new collection row; scalars are inserted directly by the set methods.

#### `add_hash`

Create a new empty hash. Returns its `collection_pk`.

`db.add_hash() → collection_pk`

#### `add_array`

Create a new empty array. Returns its `collection_pk`.

`db.add_array() → collection_pk`

### Setting elements

Four flavors, one per (parent shape × content shape) combination. Each handles fresh insert, in-place update (no-op if the new value equals the existing one), and shape swings between collection reference and inline scalar. Every call runs inside its own atomic() savepoint; the mark trigger + drain handles any GC that follows from an update swinging away from a collection edge.

#### `set_hash_ref`

Anchor an existing collection under a hash key. Value is a `collection_pk` returned from `add_hash` / `add_array`.

`db.set_hash_ref(parent, key, ref_pk)`

#### `set_hash_scalar`

Set an inline scalar under a hash key. Value is a Lua scalar; `st` is inferred from the Lua type: string → `'s'`, number → `'n'`, boolean → `'b'` (stored as 0 or 1), nil → `'u'`.

`db.set_hash_scalar(parent, key, value)`

#### `set_array_ref`

Anchor an existing collection at a specific idx in an array. If the idx is already occupied, the shift trigger opens room.

`db.set_array_ref(parent, idx, ref_pk)`

#### `set_array_scalar`

Set an inline scalar at a specific idx in an array. Same shift semantics as `set_array_ref` on collision.

`db.set_array_scalar(parent, idx, value)`

### Reading elements

Point-lookup navigation — return the value at a specified slot. Not queries in any SQL sense; these are the equivalent of subscript access on a hash or array. Higher-level "walk the graph" traversal is composed from these plus the iterators.

Return shape is uniform: the value is a `collection_pk` (integer) if the slot holds a collection reference, or the inline scalar value (Lua nil / boolean / number / string) if the slot holds a scalar, or `nil` if the slot is empty. Callers who need to distinguish "empty slot" from "slot holding a null scalar" use a separate predicate — that predicate is left for a later design pass; V1 collapses both cases to `nil` matching Ruby / Lua idiom for hash access.

#### `get_hash_element`

Read the value at a key in a hash.

`db.get_hash_element(parent, key) → collection_pk | scalar | nil`

#### `get_array_element`

Read the value at an idx in an array. Same return shape as `get_hash_element`.

`db.get_array_element(parent, idx) → collection_pk | scalar | nil`

#### `get_hash_length`

Number of entries in a hash. Simple count of `relationships` rows under that parent.

`db.get_hash_length(parent) → integer`

Raises if `parent` isn't a hash — the method name declares the caller's type expectation; array parents use `get_array_length` instead.

#### `get_array_length`

**Highest occupied idx + 1**, matching Ruby array semantics. A sparse array where you set `$arr[1000] = 'foo'` reports length `1001`, not `1`. Zero if the array is empty.

`db.get_array_length(parent) → integer`

Raises if `parent` isn't an array. Distinct from `get_hash_length` because the semantic is different: hashes count entries; arrays report the addressable extent.

Under the hood these are two different SQL shapes — hash length is `select count(*) from relationships where parent = ?`, array length is `select coalesce(max(idx) + 1, 0) from relationships where parent = ?`. Both hit the same `relationships_parent` index; both are O(log N).

If a caller genuinely wants "how many populated slots does this array have" (count semantic on an array parent), that's a separate call — spec'd as `get_array_populated_count` if a workload asks for it, aspirational until then.

### Iterating collections

Three iterator methods that work uniformly on hashes and arrays. Each returns a standard Lua for-loop iterator (function, state, initial-control) so it drops straight into `for ... in`. Snapshot semantics — the iterator captures a view of the collection at call time via the temp-table pair (`iterators` and `iterator_elements`); subsequent mutations to the source don't affect the walk. Missing / gone rows on deref return `nil`.

Sparse array gaps are not yielded — iteration walks only populated slots. If a caller needs to enumerate every idx from 0 to `get_array_length - 1` including gaps, they loop with the length and call `get_array_element` per slot; that's a different access pattern from iteration.

Under the hood: each iterator method creates a row in the `iterators` temp table, populates `iterator_elements` in one INSERT, and returns Lua state that walks that snapshot. Cleanup on iterator finalization (Lua GC, explicit close, or transaction boundary) deletes the `iterators` row; the CASCADE FK drops the elements.

#### `keys`

Yields the keys of a collection. For a hash: string keys, in insertion order (which is the row's `idx`). For an array: the integer idxs of populated slots, in ascending order.

`db.keys(parent) → iterator`

~~~lua
for k in db:keys(pk) do
    -- k is a string (hash) or integer (array)
end
~~~

#### `values`

Yields the values of a collection. Each yielded value is a `collection_pk` if the underlying row is a reference, or the Lua-typed scalar if it's an inline scalar. Missing / GC'd targets yield `nil` at deref (same "structure-snapshot, live-value" behavior settled earlier).

`db.values(parent) → iterator`

~~~lua
for v in db:values(pk) do
    -- v is a collection_pk, a scalar, or nil (if the target went away)
end
~~~

#### `pairs`

Yields (key/idx, value) pairs — the combination of `keys` and `values` in one walk.

`db.pairs(parent) → iterator`

~~~lua
for k, v in db:pairs(pk) do
    -- for hash parent: k is string, v is collection_pk | scalar | nil
    -- for array parent: k is integer idx, v is collection_pk | scalar | nil
end
~~~

Name collides with Lua's built-in `pairs()` at the call site. Not a problem — `db:pairs(...)` is called as a method, resolved via the `db` handle, so it doesn't shadow the global. The proxy-layer metatable's `__pairs` hook will call this method under the hood so user code can write `pairs(some_proxy)` and get the same iteration.

### Deleting elements

#### `delete_hash_element`

Remove a key from a hash. If the removed row was a collection edge whose child collection is no longer reachable from root, the drain collects the child (and any subgraph that becomes unreachable with it).

`db.delete_hash_element(parent, key) → boolean`

Returns true if a row was removed, false if `(parent, key)` didn't exist.

#### `delete_array_element`

Remove an idx from an array. **Every sibling with a higher idx shifts down by 1** to close the gap. Ruby-array semantics for `arr.delete_at(N)`. GC behavior as above.

`db.delete_array_element(parent, idx) → boolean`

Returns true if a row was removed, false if `(parent, idx)` didn't exist.

**Sparseness is preserved, not collapsed.** If the array was sparse before the delete (e.g., `[a=0, b=1000]`), deleting idx=0 gives `[b=999]`, not `[b=0]`. Each surviving element's idx decreases by exactly the number of deletes at positions below it. Sparse structure survives; dense arrays stay dense.

The shift-down happens in Lua (`Db:_shift_down_array`) via a two-phase 10^18 hop — the same safe-range pattern the shift-on-update trigger uses for inserts. No dependency on SQLite planner row-processing order.

Hashes take the opposite semantic: `delete_hash_element` leaves a gap in idx. Hash users interact by key, so the gap is invisible to them.

### Transactions

#### `atomic`

Run a function atomically. Any Fiona API calls inside commit together on success, roll back together on error. Nests correctly via SQLite savepoints — inner calls stack their own savepoints and defer commit/rollback to the outer level.

`db.atomic(fn) → any...`

The block form owns the scope: rollback on any raised error is automatic, no `commit` call needed for the happy path. Whatever `fn` returns is passed through unchanged.

The outermost `atomic` boundary is what triggers the GC drain — every user-observable transition ends with `needs_trace` and `in_trace` fully cleared. See [Garbage collection](#garbage-collection) below.

Idiomatic use is grouping "create a collection, anchor it" so no orphan is ever observable between the two:

~~~lua
db:atomic(function()
	local pk = db:add_hash()
	db:set_hash_ref(parent, "k", pk)
end)
~~~

Every mutating public method already wraps itself in an implicit `atomic`, so bare calls also benefit from the drain-at-boundary guarantee. Wrapping multiple calls in `atomic` promotes them into one savepoint.

### Garbage collection

Fiona collects orphaned collections via a Drinian-style backward trace, driven in Lua at the outermost `atomic` boundary. Not directly callable — GC runs automatically.

**How it works.** On every relationship delete or child-swap, a mark trigger sets `needs_trace = 1` on the collection whose incoming edge just went away (root skipped — never a valid seed). The drain then loops: pick a seed via the partial index, mark it and every collection that reaches it (via a recursive-CTE UPDATE that walks upward through `relationships.parent`), and check whether root ended up marked. Root marked → seed is anchored, clear the flags. Root not marked → the whole closure is unreachable, either bulk-deleted (no callback registered) or processed one-at-a-time by the delete-as-you-go loop (callback registered). FK cascade drops outgoing edges; the mark trigger fires on each cascade delete and the outer loop picks up the next seed.

**No depth cap.** The Lua loop iterates rather than recurses, so `SQLITE_LIMIT_TRIGGER_DEPTH` (default 1000) doesn't apply. Chains millions deep are collectible in principle; the practical bound is memory for the CTE's worklist and Lua-loop time per collected collection.

**Cycles.** A fully-detached cycle collects in one drain pass: propagation from any cycle member marks the whole cycle, root is not in the closure, everything in the closure is deleted.

**Callbacks.** A caller can register a per-db close hook via `db:on_gc(fn)` — see [on-gc](./on-gc) for the full mechanism (parent-first ordering via the `in_trace_counter`, the auto-mark trigger that keeps callback-created collections in-trace, and the `db:gc_errors()` accumulator).

**Assertion on exit.** After the loop, the drain asserts `select count(*) from collections where needs_trace = 1 or in_trace is not null` is 0. This is what "no committed state ever carries a mark" comes down to — the transaction commits with the flags clean or raises loudly.

### Introspection

#### `meta`

Return every row of the meta table as a flat hash keyed by the row's `key` column.

`db.meta() → hash`

Fresh DB carries one row:

~~~lua
{schema = '2.0'}
~~~

The method is a thin projection over the meta table, not a hand-maintained list of fields.

**Why just the meta table, not runtime / DBMS info too.** Runtime info (the mode string, the file path) lives on the handle itself and doesn't belong in a method whose name suggests "stored metadata." DBMS info is trivial to query directly from SQLite when needed. If a grouped summary earns its keep later, it can land as a separate method with a name that says so.

#### `is_hash` / `is_array`

Cheap type probes for a given `collection_pk`. Return `true` iff the row exists and matches the requested type; return `false` for both a wrong-type row and a nonexistent pk.

`db.is_hash(pk) → boolean`

`db.is_array(pk) → boolean`

Callers use these to disambiguate what a bare `collection_pk` refers to — most useful inside an `on_gc` callback where the handle's origin varies. The mirror methods on the callback's handle (`handle:is_hash()` / `handle:is_array()`) close over the type field so no extra query fires.

### GC callbacks

#### `on_gc`

Register a per-db close hook. The function fires once per collection about to be deleted by the drain, in parent-first order.

`db.on_gc(fn)` — one at a time; re-registering replaces. `db.on_gc(nil)` clears.

The callback receives a proxy handle: `.pk` and `.type` are direct fields; `handle[key]` and `handle[idx]` read the collection's entries; `#handle` is its length; `pairs(handle)` walks its entries. See [on-gc](./on-gc) for the full mechanism (parent-first ordering, auto-mark trigger for callback-created collections, and the "no resurrection" semantic).

#### `gc_errors`

`db.gc_errors() → list`

Returns the accumulator of errors raised by the callback during the most recent drain. Each entry is `{collection_pk, message, trace_order}`. The list clears at the start of every drain — a long list is a smell, and programs that snapshot at shutdown can check this before committing.

### Handles

The raw db API is method-based: `db.set_hash_scalar(t, "foo", "bar")`, `db.get_hash_element(t, "foo")`. Handles wrap a `collection_pk` in a Lua table with metatable magic so a collection looks like a regular Lua hash or array.

`db.collection(pk) → handle`

Returns a handle for the collection at `pk`. Raises if `pk` doesn't exist.

The handle supports the natural Lua idioms:

- `handle.foo` — reads a hash element. Scalars come back as raw Lua values (string, number, boolean). Refs come back as a fresh handle, so `handle.child.foo` chains naturally through nested structure.
- `handle.foo = "bar"` — writes a hash scalar.
- `handle.foo = other_handle` — writes a hash ref (extracts the target `pk` from the given handle).
- `handle.foo = nil` — deletes the hash key.
- `handle[3]` / `handle[3] = "x"` — same three cases for arrays. Indexes are 0-based, matching the rest of the Fiona API.
- `#handle` — length. `get_hash_length` for hashes, `get_array_length` for arrays.
- `pairs(handle)` — iterates entries; refs come back wrapped.
- `handle.pk`, `handle.type` — direct accessors for the underlying `collection_pk` and type string (`'h'` or `'a'`).
- `handle:is_hash()`, `handle:is_array()` — type predicates.
- `handle1 == handle2` — true iff both wrap the same `collection_pk`.
- `tostring(handle)` — debug form: `"fiona.collection(pk=…, type=…)"`.

**Reserved fields.** `pk`, `type`, `is_hash`, `is_array` are handle-owned names. Reads return the handle's own value; writes raise (they can't accidentally overwrite the underlying pk or class). A hash key that happens to collide with one of these — a user hash that legitimately wants a key called `"pk"` — must be reached via the raw db API: `db.get_hash_element(handle.pk, "pk")` reads it, `db.set_hash_scalar(handle.pk, "pk", value)` writes it.

**When to use handles vs the raw API.** Handles are ergonomic for code that reads and writes named fields naturally (`handle.name`, `handle.child.id`). The raw API stays useful for bulk operations, code that already has the `pk` in hand, and situations where handle allocation per read would show up as pressure.

## Aspirational — not implemented yet

The following methods are spec'd but not present in the current interface. Landing them is a straightforward addition when demand shows up.

### `append_to_array`

Add a value to the end of an array. Convenience over `set_array_ref` / `set_array_scalar` — picks the next idx so the caller doesn't have to. Polymorphic on value: a `collection_pk` (returned by `add_hash` / `add_array`) is anchored as a reference; a Lua scalar is stored inline.

`db.append_to_array(parent, value)`

The ref-vs-scalar disambiguation here is trickier than in the `set_*` methods because it can't be done by choosing a method name. A wrapper (`db.ref(pk)`) or a typed marker is the likely path if this lands.

### `full_sweep`

Safety valve. Delete every collection not reachable from root via a full top-down trace. Expensive — walks the entire graph. The ordinary drain runs at every atomic boundary and keeps orphans from accumulating in the normal flow; `full_sweep` is what you run if something bypasses that path or leaves the DB with orphans anyway (e.g., raw SQL that skipped the API). Ideally never needed.

`db.full_sweep()`

### `normalize_hashes`

Renumber every hash-parented relationship to dense 0..n-1 per parent, in current idx order. Insertion order preserved; idx values become dense.

`db.normalize_hashes()`

**Primary reason to call this: developer sanity.** Insert/delete churn on long-lived hashes leaves scattered idx values (delete leaves gaps; append picks max+1). If you're inspecting the database directly and reasoning about entries with idx values like `12`, `487`, `9204`, `88301`, an occasional normalize resets everything to `0`, `1`, `2`, `3` for a readable view. No functional benefit for the running program — hash users interact by key, not idx — but a big quality-of-life win when a human is looking at the data.

Secondary reason: on cosmological timescales of insert/delete churn, drift could theoretically approach the 10^18 shift-safe boundary. This resets that too. Not a real-workload concern.

**Arrays are deliberately untouched.** Users control array idx directly (including sparse patterns like `$arr[100_000] = 'b'`), and auto-normalization would collapse those deliberate layouts. If a specific array needs its idx values reset, the caller does it manually.

**Implementation note.** A naive per-parent `update relationships set idx = row_number() over (order by idx) - 1 where parent = ?` would depend on the SQLite planner processing rows in ascending idx order — empirically stable but not a written contract. The two-phase 10^18 hop pattern (already used by the shift-on-update trigger and `_shift_down_array`) is the order-independent alternative and the expected implementation.
