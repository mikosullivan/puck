# SQLite implementation

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_spec_sqlite",
	"role": "SQLite implementation of Fiona — the on-disk layer and the callable method surface on a Fiona db handle. The [schema](./schema/) is the source of truth for tables, constraints, and triggers; this page catalogs the methods. Conceptual model lives at ../../.",
	"status": "stub"
}}
~~~

SQLite implementation of Fiona — the concrete DBMS layer under Fiona's conceptual model at [../../](../../).

## Functions

Top-level functions — things you call before you have a `db` handle.

### `get_db`

Return a database handle backed by SQLite. Every method under [Methods](#methods) is called on this handle.

`get_db(path, mode) → db`

**`path`** — a Lua string identifying where the database lives:

- A filesystem path (e.g., `'./fiona.db'`, `'/var/data/fiona.db'`) — a persistent database file.
- The literal string `':memory:'` — an in-memory database that vanishes when the handle is released. Useful for tests and ephemeral computation. This is SQLite's own convention.

**`mode`** — a required short string specifying the access mode. One of:

- `'r'` — read-only. File must exist; the returned handle raises on any method that would modify the database.
- `'rw'` or `'wr'` — read-write. Both directions allowed. Combines with create-if-missing.

No default. Callers must specify explicitly — makes intent visible at every call site and prevents accidental writes to a database opened for reading. Convention borrowed from C's `fopen()` mode string.

**No write-only mode in V1.** `'w'` is deliberately not accepted, even though the C `fopen`-style vocabulary would suggest it. Every write to a Fiona database has to read the root hash first to resolve where the write lands, so a strict write-only handle would be unable to perform any operation Fiona actually exposes. Removing `'w'` from the accepted set is a conscious V1 choice, not an oversight — if a genuine append-only use case surfaces (bulk load, log-style ingestion) and can justify the root-hash-read exception, `'w'` can be added back. Passing `'w'` today raises.

**`':memory:'` requires write permission.** An in-memory database starts empty and can't be populated without write access — opening one in `'r'` mode raises. Valid combinations for in-memory: `'rw'` or `'wr'` only.

**Lua parameter convention.** Both parameters are positional. Lua doesn't have named arguments natively; the convention when a function has many optional parameters is to accept a single table argument (e.g., `get_db{path = './fiona.db', mode = 'rw', timeout = 5}`). `get_db` has two required parameters and no optional ones for V1, so it stays positional. If future options land (connection timeout, custom pragmas), the natural extension is a third table-shaped argument.

**Startup logic.** `get_db` decides between three cases based on what it finds:

1. **Database has the Fiona schema** → open and use.
2. **Database has no tables** → apply the Fiona schema. Only valid in `'rw'` / `'wr'` mode; a fresh file opened in `'r'` mode raises (schema can't be applied read-only).
3. **Database has tables but they're not Fiona's** → raise. Prevents silently corrupting an unrelated SQLite file or opening a foreign DB as if it were Fiona.

Concretely:

1. Open (or create) the SQLite file via lsqlite3. In `'rw'` / `'wr'` modes, SQLite creates the file if absent (matching its own default). In `'r'` mode, a missing file raises.
2. Inspect the schema — check whether `hsa`, `relationships`, and `meta` tables are present.
   - All three present → case 1, open normally.
   - None present (and no other tables) → case 2, apply the schema at [../build/sqlite/lua/src/fiona.sql](../build/sqlite/lua/src/fiona.sql).
   - Any other combination (subset present, or unrelated tables present) → case 3, raise.
3. Set the required per-connection pragmas: `foreign_keys = on`, `recursive_triggers = on`.
4. Return the handle, tagged with the mode so its methods can enforce read/write restrictions.

**Schema matching depth.** Step 2 checks table presence by name only. Deeper verification (column types, constraint sets, trigger bodies, index presence) is not done at V1 — if `hsa`, `relationships`, and `meta` exist by name, they're assumed to be the correct Fiona schema. If this assumption ever becomes unreliable in practice, `get_db` can grow schema-fingerprint checking (e.g., verify `meta.version` matches expected). For V1, keep it minimal.

The tradeoff of auto-create is the "typo in the path silently produces an empty DB" case. That's a caller-side concern, not a `get_db` responsibility — matches SQLite's own choice and every other file-based DB library.

## Methods

### Adding HSA elements

Create hsa rows. Everything stored in a collection has to exist as an hsa row first; these methods return an hsa_pk the caller then wires into place via `set_hash_element`, `set_array_element`, or `append_to_array`.

#### `add_hash`

Create a new empty hash.

`db.add_hash() → hsa_pk`

#### `add_array`

Create a new empty array.

`db.add_array() → hsa_pk`

#### `add_scalar`

Create a new scalar. `st` is inferred from the Lua type of `value`: string → 's', number → 'n', boolean → 'b', nil → 'u'.

`db.add_scalar(value) → hsa_pk`

### Transactions

Group calls into all-or-nothing units, with arbitrary nesting. Load-bearing for the multi-step patterns (`add_hash` → wire, `add_array` → wire, etc.) that would otherwise leak orphaned hsa rows on a crash.

Nesting maps onto SQLite's SAVEPOINT mechanism. The first `transaction_start` on a connection issues `BEGIN`; subsequent nested calls issue `SAVEPOINT`. The API layer holds the per-connection stack; the backend just executes the primitives.

**Commit and rollback both exit the transaction they act on.** There is no commit-and-keep-going. Acting on an outer transaction from inside a nested one releases (or rolls back) every level between the current innermost and the target, then closes the target too.

Example — inside four nested transactions:

```
transaction a
    transaction b
        transaction c
            transaction d
                (commit a here)
```

That commit closes d, c, b, and a. You're outside all four.

**Auto-rollback on scope exit.** Explicit `transaction_rollback` is optional. If control leaves the scope in which the transaction was opened without a matching commit, the transaction is rolled back automatically. Explicit rollback stays available for early exit or clarity, but callers never have to write it in the happy path.

**Commit and rollback don't unwind control flow.** They close the target transaction (and any nested below it), then return. Execution continues at the next statement in the caller's block. Any DB operations after that point run under whichever transaction is now innermost — or in auto-commit mode if the rollback closed the outermost.

_Open question: how a caller identifies which transaction to act on — a handle returned by `transaction_start`, a caller-supplied name, or something else. Signatures below assume a returned handle as a placeholder._

_Open question: how the Lua layer detects "left the scope." Lua has no deterministic destructors, so this likely calls for a block-form primitive — something like `transaction(fn)` that owns the scope and rolls back on function return unless commit was called — alongside or in place of the bare handle-returning `transaction_start`._

#### `transaction_start`

Open a new transaction. Returns a handle identifying this level.

`db.transaction_start() → handle`

#### `transaction_commit`

Commit a transaction. Without a handle, commits the innermost open transaction. With a handle, commits that level and every nested level below it — you exit all of them.

`db.transaction_commit(handle?)`

#### `transaction_rollback`

Roll back a transaction. Same targeting semantics as `transaction_commit`. Also exposed as `transaction_exit` (alias with identical semantics) — since auto-behavior at end-of-block IS rollback, "exit the transaction" and "roll it back" are the same thing.

`db.transaction_rollback(handle?)`
`db.transaction_exit(handle?)`

### `query_hash`

Read the value at a key in a hash. Returns a scalar value if the child is a scalar, a handle if it's a collection, or a distinguished "not present" signal if the key doesn't exist.

`db.query_hash(parent, key) → value | handle | not_present`

### `query_array`

Read the value at an idx in an array. Same return shape as `query_hash`.

`db.query_array(parent, idx) → value | handle | not_present`

### `set_hash_element`

Write a value to a key in a hash. If the value is a scalar, creates a scalar hsa row and wires the relationship. If it's a handle to an existing hsa, wires the relationship only. Replaces if the key already exists.

`db.set_hash_element(parent, key, value)`

### `set_array_element`

Write a value to a specific idx in an array. Same value semantics as `set_hash_element`. If the idx is already occupied, the shift trigger opens room.

`db.set_array_element(parent, idx, value)`

### `append_to_array`

Add a value to the end of an array. Convenience over `set_array_element` — the API picks the next idx so the caller doesn't have to.

`db.append_to_array(parent, value)`

### `delete_hash_element`

Remove a key from a hash. Purge trigger reclaims the child if it had no other parents.

`db.delete_hash_element(parent, key)`

### `delete_array_element`

Remove an idx from an array. Purge behavior as above. **Every sibling with a higher idx shifts down by 1** to close the gap. Ruby-array semantics for `arr.delete_at(N)`.

`db.delete_array_element(parent, idx)`

**Sparseness is preserved, not collapsed.** If the array was sparse before the delete (e.g., `[a=0, b=1000]`), deleting idx=0 gives `[b=999]`, not `[b=0]`. Each surviving element's idx decreases by exactly the number of deletes at positions below it. Sparse structure survives; dense arrays stay dense.

The shift happens via the `relationships_shift_down_on_array_delete` trigger. The trigger relies on SQLite's planner processing the shift UPDATE in ascending idx order — a stable empirical behavior, not a written contract. A feature request to document that guarantee is pending upstream; regression tests catch it immediately if the planner ever changes.

Hashes take the opposite semantic: `delete_hash_element` leaves a gap in idx. Hash users interact by key, so the gap is invisible to them; the WHEN clause on the shift trigger excludes hash parents.

### `full_sweep`

Safety valve. Delete every hsa row not reachable from root via a top-down trace, using the same reachable-from-root CTE the purge trigger uses. Expensive — walks the entire graph.

The `relationships_purge_after_delete` trigger normally keeps orphans from accumulating in the ordinary flow; `full_sweep` is what you run if something bypasses that path or leaves the DB with orphaned rows anyway. Ideally never needed.

`db.full_sweep()`

### `normalize_hashes`

Renumber every hash-parented relationship to dense 0..n-1 per parent, in current idx order. Insertion order preserved; idx values become dense.

`db.normalize_hashes()`

**Primary reason to call this: developer sanity.** Insert/delete churn on long-lived hashes leaves scattered idx values (delete leaves gaps; append picks max+1). If you're inspecting the database directly and reasoning about entries with idx values like `12`, `487`, `9204`, `88301`, an occasional normalize resets everything to `0`, `1`, `2`, `3` for a readable view. No functional benefit for the running program — hash users interact by key, not idx — but a big quality-of-life win when a human is looking at the data.

Secondary reason: on cosmological timescales of insert/delete churn, drift could theoretically approach the 10^18 shift-safe boundary. This resets that too. Not a real-workload concern.

**Arrays are deliberately untouched.** Users control array idx directly (including sparse patterns like `$arr[100_000] = 'b'`), and auto-normalization would collapse those deliberate layouts. If a specific array needs its idx values reset, the caller does it manually.

**Same undocumented-planner-order dependency as `delete_array_element`.** The natural implementation of `normalize_hashes` is a single per-parent `update relationships set idx = row_number() over (order by idx) - 1 where parent = ?` — which relies on the planner processing rows in ascending idx order so each row's new slot is one that was just vacated by the row below it. Same empirically-stable, not-a-written-contract behavior noted under [`delete_array_element`](#delete_array_element). Any regression fires as unique-constraint violations in the normalize_hashes tests; the fix would be a two-phase hop through the 10^18 safe range, matching what the shift-on-update trigger does.

### `meta`

Return every row of the meta table as a flat hash keyed by the row's `key` column.

`db:meta() → hash`

**Return shape (V1, fresh DB):**

~~~lua
{schema = '1.0'}
~~~

The only row a fresh Fiona DB carries is `schema`, whose value names the schema version this file was built against. If future rows are added to the meta table, `meta()` picks them up automatically — the method is a thin projection over the table, not a hand-maintained list of fields.

**Why just the meta table, not runtime / DBMS info too.** An earlier draft grouped Fiona-side, handle-side, and SQLite-side info into `fiona` / `mode` / `dbms` sub-hashes. That's more machinery than V1 needs, and the `fiona` name overreached — the meta table describes the schema, not the whole Fiona package. Runtime info (the mode string, the file path) lives on the handle itself and doesn't belong in a method whose name suggests "stored metadata." DBMS info is trivial to query directly from SQLite when needed. If a grouped summary earns its keep later, it can land as a separate method with a name that says so.
