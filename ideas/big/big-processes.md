# Big processes

~~~vibecode
{"vibecode": {
	"doc": "ideas_big_processes",
	"role": "brainstorm doc for Caspian at the OTHER end of its design range — programs that manage a whole factory, hold billions of records, run for weeks, exceed any single machine's RAM. Frames the design principle (small language + pluggable storage) that ties together the recent pieces (bigstring, mvm-sqlite, %amber) and what would need to be added to complete the picture.",
	"status": "idea — spitball only. NOT V1 scope; nothing here has a promotion path to requirements/ implied."
}}
~~~

**Not V1.** Exploratory. Caspian ships small first; big-process shape earns its way in later, if at all.

## The other end of the spectrum

Caspian is designed small. Under 1 MB for the engine + stdlib + docs; fits on a floppy with room to spare. That's the primary design commitment.

**But nothing in the design forces smallness at the workload end.** With the right storage backing, the same Caspian language could run a factory: thousands of workstations, millions of sensors, billions of events per day, state that far exceeds any single machine's RAM. The program writes `$machine_42.temperature` and doesn't care whether that value is in memory, on disk, in a database, or on another host. The language surface stays simple; the storage decisions are engineering, not language.

Small language, big process. Not a contradiction — a consequence of separating storage from language.

## The design principle

**The language stays small; storage decisions become pluggable.**

Three of the recent idea threads are secretly building toward this:

