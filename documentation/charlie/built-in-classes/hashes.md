# Hash Methods

<a id="overview"></a>
## 1 Overview

```
vibecode: {
	"section": "overview",
	"type": "Hash",
	"notes": ["ordered_key_value_pairs", "key_order_is_significant",
		"two_hashes_equal_only_if_same_keys_same_values_same_order"]
}
```

Hashes are ordered collections of key-value pairs. Key order is significant — two hashes
with the same keys and values but different insertion order are distinct. Keys are
typically symbols or strings.

---

<a id="basic-methods"></a>
## 2 Basic Methods

```
vibecode: {
	"section": "basic_methods",
	"methods": ["[]", "[]=", "has_key?", "keys", "values", "length",
		"empty?", "any?", "delete"]
}
```

<a id="and"></a>
### 2.1 `[]` and `[]=`

Read and write entries by key:

```
$h = {name: 'Picard', rank: 'Captain'}

$h['name']           -> 'Picard'
$h['ship'] = 'Enterprise'   # adds a new entry
$h['ship']           -> 'Enterprise'
```

Reading a key that doesn't exist returns `null`. Writing
either creates a new entry (appended at the end, preserving
insertion order) or updates the existing value in place
(position preserved).

<a id="has_keykey"></a>
### 2.2 `has_key?(key)`

Predicate. Returns `true` if the hash contains the given key,
`false` otherwise.

```
$h = {name: 'Picard'}
$h.has_key?('name')      -> true
$h.has_key?('rank')      -> false
```

Use this when you need to distinguish "key absent" from "key
present with `null` value" — both make `$h['key']` return null,
but `has_key?` separates them.

<a id="keys"></a>
### 2.3 `keys`

Returns an array of all keys in insertion order.

```
$h = {name: 'Picard', rank: 'Captain', ship: 'Enterprise'}
$h.keys                  -> ['name', 'rank', 'ship']
```

<a id="values"></a>
### 2.4 `values`

Returns an array of all values in insertion order.

```
$h = {name: 'Picard', rank: 'Captain', ship: 'Enterprise'}
$h.values                -> ['Picard', 'Captain', 'Enterprise']
```

<a id="length"></a>
### 2.5 `length`

Returns the number of entries.

```
$h = {name: 'Picard', rank: 'Captain'}
$h.length                -> 2
```

<a id="empty"></a>
### 2.6 `empty?`

Predicate. Returns `true` if the hash has no entries, `false`
otherwise.

```
{}.empty?                -> true
{name: 'Picard'}.empty?  -> false
```

Equivalent to `$h.length == 0` but reads more directly.

<a id="any"></a>
### 2.7 `any?`

Predicate. Returns `true` if the hash has at least one entry,
`false` if empty. The inverse of `empty?`; available for
readability when the natural phrasing is positive.

```
{}.any?                  -> false
{name: 'Picard'}.any?    -> true
```

<a id="deletekey"></a>
### 2.8 `delete(key)`

Removes the entry for the given key and returns the value that
was removed. Returns `null` if the key wasn't present.

```
$h = {name: 'Picard', rank: 'Captain'}
$old = $h.delete('rank')
$old                     -> 'Captain'
$h                       -> {name: 'Picard'}

$h.delete('nonexistent') -> null
```

Position of remaining entries is preserved; deleting from the
middle leaves no gap.

---

<a id="elements"></a>
## 3 Elements

```
vibecode: {
	"section": "elements",
	"method": "elements",
	"returns": "Array of element objects",
	"notes": ["live_references_synced_with_hash",
		"deleted_element_raises_on_any_method_call",
		"index_is_zero_based_position_in_key_order",
		"key_rename_preserves_position",
		"move_methods_clamp_at_boundaries"]
}
```

`elements` returns an array of **element objects**, one per key-value pair in the hash.
Each element object is a live reference: it knows its current key, value, and position,
and stays in sync with the hash as pairs are moved, renamed, or deleted.

```
$h = {name: 'Picard', rank: 'Captain', ship: 'Enterprise'}
$els = $h.elements

$els[0].key     -> 'name'
$els[0].value   -> 'Picard'
$els[0].index   -> 0
```

<a id="element-object-api"></a>
### 3.1 Element Object API

| Method | Returns | Description |
|--------|---------|-------------|
| `key` | String | The element's key |
| `key=($new_key)` | nil | Rename the key. Position in the hash is preserved. If `$new_key` already exists in the hash, that existing pair is replaced — same behavior as regular hash assignment. |
| `value` | Any | The element's value |
| `value=($v)` | nil | Update the element's value in place. |
| `index` | Number | Current 0-based position in key order |
| `index=($n)` | nil | Move to position `$n`. Other elements shift to fill the gap. |
| `move_left` | nil | Swap with the element immediately to the left. No-op if already first. |
| `move_left($n)` | nil | Move left by `$n` positions. Clamps at index 0. |
| `move_right` | nil | Swap with the element immediately to the right. No-op if already last. |
| `move_right($n)` | nil | Move right by `$n` positions. Clamps at the last index. |
| `move_to_start` | nil | Move to index 0. |
| `move_to_end` | nil | Move to the last position. |
| `delete` | nil | Remove this pair from the hash. All subsequent method calls on this element raise an exception. |

<a id="live-sync"></a>
### 3.2 Live Sync

Element objects reflect the current state of the hash. Renaming a key or moving a pair
updates all affected elements:

```
$h = {a: 1, b: 2, c: 3}
$els = $h.elements

$els[0].key = 'z'

$h              -> {z: 1, b: 2, c: 3}
$els[0].key     -> 'z'
```

Moving an element updates the `index` of all affected elements:

```
$h = {a: 1, b: 2, c: 3}
$els = $h.elements

$els[2].move_to_start

$h              -> {c: 3, a: 1, b: 2}
$els[0].key     -> 'c'
$els[1].key     -> 'a'
$els[2].key     -> 'b'
```

Updating a value through the element object is reflected in the hash:

```
$h = {name: 'Picard'}
$els = $h.elements

$els[0].value = 'Riker'

$h              -> {name: 'Riker'}
```

<a id="deleted-elements"></a>
### 3.3 Deleted Elements

After `delete`, the pair is removed from the hash. Any method call on the deleted element
raises an exception:

```
$h = {a: 1, b: 2, c: 3}
$els = $h.elements

$els[1].delete

$h              -> {a: 1, c: 3}
$els[1].key     # raises exception — element has been deleted
```

