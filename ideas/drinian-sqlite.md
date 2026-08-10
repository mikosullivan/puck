# MVM on SQLite

~~~vibecode
{"vibecode": {
	"doc": "ideas_mvm_sqlite",
	"role": "brainstorm doc for backing MVM's runtime state hash with SQLite (in-memory by default, optionally on-disk) instead of (or in addition to) a plain Lua table. Explores what this buys, what it costs, and what a hybrid or opt-in shape might look like.",
	"status": "idea — spitball only. NOT V1 scope; no promotion path to requirements/ implied."
}}
~~~

**Not V1.** Exploratory. Nothing here is committed for V1; nothing has a promotion path to `requirements/` implied.

## The idea

MVM is Caspian's runtime state hash — every object, every reference, every call-stack frame, every local variable, every iterator position, every role, every chain, every pending exception. Currently spec'd as a plain Lua table (in Lucy, the reference implementation).

What if MVM's backing store were **an in-memory SQLite database** instead? The state's shape is unchanged; only the storage substrate differs.

Miko's motivating benefit: if the DB can be switched to on-disk mode, you can run **big processes** — state that doesn't fit in RAM overflows to disk. Like OS swap, but at the language level: the runtime doesn't die when the working set grows past physical memory.

## What else it might buy

### Snapshot-and-revive falls out for free

MVM's stated goal is eventually serializing the state hash so a process can pause across a remote call, release the host, and resume when the response arrives. On Lua tables, this is a serious engineering problem — walk the graph, encode references, preserve cycles, handle closures. On SQLite, it's `.backup dst.sqlite` (or copy the file when in on-disk mode). The database format IS the wire format.

### Time-travel and introspection

If the state's shape is representable as SQL tables — one table for objects, one for references, one for frames, etc. — a debugger can just query it:

- "Show me every object owned by the agent role."
- "Trace all references pointing at object 42."
- "List every frame currently on any stack."
- "Which frames captured this closure?"

Currently these are Lua-table walks written by hand. With SQL, they're one-liners. Live debuggers, post-mortem inspectors, coverage tools — all get a shared query language.

### ACID for state transitions

Some Caspian operations mutate multiple objects at once (initializing an instance, unwinding an exception, applying a role delegation). If any of those raise mid-way, the current Lua-table approach needs careful hand-rollback to avoid leaving state inconsistent. SQLite transactions make it automatic: wrap the operation in `BEGIN ... COMMIT`, and any raise rolls the whole thing back.

### GC as a SQL query

Deterministic GC's "walk the reference graph from uspace roots" is exactly a recursive CTE:

~~~sql
WITH RECURSIVE reachable AS (
    SELECT target_id FROM references WHERE source_id IN (SELECT id FROM uspace_roots)
    UNION
    SELECT r.target_id FROM references r JOIN reachable ON r.source_id = reachable.target_id
)
DELETE FROM objects WHERE id NOT IN reachable;
~~~

Simpler than a Lua tree-walker, and the query planner takes care of the traversal.

### Persistence across restarts (on-disk mode)

With on-disk backing, a Caspian process could survive its host dying: process dies → restart → open the DB → continue from wherever it left off. Similar to snapshot-and-revive but automatic and continuous. Different feature, same underlying mechanism.

### Cross-process shared state (on-disk mode)

Two Caspian processes could open the same DB — one writer, many readers via WAL mode. Communication via shared state rather than IPC. Not a common pattern in most languages; opens design space Caspian could explore.

## What it costs

### Hot-path performance

Every runtime state access goes through SQLite. A Lua table read is nanoseconds; a SQLite lookup is microseconds — 100-1000x slower. On the hottest paths (variable read/write, method dispatch, frame push/pop), that adds up fast. For a language whose interpreter loop is doing millions of these per second, a straightforward "everything through SQLite" model would be a serious slowdown.

Mitigations exist (prepared statements, batched writes, in-memory caching of hot rows) but each adds complexity and takes design effort.

### Per-row overhead

SQLite adds ≈20 bytes of housekeeping per row (page structure, rowid, indexes). MVM holds many small values (a single-frame stack has one row per local variable; an active method has one per method-param). For a process with 10,000 live variables, that's ≈200 KB of overhead beyond the values themselves. Bounded but non-trivial for a small-footprint language.

### Startup cost

Creating the DB, defining tables, preparing statements. Cold-start-sensitive workloads pay for this before doing any real work. Lua-table MVM starts instantly.

### Serialization of Caspian values

Every value stored in SQLite needs a serialization strategy. Numbers, strings, booleans map directly. Objects and references need indirection (BLOB or foreign key). Closures with captured environments — non-trivial. Functions and methods (their body ASTs) — very non-trivial. Some of this design overlaps with what the Lua-table approach ALSO needs for snapshotting, but on the runtime path it's paid every access, not just at snapshot time.

### Complexity increase

"State is a Lua table" is one primitive. "State is a SQLite DB with N tables plus a query layer plus a serialization discipline" is a stack. More code, more failure modes, more debugging surface.

### Lua's speed as an asset

A lot of what makes Lua a good reference-implementation host is that tables are FAST. Putting SQLite in the middle throws away that advantage on every access.

## Prior art

Adjacent designs from other systems:

