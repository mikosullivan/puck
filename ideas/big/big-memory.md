# Big memory

~~~vibecode
{"vibecode": {
	"doc": "ideas_big_memory",
	"role": "brainstorm doc for a Caspian primitive where structured data lives in a database but Caspian code accesses it as if it were ordinary in-memory objects. Reading a member of a stored hash reads through to the DB; nested hashes hand out their own live references; writes flow back. The store's shape is a graph, not a tree — sharing across parents is native — which matches how in-memory object graphs actually look. Starts with a prior-art survey of systems that already do this shape.",
	"status": "idea — just prior-art notes so far. NOT V1 scope — spitball only. No implementation plan, no promotion path to requirements/ implied."
}}
~~~

**Not V1.** Exploratory. Nothing here is committed for V1; nothing has a promotion path to `requirements/` implied.

## The concept

A `bighash` (working name) is an object that **references a structured value in a database** and behaves like an ordinary `Hash` from the outside. The actual data lives in the DB, not in memory. Reading a member (`$doc['users']`) returns another live reference — if the member is itself a hash, you get another bighash; if it's a leaf value, you get the value. Nested access (`$doc['users']['alice']['email']`) walks down through DB reads without ever materializing the whole structure.

Writes flow the other way: `$doc['users']['alice']['email'] = 'new@example.com'` updates the DB. The developer never calls a `.save()` or `.fetch()` method; the persistence is invisible.

The store behaves like memory that survives process restarts — hence the name. Same "value that lives somewhere else" spirit as [bigstring](big-string), applied to structured data instead of a byte sequence. JSON is one possible export format for what a bighash holds, but it's not the storage shape; the storage shape is a graph of hashes, arrays, and scalars with arbitrary sharing between them.

## Prior art — small graph databases

Fiona's shape is essentially a (subject, predicate, object) triple store — parent / key / child in Fiona's terms. That's a well-trodden shape; several existing systems could plausibly back a bighash. Caspian is like Mighty Mouse: small but powerful. So the survey prefers small candidates that punch above their weight, and skips the heavyweights that would drag in a stack to solve a two-table problem.

### SQLite as substrate

The simplest option isn't a graph DB at all: SQLite with the Fiona schema (`hsa` + `relationships`) laid over it. SQLite is embedded, sub-MB, ubiquitous, single-file. Recursive CTEs handle graph walks (mark-and-sweep, reachability queries) natively. Fiona's two-table decomposition is straight-line SQL; the driver is a few hundred lines.

Not a graph DB per se — it's SQL underneath — but arguably the strongest candidate on Mighty Mouse grounds. Caspian is likely to depend on SQLite for other things already ([mvm-sqlite](mvm-sqlite) explores it as MVM's backing store), so this adds no new dependency.

### Embedded triple stores

RDF triple stores are the structural cousins of Fiona: rows are (subject, predicate, object) — the same shape as (parent, key, child).

