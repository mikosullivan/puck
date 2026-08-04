# References

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_references",
	"role": "spec for the references hash inside Drinian — the foundational data structure that maps reference objects to the objects they point at; the table the engine scans to determine reachability for deterministic garbage collection",
	"status": "draft — refs hash + reference class hierarchy + uspace as class-level property",
	"audience": "Caspian engine implementers building the reference-object and GC subsystems"
}}
~~~

The `references` hash is the structural foundation that makes Drinian's **deterministic garbage collection** work without reference counting. Every "thing that can hold an object reference" is an entry in this hash, mapping its own ID to the object it points at. When a reference is removed, the engine traces from a root set of `uspace` references to determine whether the affected object is still reachable — if not, it's an orphan and gets collected.

<!-- SPEC CONFLICT: archive links to garbage-collection.md for the GC model this hash makes tractable. No such doc exists in current requirements/. Needs Miko decision on whether to write that spec (and where — under requirements/lua/ or top-level requirements/), and how much of the GC model should be inlined here in the meantime -->

## Shape

The `references` hash is a top-level field in the Drinian hash. Keys are reference IDs; values are object IDs (each of which must resolve to an entry in [`objects`](https://puck.uno/requirements/drinian/objects) — the companion top-level hash holding per-object records):

~~~json
"references": {
	"2": "4",
	"3": "4",
	"5": "6"
}
~~~

Every reference points at exactly one object — that's the contract of a reference. Multiple references can point at the same object (`2` and `3` both point at `4` above); that's how sharing works. The hash captures the full edge set of the program's reference graph.

The reference ID is the reference object's own object ID. There's no separate `ref_id` namespace — a reference is itself an object (instance of `core:reference` or a subclass), and the hash maps its identity to whatever target it currently holds.

### Object IDs

Object IDs are integers-as-strings drawn from a single program-wide counter. The counter starts at `"1"` and proceeds `"1", "2", "3", ..., "999", "1000", ...` in encounter order. Every object created in the program — variables, hash elements, hashes, function objects, class instances — draws its ID from the same counter, so every ID in a running program is unique across all object kinds.

**Platters differ.** Most platters have no ID — they're anonymous positional entries in the object's `stack` array (see [objects § stack](https://puck.uno/requirements/drinian/objects#stack)). The one exception is a **nested-object platter**: a platter carrying a `nested: "<UUID>"` marker that links the platter to the matching UUID-keyed entry in the parent's bucket (see [built-in-classes/object/structure § Nested objects](https://puck.uno/requirements/built-in-classes/object/structure#nested-objects)). That UUID is the platter's identity; it's a UUID rather than a sequence-counter integer-string precisely because it appears as a key inside user buckets, where integer-strings could collide with user-chosen field names.

**The counter is stored as a string**, not as an integer, so the sequence can grow indefinitely without bigint machinery. A small increment-the-string-by-one routine handles the counter — rightmost digit increments, carry propagates left. No overflow concern for long-running programs that allocate billions of objects.

Properties:

- **Stable within a program's lifetime.** Once `"2"` refers to an object, that mapping holds until the object collects.
- **Not stable across runs.** A new program execution starts the counter fresh; the same object might be `"2"` in one run and `"47"` in another.
- **Not designed for cross-process merging.** Snapshots from two different processes will have colliding IDs. Programs that need to combine state from multiple processes resolve that explicitly at the application level — not the engine's job.
- **No namespace prefix, no sigil.** IDs are bare strings. Context disambiguates: an ID appears as a key or value in `references`, as a value in a frame's `locals`, etc. Plain values in those positions are always wrapped in the standard drinian value shape (`{"value": ..., "src": [...]}`), so a bare string in a reference-typed slot is unambiguously an ID.

The counter is cheap (one string-increment per allocation), the IDs are short (1-4 characters for typical programs), and Drinian snapshots stay readable — `references: {"2": "4", "3": "4"}` is far more inspectable than UUID equivalents.

For persistent object identity across process restarts (Mikobase records, blockchain entries, etc.), different ID schemes apply — those systems use UUIDs because the cross-process uniqueness requirement is real for them. The in-process Caspian counter is for in-memory program state only.

## Reference classes

Every entry on the left side of the hash is a **reference object** — an instance of `core:reference` or one of its subclasses. The reference's class determines what role it plays in the program; the hash entry itself only carries the pointer.

<!-- SPEC CONFLICT: archive uses puck.uno/reference, puck.uno/variable, puck.uno/hash_element as class identifiers. UNS is dropped per project memory. "core:variable" is documented in current spec (built-in-classes/variable-object references it); the other two follow the same pattern but aren't yet documented — needs Miko decision on the identifiers -->

`core:reference` is the base. Its responsibility is exactly:

- Own one pointer (stored in the `references` hash, not in the reference object itself).
- Participate in GC tracing.

The reference object's classes and bucket carry semantic metadata about *what kind* of reference this is. The pointer lives in exactly one place — the `references` hash — so there's no risk of drift between the reference's internal state and the table.

Two subclasses, both V1.0:

| Class | Plays the role of |
|---|---|
| `core:variable` | A named slot in a scope frame |
| `core:hash_element` | A key inside a hash |

`core:variable` is a bare reference object — its bucket is empty. The lexical name lives in the enclosing scope as the key in the frame's `locals` hash; the frame's identity is implicit (the variable only exists because some frame's `locals` references it, and that's the frame it belongs to). The variable's only state is its identity (its object ID) and its target (the entry in `references` keyed by that ID). Assignment to a variable (`$foo = $bar`) rebinds the variable's entry in the `references` hash to point at the new target.

`core:hash_element` carries the parent hash and the key. `hash[key] = obj` rebinds the hash element's entry to point at the new target. Hash internals are first-class reference objects, not some special-cased container scheme — GC walks the `references` hash uniformly.

Future reference subclasses (return slots, system-surface references, etc.) can be added without changing the hash shape.

### Reference API

The base class provides two operations:

- **`.target`** — returns the object the reference currently points at. Under the hood: `state.references[self.id]`.
- **`.rebind(obj)`** — updates the pointer to a new target. Under the hood: `state.references[self.id] = obj.id`. The engine fires a GC trace from the previous target before returning.

Both are engine-managed. User code typically doesn't call them directly — assignment expressions and hash mutation drive them.

## Uspace: a class-level property

Caspian distinguishes **uspace** (user space) — the reachability graph as the program sees it — from **engine bookkeeping** that also lives in `state` but is not part of the program's data.

The distinction matters for GC: an object is in uspace if a trace through `references` lands on a uspace **root**. Roots are the subset of reference objects that ground the program's data graph. Engine-internal references (the slots holding the call stack itself, the `references` hash itself, etc.) don't count as roots even though they're also reference objects.

**Uspace is a class-level property, not a per-instance flag.** Each reference subclass declares `uspace: true` or `uspace: false` in its class definition. The declaration is fixed for the class's lifetime — every instance of the class is uspace if the class declares it, and not otherwise.

The classification:

| Class | `uspace` |
|---|---|
| `core:reference` (base) | `false` |
| `core:variable` | `true` |
| `core:hash_element` | `false` |
| Engine-internal subclasses (`state` slots, etc.) | `false` |

Why hash_element is **not** uspace: a hash element only matters if the hash containing it is reachable through some uspace root. The element itself isn't a root — the variable (or other root) that holds the hash is. Walking from variable roots picks up all reachable hash elements naturally; making hash_element a root in its own right would double-count.

Why variable **is** uspace: variables in active scope frames are the program's data anchors. Everything the program "has access to" traces back to a variable.

System surfaces (`%foo` methods, `state` slots that the engine exposes as program-visible) get their own reference subclasses that declare `uspace: true`. Adding new uspace-rooting reference kinds is a class-definition act, not a per-call decision.

Why class-level rather than per-instance: it matches the rest of the design. Truthiness is determined by class membership (see [built-in-classes/object/structure § Truthiness](https://puck.uno/requirements/built-in-classes/object/structure)); identity-bearing properties (redact-status, etc.) likewise. The uspace classification is the same kind of thing — *what kind of reference is this?* — so it lives in the same place.

## Lifecycle: creating and destroying references

A reference object is created when a slot opens (variable declared, hash key assigned for the first time). The engine:

1. Allocates the reference object (with the appropriate subclass).
2. Inserts a row in `references`: `state.references[ref.id] = target.id`.
3. The reference is now live.

A reference object is destroyed when its slot closes (variable goes out of scope, hash key deleted). The engine:

1. Removes the row from `references` (`state.references[ref.id] = nil` in implementation terms).
2. Fires a GC trace from the former target — if the target is no longer reachable from any uspace root, it's an orphan and gets collected.
3. The reference object itself is also collected.

The invariant: `references` hash has exactly one entry per live reference object, and no entries for destroyed ones.

## How GC uses the hash

When the engine modifies a reference (rebinds a variable, pops a frame, overwrites a hash element, etc.), it updates the `references` hash and then checks for orphans:

1. **Update the row.** A rebinding writes the new target in place; a destruction removes the row entirely.
2. **Identify candidate orphans.** Any object that just lost an incoming pointer is a candidate.
3. **Trace from uspace roots.** Walk every reference where the reference's class declares `uspace: true`. Follow each one's target. From each target, follow every outgoing reference (other entries in `references` whose target is that object).
4. **Mark reachable objects.** Anything the walk reaches is alive.
5. **Collect what wasn't reached.** Candidates not in the reachable set are orphans, along with everything in their reachability island. The engine fires `on_close` deepest-first.

The walk handles cycles naturally. Two objects pointing at each other but unreachable from any uspace root are both collected.

Cost: O(reachable objects) per trace, bounded by what the program is actually doing. Most reference changes affect tiny graphs.

## Why a hash, not an array of pairs

An earlier sketch used `"refs": [[ref_id, object_id], ...]` — an array of pairs. A hash is better for three reasons:

- **One source of truth.** Every reference points at exactly one object. Storing the pointer once in the hash (instead of duplicating it in the reference object's own state) means no drift.
- **O(1) lookup.** `state.references[ref.id]` is constant-time; scanning an array of pairs isn't.
- **Future metadata fits naturally.** If a per-reference field ever needs to live alongside the pointer (cached uspace flag for fast trace, last-mutation timestamp, etc.), the hash's value can grow from a bare object ID to a small record without reshaping the table.

The cost of a hash over an array is a few extra bytes per entry for the hash overhead — negligible against the cleanup-without-refcounting benefit.

## Snapshot serialization

When the engine snapshots Drinian (post-V1.0 feature; see [drinian § V1.0 scope](https://puck.uno/requirements/drinian/#v1-0-scope)), the `references` hash serializes verbatim — just IDs on both sides, trivially representable in JSON.

The actual reference objects (instances of `core:variable` etc.) and the objects they point at serialize via their classes' `to_json` methods. This is where [redaction of sensitive fields](https://puck.uno/requirements/drinian/#on_snapshot--on_revive-class-hooks) happens.

The `references` hash is the **structure**; the objects' `to_json` outputs are the **content**.

## Open questions

- **Are primitives reference targets?** Strings, integers, etc. are immutable value types. Treating them as identity-bearing objects in the `references` hash adds bulk for little benefit. Probably inlined in their referring containers — a variable holding a string stores the string value directly in the variable's bucket, not via the references hash. But interned strings and large strings shared by reference are edge cases worth thinking through.
- **Updates during snapshot.** Mid-execution snapshots must freeze the hash for a consistent view, not a mid-mutation tear.

## Related docs

- [drinian](https://puck.uno/requirements/drinian/) — the overall Drinian state hash, of which `references` is a part.
- [drinian/objects](https://puck.uno/requirements/drinian/objects) — the companion `objects` hash whose keys the target values in this hash resolve to.
- [built-in-classes/object/structure](https://puck.uno/requirements/built-in-classes/object/structure) — object bucket / stack / platter model, the user-facing surface that `references` implements under the hood.
