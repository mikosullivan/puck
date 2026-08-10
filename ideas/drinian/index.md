# MVM redesign

~~~vibecode
{"vibecode": {
	"doc": "ideas_mvm",
	"role": "brainstorm doc for reorganizing the MVM spec (requirements/mvm/). Current spec feels disorganized — this page collects the problems, floats structural ideas, and settles into a plan before edits touch the live spec. Will be populated iteratively; promotes to requirements/ once the shape settles.",
	"status": "stub — populate iteratively"
}}
~~~

**Not V1 spec change.** Placeholder for design work; the live spec at [requirements/mvm](https://puck.uno/requirements/mvm) stays as-is until this page's plan is settled.

## Overview

### Everything is in one hash

MVM is a **single hash** that contains every piece of the Caspian process's execution state. Objects, references, the call stack (with each frame's locals, source position, iterator state, role, and chain), pending exceptions — all of it lives inside that one hash. The interpreter never reaches around MVM to access execution state; every read and every write goes through the hash's interface.

The single-hash organization is the foundation everything else in the runtime builds on. Snapshotting the process is snapshotting the hash. Reviving is reviving the hash. Deterministic garbage collection walks the reference graph inside the hash. Runtime inspection reads the hash. Because there's exactly one place where execution state lives, "what is the process doing right now?" always has one answer.

### Everything in MVM is serializable

Every value that lives in MVM must be serializable. This is a hard constraint, not a preference: it's what enables snapshot-and-revive, cold restart, distributed MVM across hosts, and alternative backing stores (SQLite, Fiona, whatever comes next). If a value cannot be represented as bytes, it cannot live in MVM.

Native resources that cannot be serialized (file descriptors, open sockets, timer handles, foreign-library pointers, callbacks registered with the OS, protected memory) do NOT live in MVM. They live in a host-engine sidecar — a Lua-side table (in Lucy) or its equivalent — keyed by an ID. The Caspian-side wrapper object that a program interacts with (the file object, the socket object, the timer object) DOES live in MVM and IS serializable — it holds the sidecar ID as a plain string, plus whatever spec is needed to re-establish the underlying resource on revive. The wrapper is the Caspian-visible object; the sidecar is the host-engine implementation detail.

The wrapper discipline is enforced at the API boundary. Methods that would return a raw native handle (`%fs.open`, `%net.tcp_connect`, etc.) return wrapper objects instead. If it always comes wrapped, it always stays serializable, and MVM never sees a value it can't snapshot.

#### Serialization is a contract, not an implementation restriction

"Serializable" means the value can produce a serializable representation on demand and can be revived from that representation. It does NOT mean the value must literally be a plain hash or array under the hood. Values in MVM can be dynamic objects — their own class, their own methods, their own internal invariants — as long as they honor the serialization contract when asked.

The **reference table** is the load-bearing example. From outside it looks and serializes like an array (indexed access, iteration, JSON-shape output). Under the hood it can carry whatever machinery makes reference operations efficient — probably an inverse index for O(1) "who references this object?" lookups, capacity management, cached counts. The snapshot serializer calls the object's serialize hook and gets back the array shape; the reviver hands the array to the class's reconstruct hook and gets back a fully-populated dynamic object with its indexes rebuilt. Same value from Caspian's perspective; different memory shape while running.

Same pattern applies to any other MVM-native structure that benefits from being smarter than a plain hash — cached lookups, secondary indexes, watch-set tracking, whatever. As long as the serialize hook produces something the reconstruct hook can rebuild losslessly, the object is MVM-legal.

## The reference table

The reference table is MVM's foundation for deterministic GC without reference counting. It carries every current reference-to-object edge in the process, structured so that dropping a reference immediately answers the question "did that just orphan anyone?"

Both the reference table and its inverse index are **engine-internal** — Lua tables in Lucy, or whatever host-language storage a future engine uses. User Caspian code never sees them directly; the engine maintains them as a side effect of ordinary reference operations (variable assignment, hash mutation, scope entry / exit, exception unwind).

