# Array Methods

<a id="overview"></a>
## Overview

~~~vibecode
{"vibecode": {
	"section": "overview",
	"type": "Array",
	"notes": ["ordered_collection", "zero_based_indexing",
		"set_theory_methods_use_unicode_symbols_with_named_aliases",
		"sparse_storage_large_gaps_cost_nothing"],
	"example_universe": "Narnia"
}}
~~~

Arrays are ordered collections. Indices are zero-based. Array methods that return a new
array do not mutate the original.

**Sparse-friendly.** Assigning to a large index doesn't allocate the
intervening slots. `$arr[109993] = 'bar'` costs the same as
`$arr[0] = 'bar'` — only populated cells take memory. The unset cells in
between read as unflavored `null`.

---

<a id="set-theory"></a>
## Set Theory

~~~vibecode
{"vibecode": {
	"section": "set_theory",
	"unicode_methods": ["⊂", "⊆", "∪", "∩", "∅?"],
	"binary_operators": ["∈", "∉"],
	"named_aliases": {
		"∈": "in", "∉": "not_in",
		"⊂": "proper_subset_of?", "⊆": "subset_of?",
		"∪": "union", "∩": "intersection", "∅?": "empty?"
	}
}}
~~~

Caspian supports set-theory operations on arrays using Unicode symbols. Each symbol has
a plain-English alias.

<a id="binary-operators"></a>
### Binary Operators

`∈` and `∉` are binary operators registered in the scope, not methods on Array. They
sit naturally between the element and the collection:

```
$x ∈ $array       # true if $x is in $array
$x ∉ $array       # true if $x is not in $array

$x in $array      # same — English alias
$x not_in $array  # same — English alias
```

<a id="array-methods"></a>
### Array Methods

| Symbol | Name | Returns | Description |
|--------|------|---------|-------------|
| `∅?` | `empty?` | Boolean | True if the array has no elements |
| `∪($other)` | `union($other)` | Array | All elements from both arrays, duplicates removed |
| `∩($other)` | `intersection($other)` | Array | Only elements present in both arrays |
| `⊂($other)` | `proper_subset_of?($other)` | Boolean | True if every element of this array is in `$other` and `$other` has at least one element not in this array |
| `⊆($other)` | `subset_of?($other)` | Boolean | True if every element of this array is in `$other` (equal arrays satisfy this) |

<a id="ordering"></a>
### Ordering

Set operations treat arrays as unordered by default. Pass `ordered: true` to make the
result follow the left array's element order:

```
$a = [3, 1, 2]
$b = [2, 4, 1]

$a.∪($b)                    -> order not guaranteed
$a.∪($b, ordered: true)     -> [3, 1, 2, 4]

$a.∩($b)                    -> order not guaranteed
$a.∩($b, ordered: true)     -> [1, 2]   # left array order for matching elements
```

`⊂` and `⊆` return a Boolean and are always unordered — `ordered:` does not apply.

<a id="equality"></a>
### Equality

`∈` and `∉` use `==` for element comparison. This means a custom class that overrides
`==` affects membership testing. That is intentional and the caller's responsibility.

Examples:

```
$a = [1, 2, 3]
$b = [2, 3, 4]
$c = [1, 2, 3, 4]

$a.∪($b)               -> {1, 2, 3, 4}  (unordered)
$a.union($b)           -> {1, 2, 3, 4}

$a.∩($b)               -> {2, 3}  (unordered)
$a.intersection($b)    -> {2, 3}

$a.⊂($c)               -> true
$a.proper_subset_of?($c) -> true

$a.⊆($a)               -> true
$a.subset_of?($a)      -> true

2 ∈ $a                 -> true
2 in $a                -> true

5 ∉ $a                 -> true
5 not_in $a            -> true

[].∅?                  -> true
$a.empty?              -> false
```

---

<a id="elements"></a>
## Elements

~~~vibecode
{"vibecode": {
	"section": "elements",
	"method": "elements",
	"returns": "Array of element objects",
	"notes": ["live_references_synced_with_array",
		"deleted_element_raises_on_any_method_call",
		"index_is_zero_based",
		"move_methods_clamp_at_boundaries"]
}}
~~~