- **Redis** — in-memory data structure server that persists to disk. "Fast in-memory KV with optional durability" is a well-trodden pattern.
- **DuckDB / SQLite in-memory** — general-purpose in-memory analytical databases used as language runtimes' backing stores in experimental setups.
- **Erlang's Mnesia** — a database integrated into the language runtime. Stores Erlang tuples, supports distributed replication, is used as both an application store AND for some runtime state. Not exactly MVM but the "database ≈ language state" model is close.
- **Datomic** — immutable database with time-travel queries. Not runtime state, but the "your state IS a database you can query" philosophy applies.
- **PostgreSQL as a Lisp image** — occasional experiments treating a Postgres DB as the persistent store for a Lisp environment. Same shape at bigger scale.
- **Smalltalk images** — the whole runtime is a persistent snapshot on disk; startup loads the image, shutdown re-serializes it. Different mechanism, same "runtime state is a first-class persistent thing" spirit.

## Middle-ground shapes worth considering

The "all or nothing" framing is probably wrong. Some hybrids:

### Snapshot-only SQLite

Runtime uses the current Lua-table MVM for speed. Snapshot-and-revive serializes to a SQLite file for portability and time-travel. Best of both: no hot-path cost, snapshot story simplified. Doesn't get you huge-process support or ACID or live introspection queries — those need the runtime to actually be on SQLite. But it's a much smaller commitment and delivers the immediate value.

### Two-tier state

Hot state (call stack, active frames' locals, dispatch tables) in Lua tables. Cold state (long-lived objects, background data, exceptions not being unwound) in SQLite. Objects age out of the hot tier to the cold tier when they haven't been touched recently. This is essentially what OS-level swap does, applied at the language level. Complexity high; possibly worth it for the huge-process case Miko named.

### Abstract MVM's storage behind an interface

Probably the cleanest shape. MVM defines an ABSTRACT storage interface — `get_object(id)`, `set_object(id, value)`, `push_frame(frame)`, `pop_frame()`, `find_references_to(id)`, etc. Any backing store implements the interface: a Lua-table driver, a SQLite driver, an mmap driver, a Redis driver. MVM's spec is decoupled from the storage decision entirely.

Payoffs:

- **The database CAN act as if it were in memory** — that IS the interface. The MVM caller writes as though state is in a table; the driver translates to SQL under the hood (or Lua-table access, or whatever).
- **Storage is an implementation detail.** Users don't opt in / out of a specific backing; they use MVM, and the runtime (or the host) decides which driver to bind.
- **Adding a new backing store is bounded work** — implement the driver, wire it in. Doesn't touch MVM's spec or any code that consumes it.
- **Testing gets easier** — mock driver for interpreter tests; real drivers for integration.
- **Hybrid drivers become possible** — a driver could keep hot state in Lua tables and cold state in SQLite (the two-tier idea), with the split invisible to MVM.
- **The "big process" case Miko named** ships as a driver choice, not a runtime feature.

Cost is design work up-front: naming the interface precisely, drawing the get/set/traverse boundary at the right granularity, deciding what's a driver responsibility vs a MVM responsibility. Some operations (GC's recursive-CTE traversal, transactional multi-write) fit some drivers better than others; the interface has to expose enough for each driver to do its best work without leaking implementation to callers.

### Opt-in SQLite mode

Simpler than the abstract interface: default Lua-table MVM (fast); a build flag or `%engine.state_backing` toggle switches to SQLite-backed MVM for use cases that want the extra features. Two implementations of the same fixed shape, no proper abstraction layer. Faster to prototype than the interface approach; less flexible long-term.

### Same-shape design regardless

Whichever backing store is chosen, design MVM's state so it's REPRESENTABLE as SQL tables. That makes snapshot-serialization to SQLite clean, and leaves the door open for a full SQLite-backed mode later without a redesign. This is a discipline decision, not a code decision — spec MVM's shape in a way that maps cleanly to tables, and the future is open.

## My lean

**Abstract MVM's storage behind an interface** (the fourth middle-ground option) is probably the right answer. It generalizes every other option — snapshot-only, opt-in mode, hot/cold tiering — as driver choices rather than separate features. MVM's spec stays clean; the storage decision moves to a per-driver detail.

Under that shape, the roadmap is:

1. **V1** — ship a Lua-table driver; that's what actually runs. MVM's spec is written against the abstract interface so the driver is one of many possible implementations, not the only shape the spec allows.
2. **Post-V1** — add a SQLite-file driver that handles the snapshot-and-revive surface. Same MVM, different driver.
3. **Later, if it earns its place** — a full SQLite-backed driver (in-memory or on-disk) for the huge-process / live-introspection / continuous-persistence cases Miko named.
4. **Further out** — hybrid two-tier driver, Redis driver, mmap driver, whatever real workloads want.

Not-for-V1 as the primary hot-path store — the performance cost is too big a commitment while the current path works. But the interface-first design is a modest V1 discipline that pays off every time a new backing shape shows up. Cheap to do; expensive to skip.

## Open questions

- **What's the actual measured overhead?** The 100-1000x hot-path slowdown is folklore; a benchmark would say whether prepared statements + caching bring it down to a manageable range.
- **Can SQLite in-memory be swapped to on-disk after creation, or is it decided at open?** If mode-switching mid-process is possible, that changes the design shape.
- **How does the reference graph fit into SQL?** One table per reference kind (variable→object, object-field→object, closure-capture→object)? A single unified `references` table with a discriminator? Affects query complexity.
- **What about closures?** Serializing a Lua function reliably is hard; the captured-environment part is the sticky bit. Same problem as any snapshot approach — but SQLite doesn't magically solve it.
