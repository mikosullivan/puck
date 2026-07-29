# Idea: `by:` kwarg for set operations

~~~vibecode
{"vibecode": {
	"doc": "set_operations_by_key",
	"role": "brainstorm — a deferred post-V1 idea to add a `by:` kwarg to array set operations (union, intersection, difference, symmetric_difference, subset predicates, disjoint?) so callers can key comparisons off a block-returned value instead of using full-recursive `==` equality. Motivated by record-shaped data where 'same element' means 'same primary key' rather than 'same full contents.'",
	"status": "deferred — revisit after V1",
	"references": ["https://puck.uno/ideas/array-methods#set-operations"]
}}
~~~

**Status: deferred to post-V1.** V1's set operations use `==` for element equality, which does a full recursive comparison of the structure — nested arrays and hashes are walked, and both must be in the same order to match. This is sufficient for the common case; for the record-with-primary-key case, callers can convert to a shape where `==` gives the right answer (e.g., `.map` to just the keys, intersect, then look up).

Revisit this after V1 ships and there's real usage data on how often the map-then-set pattern shows up.

## The pattern this idea addresses

Two lists of user records that represent "the same user" in different states:

~~~caspian
$logged_in = [
	{id: 1, name: 'Alice', last_seen: '2026-07-05 09:00'},
	{id: 2, name: 'Bob',   last_seen: '2026-07-05 09:03'},
]

$active_today = [
	{id: 1, name: 'Alice', last_seen: '2026-07-05 09:12'},
	{id: 3, name: 'Cara',  last_seen: '2026-07-05 08:45'},
]
~~~

Under `==`-based intersection, `$logged_in.intersection($active_today)` returns `[]` — the two Alice records differ on `last_seen`, so `==` says they're not equal.

The caller's actual notion of "same element" is **same id**. Every other field is incidental.

## The `by:` kwarg shape

Pass a block that projects each element to a comparison key. Set operations call the block once per element on each side, compare the projected keys, and return the original elements (from the appropriate side) for the matches.

~~~caspian
$logged_in.intersection($active_today, by: do ($u)
	return $u.id
end)
# → [{id: 1, name: 'Alice', last_seen: '2026-07-05 09:00'}]
~~~

Same naming convention as `.min_by` / `.max_by` — a reader who knows those knows what `by:` means.

Applies uniformly to every set operation:

- `.union(by: ...)` — union'd by key; left-side value wins on collision.
- `.intersection(by: ...)` — intersect by key; return left-side matching values.
- `.difference(by: ...)` — elements of left whose keys aren't in right.
- `.symmetric_difference(by: ...)` — elements whose keys appear in exactly one side.
- `.subset_of?(by: ...)` — every left key is also a right key.
- `.proper_subset_of?(by: ...)` — subset plus at least one right-only key.
- `.disjoint?(by: ...)` — no shared keys.

## The alternative already available

Without `by:`, the caller writes the pattern manually:

~~~caspian
$logged_in_ids = $logged_in.map do ($u) return $u.id end
$active_ids = $active_today.map do ($u) return $u.id end
$shared_ids = $logged_in_ids.intersection($active_ids)

$shared_users = $logged_in.keep do ($u)
	return $shared_ids.includes?($u.id)
end
~~~

Four lines, two auxiliary variables. Works, but the intent is diluted — the reader has to reconstruct what the code is trying to do.

## Sub-decisions if this ever lands

- **Duplicate keys within one array.** If two records in `$logged_in` share the same id, which one wins in the output? Recommend first-occurrence order (left-array element order).
- **Left vs. right for returned elements.** For `intersection`, return the left-side matching record (matches natural reading order — "give me `$a`'s records that are also in `$b`"). For `union` on key collisions, keep the left-side value. For `difference`, return left-side records (that's the only sensible choice — the result is "left minus right").
- **Composition with sensing predicates.** If `by:` lands on set operations, should `.includes?($x, by: ...)` and `.excludes?($x, by: ...)` also get it, for consistency? Probably yes — but that's a change to a settled method surface.
- **The `by:` block's return value.** Must be equality-comparable. Nothing enforces that at the call site; if the block returns something weird (a closure, an object without `==`), what happens? Probably standard `==` semantics apply — if the projection isn't comparable, the operation raises. Same posture as `.min_by` with a non-comparable projection.

## Related

- [array-methods § Set operations](https://puck.uno/ideas/array-methods#set-operations) — the settled V1 set-operations surface that this kwarg would extend.