`elements` returns an array of **element objects**, one per element in the array. Each
element object is a live reference: it knows its current index and stays in sync with the
array as elements are moved or deleted.

```
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[0].value   -> 'Lucy'
$els[0].index   -> 0
```

<a id="element-object-api"></a>
### Element Object API

| Method | Returns | Description |
|--------|---------|-------------|
| `value` | Any | The element's value |
| `index` | Number | Current 0-based position in the array |
| `index=($n)` | nil | Move to position `$n`. Other elements shift to fill the gap. |
| `move_left` | nil | Swap with the element immediately to the left. No-op if already at index 0. |
| `move_left($n)` | nil | Move left by `$n` positions. Clamps at index 0. |
| `move_right` | nil | Swap with the element immediately to the right. No-op if already at the last index. |
| `move_right($n)` | nil | Move right by `$n` positions. Clamps at the last index. |
| `move_to_start` | nil | Move to index 0. |
| `move_to_end` | nil | Move to the last position. |
| `delete` | nil | Remove this element from the array. All subsequent method calls on this element raise an exception. |

<a id="live-sync"></a>
### Live Sync

Element objects reflect the current state of the array. Moving one element updates the
`index` of all affected elements:

```
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[2].move_to_start

$arr            -> ['Susan', 'Lucy', 'Edmund']
$els[0].value   -> 'Susan'   # $els[0] is now 'Susan'
$els[1].value   -> 'Lucy'
$els[2].value   -> 'Edmund'
```

<a id="deleted-elements"></a>
### Deleted Elements

After `delete`, the element is removed from the array. Any method call on the deleted
element raises an exception:

```
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[1].delete

$arr            -> ['Lucy', 'Susan']
$els[1].value   # raises exception — element has been deleted
```

---

<a id="searching-find"></a>
## Searching: `find`

~~~vibecode
{"vibecode": {
	"section": "find",
	"method": "find",
	"returns": "Array of Element objects (subset of $arr.elements)",
	"forms": ["value-equality", "block-predicate"],
	"notes": ["always_returns_array_never_single_element",
		"empty_array_when_no_matches",
		"results_are_live_element_objects"]
}}
~~~

`find` is the unified search method on arrays. It **always
returns an array of Element objects** — never a single element,
never nil-on-no-match. The returned array is a subset of
`$arr.elements`, so each result carries its `.value`, `.index`,
and all the live-modification methods (`.move_*`, `.delete`,
etc.).

<a id="value-equality-form"></a>
### Value-equality form

Pass a value; `find` returns every Element whose value `==` the
argument:

```
$arr = ['Lucy', 'Edmund', 'Lucy', 'Susan']

$found = $arr.find('Lucy')

$found.length        -> 2
$found[0].index      -> 0
$found[1].index      -> 2
$found[0].value      -> 'Lucy'
```

If nothing matches, `find` returns `[]` (empty array). No
special "not found" return value.

<a id="block-predicate-form"></a>
### Block-predicate form

Pass a block taking `($index, $element)`; `find` returns every
Element for which the block returns truthy:

```
$arr = [1, 5, 12, 3, 8, 15]

$found = $arr.find() do($index, $element)
    $element.value > 10
end

$found.length        -> 2
$found[0].value      -> 12
$found[1].value      -> 15
```

The block parameters:

- **`$index`** — the position in the source array, passed as a
  convenience. (Equivalent to `$element.index`, just shorter to
  reference.)
- **`$element`** — the Element object at that position. Has
  `.value`, `.index`, and the full Element API.

The block returns truthy to include the Element in the result,
falsey to skip. Implicit last-value return is the idiom; reserve
`%call.return` for actual early exit.

<a id="common-idioms"></a>
### Common idioms

| Want | Idiom |
|---|---|
| All matches | `$arr.find($x)` |
| First match | `$arr.find($x).first` (or `[0]`) |
| Any match? | `$arr.find($x).any?` |
| How many matches? | `$arr.find($x).length` |
| Index of first match | `$arr.find($x).first.index` |
| Delete first match | `$arr.find($x).first.delete` |
| Delete all matches | `$arr.find($x).each do($i, $el); $el.delete; end` |

