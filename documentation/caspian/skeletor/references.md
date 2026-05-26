# References

~~~json
{"vibecode": {
	"doc": "references",
	"role": "the foundational data structure inside Skeletor that maps references to the objects they point to; the table the engine scans to determine reachability for deterministic garbage collection",
	"status": "design — being rebuilt from earlier conversational concept",
	"key_concepts": ["refs_table", "ref_id", "object_id", "many_to_many",
		"reachability_via_scan", "cycle_detection_via_walk_back_to_roots",
		"foundation_for_deterministic_gc"]
}}
~~~

The `refs` table is the structural foundation that makes Skeletor's
**deterministic garbage collection** work without reference counting. Every
"thing that can hold an object reference" is a row in this table; every
"object that can be pointed at" is the other side of a row. When a reference
is removed, the engine scans the table to determine whether any other
references still point at the affected object — if not, it's orphan and gets
collected.

This is the mechanism behind the "root trace at the mutation point" model in
[garbage-collection.md](../garbage-collection.md#how-it-works).

<a id="shape"></a>
## Shape

The `refs` table is a top-level field in the Skeletor hash. It holds an
array (or equivalent structure) of `[ref_id, object_id]` pairs:

```json
"refs": [
  ["ref1", "objecta"],
  ["ref1", "objectb"],
  ["ref2", "objecta"],
  ["ref2", "objectb"]
]
```

A ref can appear multiple times in different rows (e.g., a single variable
binding might point at multiple objects if it's a container of references).
An object can appear multiple times (e.g., shared object pointed at by
multiple bindings).

**This is a conceptual shape.** The actual in-memory representation may be
denormalized for lookup speed — e.g., a hash from `ref_id` to a list of
`object_id`s, plus the inverse hash from `object_id` to a list of `ref_id`s.
What matters is the **bipartite graph of references → objects** that the
table represents.

<a id="what-counts-as-a-ref"></a>
## What counts as a ref

A ref is any named slot inside `state` that holds an object reference. The
canonical sources:

- **A frame's local** — `state.call_stack[i].locals[name]` is a ref. The
  `ref_id` is the qualified path, something like `"frame[i].locals.foo"`.
- **A chain entry** — `state.call_stack[i].chain.misc[name]` is a ref.
- **An object's field** — if object `objA` has a field `@bar` pointing at
  `objB`, that's a ref `"objA.@bar"` → `objB`. Object-to-object edges are
  refs too; the same table covers them.
- **An array element** — `objA.@items[3]` is a ref slot.
- **A hash value** — `objA.@settings["color"]` is a ref slot.
- **An engine-level binding** — `state.objects[name]` (engine-provided
  objects), entries in the top-level `state.classes` registry, role
  metadata — these are roots; they're refs that always count as reachable.

The qualifying form of a `ref_id` is whatever the engine uses to address the
slot. The exact string form isn't load-bearing; what matters is that each
ref slot has a unique identifier.

<a id="what-counts-as-an-object"></a>
## What counts as an object

Anything with **object identity** — something `.object ==` could compare
against another. Concretely:

- **User-class instances.** Each has a unique `object_id` assigned at
  creation time.
- **Built-in containers** with mutable identity — hash and array instances.
- **Engine-provided objects** in `state.objects` (stdout, clock, etc.).
- **Class definitions themselves** (each class is an object).

Primitives — strings, integers, booleans, null — may or may not need
object_ids depending on whether the implementation treats them as immutable
value types or as identity-bearing objects. (Open question; see below.)

<a id="how-gc-uses-the-table"></a>
## How GC uses the table

When the engine modifies a reference (rebinds a variable, pops a frame,
overwrites an object field, etc.), it updates the `refs` table and then
checks for orphans:

1. **Remove the changed row(s).** A rebinding removes the old `[ref, object]`
   pair before adding the new one. A frame pop removes every row whose
   `ref_id` belongs to that frame.
2. **For each object that lost a ref:** scan the table for other rows
   pointing at it.
3. **If at least one other ref points at it:** done, nothing to collect.
4. **If no other refs point at it:** the object is a candidate orphan. But
   it might still be reachable via a cycle. Walk back from the object —
   what does it reference? — and from those, walk back again, until the
   walk either:
   - Reaches a root (a ref that originates from `state.call_stack` or
     another always-reachable origin) → the candidate is reachable; do not
     collect.
   - Exhausts all paths without reaching a root → the candidate is orphan,
     along with everything in its reachability island. Collect them all.

The walk handles cycles naturally. Two objects referencing each other but
with no external refs are both unreachable from roots, even though each
keeps the other in its own reference list.

The cost of the scan is proportional to the size of the table and the size
of the affected reachability island. In practice both are bounded by what
the program is actually doing: most reference changes affect tiny graphs.
The 2ms cap on `on_close` handlers
([see GC doc](../garbage-collection.md#on-close-2ms-cap)) is the relevant
runtime budget; collection scans are typically far under that.

<a id="snapshot-serialization"></a>
## Snapshot serialization

When the engine snapshots Skeletor (post-V1.0 feature; see
[skeletor.md § V1.0 scope](skeletor.md#v1-0-scope)), the `refs` table is
serialized like any other top-level field — `to_json` on the table emits
the array of pairs verbatim. No special machinery needed; the table is
already in a serializable shape.

The actual objects referenced (`objecta`, `objectb`, etc.) are serialized
via their classes' `to_json` methods — this is where
[redaction of sensitive fields](skeletor.md#out-of-scope-snapshot-revive-hooks)
happens. Each class controls what its instance becomes on disk.

The `refs` table is the **structure**; the objects' `to_json` outputs
are the **content**. Both together let the snapshot capture and revive the
full object graph.

<a id="open-questions"></a>
## Open questions

- **Are primitives in the table, or are they always inlined?** Strings,
  integers, etc. are immutable value types; treating them as identity-bearing
  objects in the `refs` table adds bulk for little benefit. Probably
  inlined as values in their referring containers, with no row in the
  `refs` table. But there are edge cases (interned strings, large
  strings shared by reference) worth thinking through.
- **`ref_id` string form** — the qualifying path scheme isn't pinned down.
  Could be hierarchical strings (`"frame[1].locals.foo"`), structured
  records (`{"kind": "local", "frame": 1, "name": "foo"}`), or opaque
  surrogate IDs. The choice affects readability of snapshots, parser cost,
  and how easy `ref_id`-to-actual-slot resolution is.
- **`object_id` allocation** — sequential? UUIDs? Hashes of creation
  context? Sequential is cheapest and most readable but breaks down
  across snapshot/revive on different processes.
- **Updates during snapshot.** If a snapshot is taken mid-execution, the
  table is frozen for the snapshot but the program may continue. Need to
  ensure the snapshot is a consistent view, not a mid-mutation tear.
- **Container internals.** When a hash adds/removes entries, that's
  multiple `refs`-table mutations bundled into one logical operation.
  Probably the engine batches the updates and runs the orphan scan once.
- **The on-close example's open question** — "how user-defined instances
  are stored in Skeletor" — is answered by this doc: instances live in
  the engine's object pool (an addressable region not directly shown in
  Skeletor's top-level fields), and the `refs` table connects refs
  to them. Where exactly the object pool lives (in another top-level
  Skeletor field? In an implicit engine-managed structure?) is the next
  question down the chain.

<a id="related-docs"></a>
## Related docs

- [skeletor.md](skeletor.md) — the overall Skeletor state hash, of which
  this table is a part.
- [garbage-collection.md](../garbage-collection.md) — the GC model the
  `refs` table makes tractable.
- [object.md](../built-in-classes/object.md) — `.object` and object
  identity, the user-facing surface that the `refs` table implements
  under the hood.
