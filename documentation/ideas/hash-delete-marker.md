# Hash delete marker

~~~vibecode
{"vibecode": {
	"doc": "hash-delete-marker",
	"role": "speculative design for a true-delete marker in Caspian hashes so cascading-config systems like meta-hash can express remove-this-key-from-the-cascade rather than just shadow-with-null",
	"key_concepts": ["delete_marker", "meta_hash_cascade", "null_flavor_candidate",
		"has_key_semantics"],
	"status": "brainstorm"
}}
~~~

Speculative — for cascading-config systems (meta-hash being the
first instance) where a deeper layer needs to **truly remove**
an inherited key, not just shadow it with null. JSON has no
delete marker; Caspian hashes are ours and could.

<a id="why-this-matters"></a>
## Why this matters

In a meta-hash cascade, the current spec says:

- Key absent in a layer: search upward.
- Key with null value at a layer: shadow upward, return null.
  `has_key?` returns true (value-is-null counts as "found").

What we don't have a way to express: "at this layer, the key
is removed — the meta-hash should treat it as absent for both
reads and `has_key?`." This case matters when a layer wants to
explicitly *clear* something an upper layer set, with the same
semantics as if no upper layer had set it.

A real motivation: `%chain` crossing a security barrier might
need to remove certain keys from the inherited chain. A null
value isn't quite right (caller can tell there was *something*
called that key via `has_key?`); a delete marker is.

<a id="two-candidate-designs"></a>
## Two candidate designs

<a id="a-null-flavor"></a>
### A — Null flavor

Add `puck.uno/null/flavor/deleted` to the existing
null-flavor system. Hashes hold it as a value at a key like any
other null. Meta-hash recognizes the flavor specifically: the
key is treated as truly absent for both `[]` and `has_key?`.

Pros:
- Reuses existing null-subclassing machinery; no new top-level
  concept.
- Callers who don't care just see null.

Cons:
- Adds one more well-known null flavor.
- Serialization: needs a JSON representation per the broader
  null-flavor serialization plan.

<a id="b-dedicated-singleton-sentinel"></a>
### B — Dedicated singleton sentinel

Define `puck.uno/hash/deleted` (or `%delete`) as its own
sentinel, not a null. Hashes can hold it; meta-hash special-cases
it.

Pros:
- Explicit about what it is — a marker, not a value.
- Wouldn't get confused with a regular null at the same key.

Cons:
- New top-level concept; one more thing to learn.
- Doesn't compose with anything else.

<a id="edge-cases-either-design-has-to-answer"></a>
## Edge cases either design has to answer

- **Iteration on a plain hash.** Does `$h.keys` include keys
  whose value is a deletion marker? Probably yes — the hash
  genuinely has the key, the marker is just an unusual value.
  The "absent" interpretation only fires inside meta-hash.
- **Plain `null` vs. delete-marker in a meta-hash layer.** Plain
  null stops the upward search and returns null (per current
  meta-hash spec). Delete-marker also stops the upward search
  but reports as absent. Both shadow inherited keys; the
  difference is what `has_key?` reports.
- **Serialization.** Both designs need a wire representation.
  Probably keyed off the null-flavor or sentinel registration
  rather than special-cased in the hash serializer.

<a id="preference-not-committed"></a>
## Preference (not committed)

A (null flavor) leans cleaner — leverages an existing pattern,
adds nothing structurally new, fits the rest of the
null-as-typed-thing model.

<a id="status"></a>
## Status

Not in v1. Filed for reconsideration when either meta-hash
genuinely needs it (more than `%chain`'s security barrier, which
can build a fresh chain instead — see [meta-hash.md](../requirements/caspian/built-in-classes/meta-hash.md))
or another cascading-config use case surfaces.