- **[bigstring](big-string)** — strings that live on disk but act like values. `$doc.length`, `$doc.split("\n")`, `$doc.match(regex)` all work regardless of whether the string is 200 bytes or 200 GB. Backing is file-or-DB, transparent.
- **[mvm-sqlite](mvm-sqlite)** — runtime state itself becomes pluggable. CVM defines an abstract storage interface; a Lua-table driver ships for V1; a SQLite driver arrives when snapshot-and-revive or huge state calls for it.
- **[%amber](https://puck.uno/requirements/amber)** — ambient hash built on the aggregate-hash primitive. Same "composable storage tiers behind a value-shaped surface" pattern.

Each piece independently makes something small into something scalable-without-touching-the-language. Together they suggest a broader move: **every collection primitive gets pluggable backing.**

## What generalizing the pattern would look like

### BigHash, BigArray, BigObject

Same "on-disk value that acts like an in-memory value" shape as bigstring, applied to every collection primitive. Developer writes `$sensors['machine_42'].temperature`; runtime decides whether that reads from RAM, SQLite, mmap, or a remote store.

Construction sketches:

~~~caspian
$fits_in_ram = {}                                       # ordinary hash
$too_big = %('core:bighash').from_db('sensors.sqlite')  # DB-backed
$mmapped = %('core:bighash').mmap('sensors.mmap')       # mmap-backed
~~~

The API surface is identical. Iteration, subscript, key check, mutation — all work the same way on either.

### Lazy iteration by default

`.each` on a billion-entry BigHash streams rows, doesn't load. This probably wants to be the ambient iteration model — the language never assumes a collection fits in memory. Design question: is that a per-type API decision (BigHash streams, regular Hash materializes) or a language-level default (all iteration is lazy)? Lazy-by-default is simpler and safer; materialize-by-default is Ruby / Python's convention and easier to reason about.

### Query pushdown

`$sensors.filter { |s| s.reading > 100 }` should translate to `WHERE reading > 100` when the backing is a DB, not "pull every entry into RAM, run the block, discard non-matches." This is the hard problem: compiling a Caspian block into SQL.

Some subset of blocks is safely translatable — pure comparison / boolean expressions over primitive-typed fields. Blocks that call methods, access ambient state, or perform I/O can't be pushed down. The runtime would need to distinguish and fall back to pull-and-filter with an explicit "this could be expensive" warning when the block escapes the translatable subset.

Related prior art: DuckDB and Polars both do this well; ORMs (ActiveRecord, SQLAlchemy) do it with more friction. Datomic queries are functions-over-facts by design.

### Distributed state

CVM on Redis / Postgres / CockroachDB. Multiple Caspian processes sharing state via a common backing. [Puck](puck-object) is already the piece for remote-reference semantics (an object reference works even when the object lives on another host); distributed CVM is the piece for shared-state semantics (many processes read/write the same state).

Composition: a Caspian process running on machine A might have `$sensors` backed by a shared Postgres, with individual sensor objects reached through Puck references to their owning processes on machines B, C, D.

### Transactions

Factory operations often need "all or nothing" — a workflow updates 12 machines; if one fails, rollback all. The CVM-on-SQLite ACID story is directly relevant. Would want a `%transaction do ... end` block that wraps state mutations in a single commit/rollback boundary.

### Coherence model

Reads from disk-backed state may lag writes; reads from distributed state may see stale values. Developer needs a way to reason about "when am I seeing a stale view?" and how to force a fresh read when it matters.

Same problem every distributed system has, now visible inside a single Caspian program. Explicit as an operation (`.refresh`, `.fresh_read`) rather than an ambient guarantee — the language shouldn't pretend to solve CAP.

### Persistence guarantees

Sync policies. What's guaranteed on disk before a mutation returns?

- **Immediate durable** — every write flushed to durable storage before returning. Safe, slow.
- **Buffered** — writes coalesced, flushed periodically. Faster, some loss window on crash.
- **Best-effort** — no durability guarantee; state is memory-with-persistence-hints.

Per-BigX or per-transaction knob. Most factories want immediate durable for critical state, buffered for high-volume metrics.

## Prior art

None do exactly what Caspian could do (small language + pluggable storage + everything-is-a-value surface). Each does one leg of it:

- **[Datomic](https://www.datomic.com/)** — the DB IS the value; queries are functions over it. Same "value that lives somewhere else" spirit, applied to entire databases.
- **[Smalltalk images](https://en.wikipedia.org/wiki/Smalltalk#Image-based_persistence)** — the whole runtime is a persistent snapshot on disk; startup loads the image, shutdown re-serializes it. Same "runtime state is a first-class persistent thing" spirit.
- **[Erlang / OTP with Mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia_overview.html)** — language-integrated distributed database. Tuples stored in a table Erlang programs read like plain data.
- **[VMS and mainframe virtual memory](https://en.wikipedia.org/wiki/Virtual_memory)** — the OS-level version: treat disk as swap so processes think they have huge RAM. Application code doesn't know.
- **[DuckDB](https://duckdb.org/) and [Polars](https://pola.rs/)** — modern "in-memory database as first-class computation surface." Query-pushdown pattern proven at scale.
- **[Automerge](https://automerge.org/) / CRDTs** — distributed values that sync as a fabric; the value IS the network of replicas.

## Not every object is DB-able

The "everything can live in the DB" story has a real limit: some values can't be serialized to disk in any meaningful way. File handles, open sockets, protected-memory allocations, active timers, foreign-library handles, callbacks registered with the OS. These are LIVE resources tied to specific process state; there's no useful bytes-on-disk form of them.

Any pluggable-storage design has to address this or it breaks at the first `%fs.open('big.log')`.

### Categories of not-serializable

- **OS-level handles.** File descriptors, sockets (TCP, UDS), directory jails, timer handles, process handles, signal masks, terminal / TTY handles. Live entries in the kernel's per-process table; die with the process.
- **In-memory-only runtime state.** Locks, condition variables, native library handles (dlopen'd `.so`), FFI resource pointers. Meaningful only within one process's address space.
- **Protected memory.** Vault-allocated secure memory (see [protected/](https://puck.uno/requirements/protected/)) must NEVER land on disk — that's the whole point. Even a well-meaning serializer would defeat the security posture.
- **Callbacks / continuations tied to live resources.** A closure that captured a file handle is only partially serializable; the closure body is data, the captured handle isn't.
- **Negotiated / stateful connections.** TLS sessions, DB connections, WebSocket streams. The wire is a socket; the state on top of it is negotiated with a peer and can't be replayed.

### Three shapes of "not serializable"

- **Reconstructible from a spec.** A file handle can be re-opened from `{path, mode, offset}`. A directory jail from its root path. A timer from its duration and start time. Serialization stores the recipe; reconstruction re-opens fresh.
- **Semi-reconstructible.** A socket's remote endpoint is a spec you can reconstruct; the in-flight buffered data and negotiated crypto state aren't. Reopen re-establishes the connection but loses mid-flight anything.
- **Not reconstructible at all.** In-memory locks. Vault-backed protected memory. Ephemeral OS resources. Never on disk, ever.

### Design shape for Caspian

Every class declares its own **serialization protocol** — a small extension of the existing bucket/platter model. Recommendation:

- **`%bucket` fields serialize by default.** These are the values the class stores as its state; they map cleanly to DB rows or JSON.
- **Fields marked `transient: true` at declaration are skipped.** They're memory-only; they get default-initialized (or lazy-initialized on first access) when the object is reconstructed.

~~~caspian
class # log_writer
	field :path, class: 'string'
	field :handle, class: 'file_handle', transient: true

	method init(@path)
		@handle = %fs.open(@path, mode: 'a')
	end
end
~~~

Under DB backing: `path` serializes; `handle` is skipped. On reconstruction, `init` runs with the serialized `path` and reopens the file handle. The developer wrote one line of intent (`transient: true`); the serialization layer handled the rest.

- **Classes can override the serialize / reconstruct hooks** for cases that need custom handling. `method &serialize` returns a hash of what to store; `method &reconstruct($stored)` (class-level) rebuilds the object. Same pattern as Ruby's `_dump` / `_load` or Python's `__getstate__` / `__setstate__`.

- **`.serializable?`** is a predicate any class can implement. Defaults to `true` (with transient fields skipped); a class that holds truly-unreconstructible state returns `false`. The DB layer raises a clear error when a not-serializable object is written: `cannot store object of class X — .serializable? returned false`. Developer sees exactly which class refused and why.

- **Protected memory is unserializable at the vault level.** No opt-in, no override. The vault's serialize hook always raises: `cannot serialize protected memory`. Belt-and-suspenders — even if a class forgets to mark its protected fields transient, the vault refuses. See [protected/](https://puck.uno/requirements/protected/) for the underlying rule.

- **Reference from DB-backed to transient must be explicit.** A DB-backed object holding a reference to a live socket doesn't silently null the reference on serialize. It raises unless the developer marked the field transient (accepting "will be null after reload") or overrode serialize (accepting "you handle it"). Silent nulling is exactly the debugging nightmare this design is trying to prevent.

### What the developer's mental model becomes

"State is DB-backed by default; live resources are memory-only and don't survive process restarts unless I write a reconstruction handler." That's the shape. It matches how Java's `Serializable` + `transient` works, how Erlang's Mnesia expects you to separate persistent facts from process state, how Smalltalk images automatically close and reopen file handles on save/load. Not a novel design — a known pattern that fits.

### Prior art for this angle specifically

- **Java `Serializable` and the `transient` keyword** — canonical. Fields marked `transient` skip serialization; default-init on read. Custom `writeObject` / `readObject` for advanced cases.
- **Python `__getstate__` / `__setstate__`** — customizable serialization for `pickle`. Returns a dict of what to store; receives it back on load.
- **Ruby `Marshal._dump` / `_load`** — same pattern.
- **Erlang `term_to_binary` / `binary_to_term`** — only serializes basic types and tuples. Ports (file/socket references) and PIDs refuse — you serialize the setup and re-establish on load.
- **Smalltalk image saves** — file handles auto-close on save, auto-reopen on load using stored paths. Sockets typically don't survive.
- **Common Lisp `save-lisp-and-die`** — similar image approach. Open streams are closed before save.
- **CRIU (checkpoint/restore)** — OS-level. Handles file descriptors by recording paths and offsets. Some sockets can be restored; some can't.

None of these is a full match for what Caspian needs, but the pattern is well-trodden: declare what's transient, provide hooks for the reconstructible-with-a-spec cases, raise loudly for the rest.

## V1 hooks: cheap now, valuable later

None of this ships as big-process support in V1. But each item is a modest V1 decision that avoids painful retrofit later. Skip these now and every future big-process piece has to break something already committed.

### 1. Lazy-compatible iteration everywhere

If V1's `.each`, `.map`, `.filter`, `.reduce` materialize their inputs before iterating, later BigHash / BigArray types that MUST stream can't drop into stdlib without breaking every existing consumer. Write V1's iteration surface as iterator-shaped from the start — even for small in-memory collections. Actual materialization becomes a fast path, not a semantic assumption.

- **V1 cost:** small design discipline. `.each` still works the same way on `{a: 1, b: 2}`; the stdlib just doesn't ASSUME the collection fits in memory anywhere in its implementation.
- **Cost to skip now:** every stdlib collection method has to be rewritten when BigHash / BigArray land.

### 2. Storage-abstraction discipline in CVM

Cross-references [mvm-sqlite § Middle-ground shapes](mvm-sqlite#middle-ground-shapes-worth-considering) — even if V1 ships the Lua-table driver, write CVM's spec against the abstract storage interface. Every consumer of runtime state reaches through the interface, not into Lua tables directly.

- **V1 cost:** design work up front — name the interface, draw the boundary. No runtime cost; the Lua-table driver still runs at full speed.
- **Cost to skip now:** every consumer of CVM state has to be untangled from Lua-table assumptions before any alternate backing (SQLite, distributed, tiered) can be added.

### 3. Serialization protocol on class definitions

Even if V1 never serializes anything, define the shape now. Class DSL supports `field :name, class: 'X', transient: true` — the `transient` flag is a no-op in V1 (nothing serializes). Optional `serialize` and class-level `reconstruct` hooks are defined but unused. When big-process DB backing lands, every existing class either works (fields serialize by default) or has the escape hatches ready.

- **V1 cost:** one extra field option; two convention method names reserved. Trivial.
- **Cost to skip now:** every class that turns out to hold a file handle, socket, or vault-backed field has to be retrofitted class-by-class when serialization surfaces.

### 4. Stable object IDs

Every object gets a unique ID at construction, guaranteed stable for the object's lifetime. Enables snapshot-and-revive (identity survives), distributed reference (multiple hosts agree on which object is which), dedup (same-object equality is cheap), and debugging (this ID is that entry in the log).

CVM already specifies this — a single program-wide counter minting integer-as-string IDs, drawn from the same pool for objects, platter markers, and src-registry keys. See [mvm/references § Object IDs](https://puck.uno/requirements/cvm/references#object-ids). V1's job is just to actually use it uniformly: every object gets its ID from the sequencer at construction, no ad-hoc `id_of(obj)` schemes that would need reconciling later.

- **V1 cost:** the counter and its increment routine (already spec'd). One field per object; a few bytes.
- **Cost to skip now:** any big-process feature that needs object identity — distribution, snapshotting, cross-host reference — has to bolt on IDs across every existing object, and reason about pre-ID objects specially.

### 5. Discipline: no globally-mutable state outside abstract globals

%amber and %chain are already per-frame / per-role (per their designs). Objects have owners. Everything mutable has a scope. If V1 preserves this discipline — never introducing a truly-global mutable slot — then distribution works: two Caspian processes on different hosts can share the well-defined abstractions (%amber grants, Puck references, DB-backed values) without a hidden "there's a global here" surprise.

- **V1 cost:** design discipline. Say no to global module-level state; keep everything scoped.
- **Cost to skip now:** distributed / snapshottable state has to work around whatever globals accreted, which is often intractable (`java.security.Providers`-style pain).

### 6. Method dispatch that doesn't assume in-memory receivers

Related to #4. In-memory objects are cheap to dereference; DB-backed / remote objects aren't. V1's method dispatch should NOT hard-code "receiver is a live pointer" — even though in V1 it always is. The receiver comes through the reference layer; the layer's V1 implementation is "chase a pointer," but the interface doesn't force that.

Puck's remote-reference model already does this for cross-host references. Same discipline extended to same-process references (which today are just pointers) leaves room for DB-backed local references later.

- **V1 cost:** one indirection at the reference layer; already there for Puck. Zero incremental cost in V1's common case.
- **Cost to skip now:** a local BigObject can't participate in method dispatch without changing the dispatch mechanism itself — a language-level rewrite.

### 7. Standard library discipline: no full-materialize assumptions

Related to #1. When writing V1 stdlib (Array, Hash, String methods), avoid patterns like "read all N entries into a Lua table, then iterate the table." Prefer patterns that iterate through whatever the collection's iterator yields. This is a stylistic habit at V1 scale (Lua tables materialize anyway); a semantic requirement at big-process scale (BigArray CAN'T materialize its billion entries).

- **V1 cost:** code-review discipline; slightly more careful stdlib. Nothing user-visible.
- **Cost to skip now:** stdlib rewrite every time a Big-* variant lands.

### Summary

Seven small V1 decisions — mostly design discipline, one modest storage abstraction, one extra field-option flag. Cost is minimal at V1 scale; every one avoids a retrofit that would otherwise cascade through the codebase when big processes lands. **Nothing here commits Caspian to big-process support** — it just leaves the doors open. The doors close permanently the moment you commit to a Lua-table-shaped API, a materialize-first iteration idiom, or an "objects are pointers, period" identity model.

## Design questions worth naming

Not answered — flagged for future thinking:

- **Where does the RAM/disk boundary get decided?** Per-value at construction (developer chooses)? Per-workload via a runtime hint? Automatic based on size?
- **What's the escape hatch when abstraction leaks?** Every "value that lives somewhere else" system eventually needs a way to force materialization, or force a specific driver, or drop to the underlying storage's native API. What's Caspian's version?
- **How does GC work across backing tiers?** A reference from an in-memory object to a DB-backed one — does the GC walk into the DB? Or does DB-backed state have its own lifecycle rules?
- **What's the story for cross-process references?** Puck handles remote objects. Does it compose cleanly with distributed CVM, or are they different mechanisms that overlap awkwardly?
- **Debugging.** How does a developer inspect a state where "the object is over there" and "the value is in this DB" and "the log is on that host"? Debugger surface for the pluggable-storage world.