- **[Redland / librdf](https://librdf.org/).** Small C library. Multiple backends (memory, SQLite, BerkeleyDB, MySQL). Dates from 2000; mature and small. C API; bindings for many languages. Low activity in recent years.
- **[Oxigraph](https://oxigraph.org/).** Modern pure-Rust triple store with SPARQL 1.1. Embeddable via library API or standalone server. RocksDB or SQLite backing. Small, well-tested, actively developed.
- **[rdflib](https://rdflib.readthedocs.io/).** Pure Python triple store. Small, well-established, in-memory or SQLite-backed. Not a Caspian fit (Python) but useful reference.

Trade-off: RDF's SPARQL query language is expressive but heavy — probably more than a bighash driver needs. Adopting an RDF store means importing a query engine and vocabulary you don't have a use for.

### Embedded property graph DBs

Property graphs (nodes + typed edges + per-edge attributes) are close to what Fiona needs, though the attribute-per-edge model has more complexity than Fiona's simpler triple.

- **[CozoDB](https://cozodb.org/).** Rust, embeddable. Datalog query language. Works over SQLite, RocksDB, or its own storage. Modern, small, actively developed.
- **[KuzuDB](https://kuzudb.com/).** C++, embeddable. Cypher-like query language. Positioned as "DuckDB for graphs" — same in-process, analytic-friendly angle. Small footprint; young project but active.
- **[Cayley](https://github.com/cayleygraph/cayley).** Go, small, embeddable. Backends include BoltDB, LevelDB, PostgreSQL, MongoDB, in-memory. Originally Google's; multiple query languages (Gizmo, GraphQL, MQL). Development is slow but code is stable.

Trade-off: again, full query language + schema flexibility beyond what a bighash driver needs.

### What's not on the list

Not considered — too big for Mighty Mouse:

- **Neo4j.** JVM, hundreds of MB, server-oriented. Embedded mode exists but the runtime footprint is against Caspian's grain.
- **Apache Jena TDB.** Java, sizable.
- **DGraph, JanusGraph, TigerGraph, Amazon Neptune.** Distributed, server-based, or cloud-hosted. Solving a bigger problem than a bighash needs.
- **ArangoDB, OrientDB, SurrealDB.** Multi-model DBs; graph is one facet of a much larger surface.

### Takeaway

For a bighash backing store, roughly in preference order:

1. **SQLite with the Fiona schema.** Smallest dependency (very likely zero-new-dependency since Caspian already touches SQLite), direct fit, tiny driver. Recursive CTEs cover the graph-walk operations. Probably the right answer.
2. **Oxigraph** or another small RDF triple store — if RDF / SPARQL earns a place elsewhere in Caspian. Otherwise oversized for this one need.
3. **CozoDB** or **KuzuDB** — if property-graph query languages (Datalog, Cypher) earn a place elsewhere. Same "solves more than we're asking" caveat.

Every purpose-built graph DB brings more than a bighash driver needs — a query language, a schema system, indexes for query patterns we don't have. Custom-writing on SQLite is the Mighty Mouse answer: small, well-understood, exactly the right size for the schema.

## Fiona as a candidate backing model

There's a Miko-authored precedent that fits this shape almost exactly: **Fiona**, a DBMS Miko once designed. Full notes at [fiona](../fiona). The structural match to a bighash is unusually good — worth serious consideration as the storage substrate rather than reinventing.

### The structural match

Fiona decomposes any structured value into two tables:

- **`hsa`** (hashes-scalars-arrays) holds primitives. Each row is one immutable value — a scalar, or the identity of a hash / array. A row's ID is the identity of that primitive.
- **`relationships`** holds the structure. Each row maps `(parent_hsa_id, key) → child_hsa_id` (or `(parent_hsa_id, index) → child_hsa_id` for arrays). A hash with N keys has N relationship rows.

Reading `$doc['users']['alice']['email']` becomes three relationship lookups plus one final `hsa` fetch for the leaf value. None of the intermediate hashes are ever materialized as in-memory structures.

That IS the bighash pattern, expressed as a schema.

### Graph, not tree

JSON is a tree: every value has exactly one parent. If two hashes need to share a sub-hash, JSON has no way to express it — you either duplicate the subtree (losing identity) or invent a reference syntax that most JSON tools don't understand.

Fiona is a graph. Multiple `relationships` rows can point at the same `hsa_id`, so any value — scalar, hash, or array — can have any number of parents. Sharing is native; no special syntax needed.

This matches how objects work in memory. Two variables that reference the same object see the same changes. Two hashes that both hold a reference to the same sub-hash see each other's mutations to that sub-hash. Under Fiona, a bighash inherits the property naturally: if `$a['x']` and `$b['y']` both point at `hsa_id = 42`, then `$a['x']['new_key'] = 'v'` inserts a relationship row with `parent = 42` — and `$b['y']` sees the new key on its next read. No special handling required; it falls out of the schema.

This is why "big memory" is the accurate framing and "big JSON" wasn't. What a bighash stores is a graph of hashes, arrays, and scalars with sharing anywhere it makes sense — a strict superset of what JSON can represent, and exactly what an in-memory object graph looks like. JSON is at best an export format for a subset of what the store holds.

### What a bighash on Fiona looks like

A `bighash` is a lightweight in-memory handle carrying two things: an `hsa_id` and a driver reference. Every hash-shaped operation translates to relationship queries against that ID:

| Caspian operation | Fiona query |
|---|---|
| `$bh['key']` | `SELECT child_hsa_id FROM relationships WHERE parent = $id AND key = 'key'` → wrap the result as a bighash (if compound) or return the primitive |
| `$bh.keys` | `SELECT key FROM relationships WHERE parent = $id` |
| `$bh.has_key?('key')` | `SELECT 1 FROM relationships WHERE parent = $id AND key = 'key' LIMIT 1` |
| `$bh.size` | `SELECT count(*) FROM relationships WHERE parent = $id` |
| `$bh.each` | `SELECT key, child_hsa_id FROM relationships WHERE parent = $id ORDER BY key` — stream results, wrap each child |
| `$bh['key'] = 'v'` | delete the existing relationship row (if any); insert a new relationship row pointing at either an existing `hsa` row for `'v'` or a newly-inserted one |
| `$bh.delete('key')` | delete the relationship row |

Deep access falls out of composition — `$bh['a']['b']['c']` is three of the first-row queries chained.

**Mutations are local.** Setting `$bh['a']['b']['c'] = 'v'` only touches the `hsa` and `relationships` rows involved in that leaf — no ancestor rows need to be rewritten. This is a direct consequence of Fiona's rule: a hash's identity is its `hsa_id`, not its contents, so adding or removing its relationship rows changes what the hash "contains" without changing the row that IS the hash. No path-copy-to-root, no Merkle-tree-style upward rewrite.

### The write model

Fiona's rule is row-level: no UPDATE, only INSERT and DELETE. That maps directly to bighash mutations:

- **Setting a key.** DELETE the old relationship row (if any); INSERT a new one pointing at the value's `hsa` row. If the value is a scalar not already in `hsa`, INSERT it there first (or reuse an existing scalar row with the same value if the driver interns).
- **Deleting a key.** DELETE the relationship row. The `hsa` row it pointed at stays — some other hash may still reference it. Orphan cleanup is a separate garbage-collection concern.
- **Replacing a subtree.** DELETE the relationship row from the parent; INSERT a new one pointing at the new subtree's root `hsa_id`. The old subtree's rows stay reachable until nothing references them.

**One open decision: scalar wiggle room.** [fiona § Overview](../fiona#overview) flags the possibility of UPDATEing scalar rows in `hsa` in place. Applied to a bighash: setting `$bh['count'] = 42` could either follow the strict rule (INSERT a new `hsa` row for `42`, rewire the relationship) or take the shortcut (UPDATE the existing scalar row's value in place). The shortcut is cheaper for hot paths that update numeric counters and the like; it costs the "the row you have a reference to is still what you last read" property for scalars. Worth deciding early — it affects both storage cost and observable semantics.

### Root anchor and garbage collection

Fiona as documented has no privileged row — any `hsa_id` can exist independently, and any of them could be a "top" of some structure. For a bighash used as a Caspian process's persistent state, that needs an addition.

**One designated root hash that cannot be deleted.** Everything else in the store must descend from it — reachable through some chain of `relationships` rows starting at the root's `hsa_id`. Anything not reachable is garbage.

Concretely:

- The root is a well-known `hsa_id` (say, always `1`) or a distinguished entry in a small `roots` table.
- User code never deletes the root — the operation isn't offered on it.
- Adding data means attaching it via `relationships` somewhere in the graph reachable from the root.
- Detaching data (deleting a relationship row) doesn't immediately delete the sub-graph — the `hsa` rows and their downward `relationships` stay until GC. If another parent still references them, they stay indefinitely — [Graph, not tree](#graph-not-tree) applies.

**Garbage collection: mark-and-sweep from the root.** Walk every relationship reachable from the root's `hsa_id`; mark every `hsa` row touched; delete every unmarked `hsa` row and its downward `relationships`. Refcounting would be simpler per-write but doesn't handle cycles; mark-sweep handles cycles correctly and matches how object graphs actually get shaped in practice.

Implications:

- **Store size stays bounded.** No orphan accumulation. Storage tracks the reachable graph, not the historical high-water mark.
- **No manual cleanup discipline required.** Developers don't have to remember to delete a sub-hash they're done with — dropping the last reference is enough; GC finds it.
- **Cycles are safe.** Two hashes that reference each other but are otherwise unreachable get collected together. Refcount would leak them.
- **`.delete` becomes simpler.** `$bh.delete('key')` removes the relationship row and returns; whether the pointed-at `hsa` row survives depends on whether anyone else still references it. GC decides later.
- **Snapshot-and-revive gets easier.** Serializing "the store from the root down" is well-defined — one obvious answer to "what's in the store."
- **When to run it.** Same design axis every GC faces: background/incremental (steady work, no pauses), stop-the-world (bounded cost per run, occasional latency spikes), on-demand (developer or transaction boundary triggers it). Fiona-flavored bighash probably wants an incremental default with a manual `%engine.gc` escape hatch — the [no-nanny-code](https://puck.uno/documentation/overview#no-nanny-code) principle suggests exposing the trigger rather than hiding it entirely.

**Open: one root or many?** Simplest is one anchor per Fiona-backed store. A step up is a named-roots table (`roots(name PRIMARY KEY, hsa_id)`) so a single store can host multiple independent bighashes. Multiple roots don't change the GC story — mark from all named roots instead of one.

### Auxiliary tables: derivable, per-driver

Two tables (`hsa` + `relationships`) are the **canonical** representation — the source of truth. But nothing stops a driver from adding auxiliary tables that make specific operations faster. The principle: **auxiliary tables are always derivable from the canonical two.** Drop them and you can rebuild them; corrupt them and you lose speed, not data.

Examples worth keeping in the back pocket:

- **GC backpointer index.** For each `hsa_id`, cache the list of relationship rows pointing AT it. Mark-and-sweep from the root uses `relationships` forward; incremental GC on `.delete` uses this reverse index to decide "is anyone else still referencing this?" without a full walk.
- **Scalar interning index.** Hash → `hsa_id` lookup for scalar rows, so `$bh['count'] = 42` finds the existing `hsa` row for `42` in O(1) instead of scanning `hsa`. The "sharing / interning falls out" bullet in [What Fiona brings](#what-fiona-brings-that-other-candidates-dont) implicitly assumes this.
- **Roots table.** Already mentioned in [Root anchor and garbage collection](#root-anchor-and-garbage-collection) — a small `roots(name PRIMARY KEY, hsa_id)` for named-root discovery. Formally an auxiliary table.
- **Class-instance index.** For each class, the set of `hsa` rows that are instances of it. Enables "find all instances of `MyClass`" without walking the graph. Useful for migrations, admin queries, debugging.
- **Snapshot / version markers.** For time-travel or multi-snapshot storage, a small table mapping snapshot ID to root `hsa_id`.

The payoff is that per-driver / per-workload optimization stays out of the Fiona spec entirely. A SQLite driver ships with the interning index and roots table (small overhead, big wins). A MongoDB driver skips the interning index because Mongo indexes handle it natively. A Postgres driver adds a materialized view for common analytical queries. All present the same bighash API; the spec stays two tables.

The discipline: writes have to keep auxiliary tables consistent with the canonical form. Same problem RDBMSes solve with triggers or with the query planner owning both. Fiona drivers own it themselves — every mutation touches whichever auxiliary tables need updating. If a driver forgets one, worst case is a stale-index bug, not data loss (rebuild from the canonical two).

### What Fiona brings that other candidates don't

- **Native to Miko's mental model.** The [immutable-objects, mutable-relationships](https://puck.uno/ideas/fiona#ideas-worth-carrying-forward) framing is already how Miko thinks about data — the design isn't grafted on. Every other candidate needs conceptual translation to fit.
- **Right-sized surface.** Every graph DB in the survey brings a query language, a schema system, and indexes for query patterns Fiona doesn't need. Fiona is two tables and a small vocabulary of INSERT / DELETE. Nothing left over for a bighash driver to ignore.
- **Every intermediate is a first-class value with an ID.** A subtree isn't a "chunk of the parent doc" — it's an `hsa` row in its own right, referenceable, shareable, comparable. That means `$bh['users']` can be passed around, stored elsewhere, compared for identity, without special casing.
- **Sharing / interning falls out.** Two hashes with the same contents naturally converge on the same `hsa` ID (if the driver de-dupes on insert). Structural sharing is default, not a bolt-on.
- **Small primitive set to implement.** Only two tables. The whole thing fits in a few hundred lines of driver code plus the schema.

### What stays open

- **Which immutability stance** (structural sharing vs mutable relationships). Both viable; each carries a different developer story.
- **Indexes and query patterns.** Reading `$bh['key']` is a keyed lookup — cheap. Reading "all bighashes where `.status == 'active'`" is a query against value-typed relationships and needs indexes designed for it.
- **Backing store.** Fiona is described abstractly (two tables). The actual store could be SQLite (single-file, familiar), Postgres (server-based, indexed), an mmap'd custom format, or something else. Same schema; different substrates.
- **How this composes with [mvm-sqlite](mvm-sqlite).** Both propose an abstract-storage layer; Fiona could be one driver in that shape, or MVM could be built on top of Fiona. Worth a design pass to see which subsumes which.

## The non-serializable-reference question

If MVM ever becomes Fiona-backed (or any-DB-backed), every value it holds has to be serializable — either directly (scalars, hashes, arrays, refs to other things in MVM) or via some convention that keeps non-serializable state elsewhere. The current spec is silent on the specifics. This is an open design question that has to get answered before the Fiona swap can happen. Spitballing.

### The scenario

A Caspian class holds a field that references a native resource — a socket handle, a file descriptor, a foreign-library pointer, protected memory, a timer, a callback registered with the OS. That resource cannot become a row in Fiona; it exists in the host process. What happens when the runtime tries to serialize an instance of that class?

### Approaches to detection

How does the runtime know a field is unserializable in the first place?

- **Class-declared.** Developer marks fields as transient (`field :handle, class: 'socket', transient: true`) or supplies a custom `.serialize` hook. Serializer trusts the declarations; anything not marked is assumed serializable.
- **Type-based.** Certain classes are registered as unserializable (e.g., `core:socket`, `core:file_handle`). Serializer refuses or skips any field of those types. No per-class declarations needed.
- **Runtime-detected.** Serializer tries to encode every value and only fails when it hits something it can't encode. The "type-based" registry is implicit in the encoder's behavior.
- **Registered driver.** Every native-resource class ships a driver that answers "am I serializable?" and "if so, how?". Serializer consults the driver, not the class directly. Cleaner separation of policy from implementation.

### Approaches to response

What happens when the serializer finds an unserializable value?

- **Loud refuse.** Raise at serialize time. "Class `X` has unserializable field `@socket` — mark it transient, add a serialize hook, or don't hold this here." Forces an explicit decision at the moment of the mistake. Friendliest to debugging; harshest to accidental snapshots.
- **Silent placeholder.** Store `null` or a "broken reference" marker. Serialization succeeds; revive gives you an object with the field cleared. First attempt to use the cleared field raises. Friendliest to snapshots that don't happen to touch the broken field.
- **Auto-transient with warning.** Skip the field silently but log to a `state.gc_errors`-style engine list. Developer sees the log; program keeps running. Middle ground; the "argument happens" without blocking the operation.
- **Coerce via reconstruct spec.** If the class supplies a `.reconstruct($spec)` hook, serialize a spec (e.g., `{path: '/tmp/foo.log', mode: 'a'}`) and reconstruct on revive. If no hook, fall back to one of the above.
- **Freeze the instance.** Mark the whole instance as read-only post-serialize. Rare fit, but suits classes that expect "you're done modifying this now."

### The prevention alternative

A different shape from the previous conversation: **never let a non-serializable value into MVM in the first place.**

Under this model:

- Every value that lives in MVM is serializable, by construction. No exceptions.
- Native resources live in a host-engine sidecar (a Lua-side table, or wherever the host keeps its own state) keyed by IDs.
- Caspian classes that need a native resource hold an ID into the sidecar, not the raw resource. The ID is a plain string; the sidecar isn't in MVM.
- The methods that create native resources (`%net.tcp_connect`, `%fs.open`, etc.) return wrapper objects that ARE serializable — they hold IDs, not handles.

The discipline is enforced at the engine boundary: the API surface makes it impossible to accidentally get a raw handle back. If it always comes wrapped, it always stays serializable.

Consequences:

- **Serialization becomes trivial.** Every value already IS serializable; the serializer never encounters a non-serializable thing because none exist in MVM.
- **Revive is harder.** The IDs in the revived MVM point at sidecar entries that don't exist yet. Either the class's `on_revive` hook re-establishes the sidecar entry from a stored spec, or the wrapper raises on first use ("this handle didn't survive revival — reconnect explicitly").
- **The wrapper-class boundary is a real API surface.** Every native-resource-returning method has to be spec'd this way. Retroactively wrapping is painful; getting it right from the start is fine.

### Contexts matter

Not every "serialize" is the same, and the right default may vary by context:

- **Snapshot-and-revive** (process pauses, resumes elsewhere later). Reconstructibility matters — the resource has to come back or the program breaks. Loud refuse is probably right.
- **Swap-to-Fiona-backing** (in-process, live migration). References to raw handles might still be reachable from Lua-side code that manages them; the MVM-visible state is what changes storage. Silent placeholder plus a sidecar mapping might be acceptable.
- **Snapshot for debugging** (dump state to inspect). Reconstructibility doesn't matter; you want to see what was there. Silent placeholder is fine; loud refuse would be annoying.
- **Cross-process message** (Puck). The peer doesn't have the sidecar. Loud refuse or spec-based reconstruction; silent placeholder would silently break the peer.
- **Big-process overflow** (evict cold state to disk). The state comes back; the resource might not. Deferred / on-revive-check pattern fits.

A single global default might not be right. A per-context policy — the runtime asks "which context am I in?" and picks the response accordingly — is more flexible but adds machinery.

### A candidate direction

Not decided. What seems to fit best across the axes:

- **Prevention as the primary discipline.** Native resources always come wrapped; IDs live in MVM; raw handles never do. This makes the common case invisible — MVM is trivially serializable because it never holds a raw handle to begin with.
- **Loud refuse as escape-hatch enforcement.** For the case that slips through (someone writes a class holding Lua-userdata directly, or a class holding a wrapper but assuming the wrapper's cached state matters), the serializer raises at snapshot time. Points at the exact mistake; matches the fail-loudly-early principle.
- **`on_revive` for reconstruction.** Class-level hook, revised from the current spec's redaction-only framing to include "re-establish sidecar entry from stored spec." Same hook; broader use.

The wrapper discipline is the load-bearing part. Get it right at the API boundary and the rest is small. Get it wrong and every future context (snapshot, Fiona swap, distributed MVM, big-process overflow) has to reinvent the escape hatch.

Worth arguing.