Because results are live Element references back into the source
array, modification operations on them work as expected — no
stale-index problems and no "modify-while-iterating" undefined
behavior.

<a id="find_first-and-find_last-sugar"></a>
### `find_first` and `find_last` sugar

For the common "I want just the first match" or "just the last
match" cases, two thin sugars:

```
$el = $arr.find_first('Lucy')
$el = $arr.find_last('Lucy')

$el = $arr.find_first() do($index, $element)
    $element.value > 10
end
$el = $arr.find_last() do($index, $element)
    $element.value > 10
end
```

Both return a **single Element object** (or `null` if no match).
Same value-arg / block-predicate forms as `find`.

Equivalent to `$arr.find(...).first` and `$arr.find(...).last`,
just one method call shorter and reads more directly when only
that one hit is wanted.

<a id="why-one-method-always-array"></a>
### Why one method, always-array

Ruby's array search splits across `find` (first match, returns
element or nil), `find_index` (returns index or nil), `select`
(all matches, returns values), and `include?` (returns
boolean). Four methods for what is essentially "show me what
matches." Each has its own return-type quirks.

`find` collapses all four use cases:

- "Did any match?" → `.any?`
- "What's the first match?" → `.first` (or `[0]`)
- "Where is the first match?" → `.first.index`
- "All matches?" → the array itself

One method, one return shape, no nil-on-no-match special case.

---

<a id="random"></a>
## `random`

~~~vibecode
{"vibecode": {
	"section": "random",
	"role": "spec for $array.random — uniform random selection of one or more elements from an array, with options for unique sampling and element-object wrappers; cryptographically secure via libsodium",
	"key_concepts": ["single_or_multi_pick", "with_replacement_by_default",
		"unique_kwarg_for_without_replacement", "elements_kwarg_for_wrapper_objects",
		"secure_via_libsodium"]
}}
~~~

Picks one or more elements uniformly at random from the array. Uses
the same cryptographically strong source as
[`%utils.random`](../global-methods/utils/index.md#utilsrandom) — libsodium's
unbiased range function, no modulo bias.

```
$array = ['a', 'b', 'c', 'd', 'e']

$array.random                        # one element, e.g. 'c'
$array.random(3)                     # three elements, with replacement; e.g. ['a', 'a', 'c']
$array.random(3, unique: true)       # three elements, no repeats; e.g. ['d', 'a', 'b']
$array.random(3, elements: true)     # three element objects (see Elements section above)
```

<a id="random-shape"></a>
### Shape

| Form | Returns |
|------|---------|
| `$array.random` | A single value picked uniformly. |
| `$array.random(n)` | An array of `n` values, **with replacement** (the same index may be picked more than once). |
| `$array.random(n, unique: true)` | An array of `n` values, **without replacement** (each index picked at most once). |
| `$array.random(n, elements: true)` | An array of `n` [element objects](#elements) instead of values. Combinable with `unique:`. |

`unique:` and `elements:` are independent; either or both may be set.

<a id="random-order"></a>
### Order

Returned arrays are in **random order**, not source order. Each pick is
independent; preserving source order would leak information about the
source.

<a id="random-element-objects-with-replacement"></a>
### Element objects with replacement

When `elements: true` is combined with the default (with-replacement)
sampling, the same index can appear more than once. Each appearance
is a **distinct element-object wrapper** pointing at that index;
calling `.delete` on one removes the underlying element, and any
subsequent method call on the other wrapper raises per the
[Deleted Elements](#deleted-elements) rule.

If that's a foothold for surprise, pass `unique: true` to guarantee
each wrapper refers to a different index.

<a id="random-errors"></a>
### Errors

- `[].random` (empty array) — raises. An empty array has nothing to pick.
- `[].random(n)` — raises, same reason.
- `$array.random(n, unique: true)` with `n > $array.length` — raises;
  can't draw that many unique values.
- `$array.random(n)` with `n < 0` — raises.

`$array.random(0)` is **not** an error — it returns `[]`. Zero
random picks is a degenerate but well-defined request.

---

<a id="open-questions"></a>
## Open Questions

- `⊃` (proper superset) and `⊇` (superset or equal) are not included — use
  `$b.⊂($a)` and `$b.⊆($a)` instead. May be added later if there is demand.
