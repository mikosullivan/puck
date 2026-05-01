# Array Methods

## Overview

```
vibecode: {
	"section": "overview",
	"type": "Array",
	"notes": ["ordered_collection", "zero_based_indexing",
		"set_theory_methods_use_unicode_symbols_with_named_aliases"]
}
```

Arrays are ordered collections. Indices are zero-based. Array methods that return a new
array do not mutate the original.

---

## Set Theory

```
vibecode: {
	"section": "set_theory",
	"unicode_methods": ["⊂", "⊆", "∪", "∩", "∅?"],
	"binary_operators": ["∈", "∉"],
	"named_aliases": {
		"∈": "in", "∉": "not_in",
		"⊂": "proper_subset_of?", "⊆": "subset_of?",
		"∪": "union", "∩": "intersection", "∅?": "empty?"
	}
}
```

KScript supports set-theory operations on arrays using Unicode symbols. Each symbol has
a plain-English alias.

### Binary Operators

`∈` and `∉` are binary operators registered in the scope, not methods on Array. They
sit naturally between the element and the collection:

```
$x ∈ $array       # true if $x is in $array
$x ∉ $array       # true if $x is not in $array

$x in $array      # same — English alias
$x not_in $array  # same — English alias
```

### Array Methods

| Symbol | Name | Returns | Description |
|--------|------|---------|-------------|
| `∅?` | `empty?` | Boolean | True if the array has no elements |
| `∪($other)` | `union($other)` | Array | All elements from both arrays, duplicates removed |
| `∩($other)` | `intersection($other)` | Array | Only elements present in both arrays |
| `⊂($other)` | `proper_subset_of?($other)` | Boolean | True if every element of this array is in `$other` and `$other` has at least one element not in this array |
| `⊆($other)` | `subset_of?($other)` | Boolean | True if every element of this array is in `$other` (equal arrays satisfy this) |

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

## Elements

```
vibecode: {
	"section": "elements",
	"method": "elements",
	"returns": "Array of element objects",
	"notes": ["live_references_synced_with_array",
		"deleted_element_raises_on_any_method_call",
		"index_is_zero_based",
		"move_methods_clamp_at_boundaries"]
}
```

`elements` returns an array of **element objects**, one per element in the array. Each
element object is a live reference: it knows its current index and stays in sync with the
array as elements are moved or deleted.

```
$arr = ['a', 'b', 'c', 'd']
$els = $arr.elements

$els[0].value   -> 'a'
$els[0].index   -> 0
```

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

### Live Sync

Element objects reflect the current state of the array. Moving one element updates the
`index` of all affected elements:

```
$arr = ['a', 'b', 'c']
$els = $arr.elements

$els[2].move_to_start

$arr            -> ['c', 'a', 'b']
$els[0].value   -> 'c'   # $els[0] is now 'c'
$els[1].value   -> 'a'
$els[2].value   -> 'b'
```

### Deleted Elements

After `delete`, the element is removed from the array. Any method call on the deleted
element raises an exception:

```
$arr = ['a', 'b', 'c']
$els = $arr.elements

$els[1].delete

$arr            -> ['a', 'c']
$els[1].value   # raises exception — element has been deleted
```

---

## Open Questions

- `⊃` (proper superset) and `⊇` (superset or equal) are not included — use
  `$b.⊂($a)` and `$b.⊆($a)` instead. May be added later if there is demand.
