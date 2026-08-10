# Inverted index

~~~vibecode
{"vibecode": {
	"doc": "ideas_inverted_index",
	"role": "brainstorm doc for a general-purpose hash subclass that maintains an inverse index — 'given this value, what keys map to it?' — as a first-class O(1) query. Motivated by the MVM reference table (which needs the who-points-at-this-target query for incremental GC) but useful as a standalone primitive for many programs. Will be populated iteratively; promotes to requirements/ once the shape settles.",
	"status": "stub — populate iteratively"
}}
~~~

**Not V1 spec change.** Placeholder for design work; nothing lands in `requirements/` until the shape is settled.

## Main purpose

Add a `.by_value` method to a specialized hash subclass, giving programs O(1) reverse lookup — "for this value, what keys map to it?":

~~~caspian
$h = %('core:inverted_hash').new
$h['a'] = 'x'
$h['b'] = 'x'
$h['c'] = 'y'

$h.by_value('x')    # ['a', 'b']
$h.by_value('y')    # ['c']
$h.by_value('z')    # []
~~~

Every plain hash operation still works (`.set`, `.delete`, subscript access, iteration). The inverted hash just adds the reverse-lookup surface on top and keeps the internal inverse index in sync automatically.

## Implementation

### Overrides

The invin class inherits from `Hash` and overrides every mutation method on the base class. Each override maintains the internal inverse index alongside the ordinary hash update:

1. Read whatever state is needed to know what the inverse should look like after the change.
2. Super-call the base method to actually mutate the hash.
3. Update the inverse index to match the new state.

**Which methods get overridden.** Every path that can change the hash's contents:

- `[]=` — set (or update) a key's value.
- `.delete` — remove a key.
- `.clear` — wipe all entries. Also wipes the inverse.
- `.merge!` (and any other bulk-update form) — every merged entry runs through inverse maintenance.
- Any other public mutation method the base Hash exposes.

**Super-call ordering: super first, then inverse.** If `super` raises (frozen hash, other engine-level failure), the inverse hasn't been touched and stays consistent with the main hash. Reversing the order leaves the inverse changed while the main hash didn't.

**The `[]=` case needs a read of the old value first.** When `$h[$key] = $new_value` and `$key` already exists, the override needs to know the OLD value to remove `$key` from that value's inverse entry before adding it to the new value's entry. So the sequence for update-in-place is:

1. Look up existing value at `$key` (`.get($key)`); remember it.
2. Super-call: base Hash performs the write.
3. If step 1 found an old value, remove `$key` from that value's inverse entry.
4. Add `$key` to the new value's inverse entry.

One extra O(1) read per set. Acceptable cost.

**Constructor forms:**

- `%('core:invin').new` — empty.
- `%('core:invin').from_hash($h)` — take an existing hash, build the inverse from it in one pass. Useful for migration or one-shot indexing of pre-existing data.

**Serialization overrides.** `.serialize` outputs the forward hash's content only; `.reconstruct` rebuilds the inverse by walking the reconstructed forward hash. The inverse is a runtime cache, not wire format — consistent with the MVM rule that internal indexes don't need to survive the wire.

**Discipline the base Hash class has to hold up.** For this pattern to work, the base Hash's public mutation API must be the ONLY way to change its contents. Any "internal fast-path" that mutates the hash without going through an overridable method lets updates slip past the invin's hooks and desyncs the inverse. Worth stating as an invariant: the base's mutation surface has to be complete and overridable.

**Pros of this strategy:**

- Uses Caspian's own class-inheritance mechanism; no new language machinery required.
- All hash operations "just work" — invin IS a hash through inheritance, so iteration, `.has_key?`, `.keys`, `.values`, `.length`, etc. inherit unchanged.
- Testable in isolation; the overrides are the surface to exercise.
- Simple mental model: "it's a hash that maintains an inverse index alongside."

**Cons / open questions:**

- Every mutation method has to be identified and overridden. Miss one and the inverse drifts.
- Depends on the base Hash class having a complete public mutation surface (no bypasses).
- The per-mutation cost of the override is small but non-zero; a hash that never queries the inverse still pays it. (This is the "if you don't want the maintenance cost, use plain Hash" trade-off — probably fine.)

## Index

TBD.