### The primary structure

The **ref table** maps every reference's ID to the object it currently points at:

~~~
ref_table = {
	"2":  "100",
	"3":  "100",
	"10": "42",
	"11": "42",
	...
}
~~~

Every reference (variable, hash element, or any future subclass of `core:reference`) has one entry. The reference is itself an object with its own object ID; the ID is the ref table's key. The value is the object ID the reference currently points at. Sharing is expressed by two refs pointing at the same target — two entries with the same value, as `"2"` and `"3"` both do above.

### Back-refs — the inverse index

The **back-refs** table is the inverse: for each target, the set of refs currently pointing at it.

~~~
back_refs = {
	"100": {"2":  true, "3":  true},
	"42":  {"10": true, "11": true},
	...
}
~~~

Each back-refs entry is a hash-of-keys (the Lua idiomatic set): keys are ref IDs, values are `true` placeholders. This gives O(1) membership test, O(1) add, and O(1) remove — regardless of how many refs point at a given target. Popular targets (a widely-referenced class definition; a shared config hash) can have thousands of incoming refs without any operation degrading.

The engine maintains back-refs in sync with the ref table on every ref change. Back-refs is what makes the "who else still points at this?" query answerable in constant time — the core query GC needs.

### Only two operations: add and delete

The ref table (and consequently back-refs) supports exactly two operations:

- **Add:** a reference is created. Insert into ref table; insert into back-refs.
- **Delete:** a reference is destroyed. Remove from ref table; remove from back-refs.

**There are no in-place updates.** A rebind (`$var = new_value`) decomposes into (delete old entry, add new entry) — two events, always sequenced as an atomic pair by the engine (no user code observes the intermediate state where the ref is momentarily targetless). This keeps the trigger model uniform: every event is unambiguously one of two kinds, no "was this an update or a fresh add?" branch to handle.

### Triggers

State changes propagate through a small cascade of triggers, each layer responsible for its own consequence:

1. **Ref-table change** (add or delete) → a trigger updates back-refs to match.
2. **Back-refs change** (specifically a delete — a target lost an incoming edge) → a trigger runs the trace to determine whether that target is now orphaned.
3. **Trace result:**
   - If the target is still reachable from some uspace root → do nothing more.
   - If the target is orphaned → collect it (and everything in the trace's visited set — see below), which itself produces ref-table deletions that fire the cascade again.

Concretely in Lua-shape:

~~~lua
function on_ref_change(ref_id, old_target, new_target)
	if old_target ~= nil then
		back_refs[old_target][ref_id] = nil
		if next(back_refs[old_target]) == nil then
			back_refs[old_target] = nil    -- clean up empty container
		end
		trace_from(old_target)              -- see below
	end
	if new_target ~= nil then
		back_refs[new_target] = back_refs[new_target] or {}
		back_refs[new_target][ref_id] = true
	end
end
~~~

Called with `on_ref_change(ref, nil, target)` on ref creation, `on_ref_change(ref, target, nil)` on ref destruction, and `on_ref_change(ref, old, new)` for a rebind. One function; two paths that each handle one event kind.

### The trace algorithm

When a ref removal fires the sidecar-delete trigger, the trace determines whether the affected target is still reachable from any **uspace root** (a reference whose class declares `uspace: true` — typically `core:variable`).

The trace walks **backward** through the reference graph: starting from the affected target, follow each incoming ref (via `back_refs[target]`) to find the ref's parent object; recurse to check if THAT parent is reachable; continue until either a uspace root is reached (target is alive) or all backward paths are exhausted without finding one (target is orphaned).

**Visited set.** The trace tracks every node it has walked to. Two purposes:

- **Cycle detection.** If the trace reaches a node already in the visited set, that path is a cycle — no root can be reached that way; abandon this path.
- **Bulk collection on failure.** If the trace completes without finding a uspace root, the entire visited set is orphaned. Every node in it was proven unreachable through all its incoming paths; they can be collected together in one pass.

This is the efficiency win: cycles and jointly-unreachable subgraphs are detected and collected in a single trace, not by cascading refcount events. See [mvm.svg](mvm.svg) for a diagram of the trace walking through the classic two-hash cycle.

**Cost profile:**

- Best case: the affected target has a uspace ref in its back-refs directly → O(1).
- Common case: trace a small local subgraph → O(local reachable).
- Worst case: trace a whole cycle to prove no root → O(cycle size). Proportional to what's actually being collected.

Compare to naïve mark-sweep from all roots: O(everything reachable) per pass, unrelated to the size of what changed. Backward trace scales with the local impact of the change, which is what you'd hope for.

### Cycles

The classic case that pure refcount can't handle:

~~~caspian
$a = {}
$b = {}
$a['b'] = $b
$b['a'] = $a
$a = null
$b = null
~~~

After both `$a = null` and `$b = null`, both hashes still have refcount 1 — each is held by the other's hash element. Pure refcount says "still referenced, don't collect"; both objects leak.

Under the trace model, the second `$b = null` fires a trace from object 101. The trace walks: sidecar[101] contains 100's hash element → parent is 100. Is 100 reachable? sidecar[100] contains 101's hash element → parent is 101 → already in visited → cycle. No uspace root anywhere in the trace. Visited = {101, 100}. Both collected in one pass.

[mvm.svg](mvm.svg) diagrams this specific case.

### Cascade discipline

**Atomicity.** Each cascade (ref change → back-refs update → trace → potential collection → outgoing-ref deletions that cascade again) must complete as a unit. Partial completion would leave MVM inconsistent (back-refs out of sync with ref table, or an orphaned object visible while it's mid-collection). The engine wraps each cascade in whatever transactional discipline the host offers; each step is idempotent so partial completion is safe.

**Cascade depth.** Collecting a large orphan subgraph fires deletion events for every ref the collected objects held, each potentially triggering its own trace. Recursion-based implementation could blow the Lua stack on deep graphs. When cascade depth becomes a concern, turn recursion into iteration with a work queue — same algorithm, bounded stack.

**Trigger ordering.** Sidecar update must happen AFTER the ref-table modification is committed (so the sidecar reflects the actual new state). Trace must happen AFTER the sidecar update is committed. Baked into the trigger definitions.

### `on_close` ordering within a jointly-collected subgraph

When the trace identifies a whole subgraph as orphaned and collects it in one pass, the `on_close` handlers for the collected objects need to fire in SOME order. Options being considered:

- **Undefined, documented.** Whatever the collection loop's iteration order produces. Developer discipline: `on_close` handlers can't rely on other members of the collected cluster being fully alive. Simplest.
- **Reverse-insertion order.** Newest-created dies first. Defensible; matches how many destructor systems work.
- **Reverse-topological where possible.** Children before parents when a strict topology exists; falls back to undefined-within-cycle when it doesn't. More work; sometimes more intuitive.

Not settled. Worth naming as a design decision that has to land before the algorithm ships.

### What lives where

Restating the level separation from earlier discussion:

- **Ref table and back-refs are engine-internal.** Lua tables in Lucy; not exposed to Caspian code.
- **`core:reference`, `core:variable`, `core:hash_element` are Caspian-level classes.** Their instances live in the ref table (as its keys) and are Caspian-visible; Caspian code interacts with them through variable assignment, hash mutation, etc. But the ref table and back-refs themselves are engine bookkeeping about those instances.
- **The trace, trigger cascade, cycle detection, and visited-set collection are all engine-side algorithms.** They operate on the engine's Lua tables to keep the Caspian-level model of "which objects are alive?" consistent. Caspian code has no window into them.

The user-facing surface is: "objects are collected when the program no longer holds them, including cycles." The mechanism is: everything above.

