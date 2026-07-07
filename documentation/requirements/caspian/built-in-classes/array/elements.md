# Elements
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_array_elements",
	"role": "spec for `.elements` on Array — the method that returns an array of live-reference **element objects**. Each element object tracks its current position in the source array, keeping `.index` and `.value` in sync as the array is mutated by any path. Also spec's the element-object surface (`.value`, `.index`, in-place moves via `.index=`, `.move_left`, `.move_right`, `.move_to_start`, `.move_to_end`, and `.delete`), the live-sync guarantee, and the raise-on-deleted rule.",
	"status": "draft — return value, element-object method surface, live-sync semantics, and deleted-element raise rule all spec'd",
	"audience": "developers writing Caspian; engine implementers building the array runtime"
}}
~~~

`.elements` returns an **elements object** — a live-view handle over the source array that behaves like an array for reads but is not itself an Array instance. Its entries are **element objects**, one per element in the source array; each is a live reference back into the source array that knows its current position and stays in sync as the array is moved, inserted into, or removed from by any path.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[0].value   # 'Lucy'
$els[0].index   # 0
$els.length     # 4 — mirrors the source array
~~~

## The elements object is a live view, not an array

The elements object mirrors the state of the source array:

- **Same length as the source array**, always. The length is a live read, not a snapshot.
- **Element at position `$n` in the elements object corresponds to the value at position `$n` in the source array.** Add, remove, or move a value in the source array and the elements object reflects the change instantly.
- **Element handles are stable** across changes to the source array — an element handle you already hold keeps tracking its own value even as the elements object at your index position may now refer to a different element.

Because it mirrors the source, the elements object does NOT carry most Array methods. Reshaping methods like `.reverse`, `.reverse!`, `.push`, `.pop`, `.shift`, `.unshift`, `.import`, `.insert`, `.remove`, `.clear`, `.sort`, `.shuffle`, and the set operations all raise if called on the elements object — they don't make sense on a live view. To rearrange the source, either call those methods on the source array itself, or use the element-object methods (`.move_left`, `.move_to_start`, `.index = $n`, `.delete`) which are designed to mutate through the view.

Read-only and iteration methods DO work — indexing (`$els[$n]`), `.length`, `.empty?`, `.any?`, `.each`, `.first`, `.last`. These treat the elements object like an array for read purposes; the entries are just element objects instead of raw values.

## Element-object method surface

Summary of every method on an element object; each has its own section below.

| Method | Returns | Description |
|---|---|---|
| `.value` | any | The element's current value. |
| `.value = $new` | null | Setter — replace the value at the element's current position. |
| `.index` | number | Current 0-based position in the array. |
| `.index = $n` | null | Setter — move to position `$n`. Other elements shift to fill the gap. |
| `.move_left` / `.move_left($n)` | null | Move left by one (bare) or by `$n` positions. Clamps at index 0. |
| `.move_right` / `.move_right($n)` | null | Move right by one (bare) or by `$n` positions. Clamps at the last index. |
| `.move_to_start` | null | Move to index 0. |
| `.move_to_end` | null | Move to the last position. |
| `.delete` | null | Remove this element from the source array. See [`.delete`](#delete) below. |

### `.value`

Returns the element's current value — the same value that `$arr[$el.index]` would return, freshly read on every call. If the array is mutated so that a different value now sits at this element's tracked position, `.value` reflects that.

~~~caspian
$arr = ['Lucy', 'Edmund']
$els = $arr.elements

$els[0].value        # 'Lucy'

$arr[0] = 'Susan'    # direct write to the array
$els[0].value        # 'Susan' — element handle tracks the slot, not the old value
~~~

### `.value = $new` (setter)

Replaces the value at the element's current position. Equivalent to `$arr[$el.index] = $new`, but the element handle owns the target — no manual index reference needed. Returns `null`.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[1].value = 'Peter'

$arr             # ['Lucy', 'Peter', 'Susan']
$els[1].value    # 'Peter' — same element handle, new value
$els[1].index    # 1 — position didn't change
~~~

The setter changes what's stored at the tracked slot. It does not move the element, doesn't delete anything, and doesn't touch neighboring positions. The element handle continues to reference the same slot before and after.

### `.index`

Returns the element's current 0-based position in the array. Reflects any position changes from previous element-object moves or from mutations that came through other paths (a `.push`, `.insert`, `.remove`, `.shift`, etc.).

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[1].index        # 1

$arr.unshift('Peter')
$els[1].index        # 2 — everything shifted right by one
~~~

### `.index = $n` (setter)

Moves this element to position `$n`. Other elements shift to fill the gap left behind and to make room at the destination. Returns `null`.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[3].index = 0    # move Peter to the front

$arr                 # ['Peter', 'Lucy', 'Edmund', 'Susan']
$els[3].index        # 0 — same element, new position
~~~

`$n` outside `[0, .length - 1]` raises. If you want "clamp to the ends" behavior, use `.move_to_start` / `.move_to_end` or `.move_left($n)` / `.move_right($n)`, which clamp.

### `.move_left` / `.move_left($n)`

Move this element toward the start of the array. The bare form swaps with the immediately-left neighbor (equivalent to `.move_left(1)`). The `.move_left($n)` form moves `$n` positions left. Both clamp at index 0 — asking to move further left than the start is a no-op for the excess, not a raise.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[2].move_left           # swap with Edmund
$arr                        # ['Lucy', 'Susan', 'Edmund', 'Peter']

$els[2].move_left(10)       # asks to move 10, but clamps at 0
$arr                        # element (still Susan) is now at index 0;
                            # the run of leftward moves stopped there
~~~

Bare `.move_left` on an element already at index 0 is a no-op. `.move_left(0)` is also a no-op.

### `.move_right` / `.move_right($n)`

Mirror of `.move_left`. The bare form swaps with the immediately-right neighbor. The `.move_right($n)` form moves `$n` positions right. Both clamp at the last index.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[0].move_right          # swap Lucy with Edmund
$arr                        # ['Edmund', 'Lucy', 'Susan', 'Peter']

$els[0].move_right(10)      # asks to move 10, but clamps at last index
$arr                        # element (still Edmund) is now at the last index
~~~

Bare `.move_right` on an element already at the last position is a no-op.

### `.move_to_start`

Move this element to index 0. Every other element shifts right by one to make room. Returns `null`.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[2].move_to_start

$arr           # ['Susan', 'Lucy', 'Edmund', 'Peter']
$els[2].index  # 0
~~~

No-op if the element is already at index 0.

### `.move_to_end`

Move this element to the last position. Every other element between the source and destination shifts left by one. Returns `null`.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan', 'Peter']
$els = $arr.elements

$els[0].move_to_end

$arr           # ['Edmund', 'Susan', 'Peter', 'Lucy']
$els[0].index  # 3
~~~

No-op if the element is already at the last position.

### `.delete`

Remove this element from the source array. Every element to the right of the deleted position shifts left by one to close the gap. Returns `null`.

**The element handle survives** — see [Deleted elements](#deleted-elements) below. Its `.index` becomes `null`; `.value` still works; and the element can be re-inserted into the array by setting `.index`, calling `.move_to_start`, or calling `.move_to_end`.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[1].delete
$arr            # ['Lucy', 'Susan']

$els[1].value   # 'Edmund' — the deleted element still knows its value
$els[1].index   # null — not in the array

$els[2].value   # 'Susan' — the element that was at index 2 tracks its new index (now 1)
$els[2].index   # 1
~~~

The handle for a non-deleted element continues to work normally; it just knows about its new position after the shift.

## Live sync

Element objects reflect the current state of the array. Moving one element updates the `.index` of every element affected by the shift, and dispatching `.value` on any element always reads the current slot:

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[2].move_to_start

$arr            # ['Susan', 'Lucy', 'Edmund']
$els[0].value   # 'Susan'
$els[1].value   # 'Lucy'
$els[2].value   # 'Edmund'
~~~

Element objects also stay in sync when the underlying array is mutated by other paths — a `.push` on the array, an `.insert` or `.remove` from another caller, a swap through some other reference to the same array. Nothing about element objects is snapshot-at-fetch-time; every method call reads the current state.

## Deleted elements

After `.delete`, the element is removed from the source array, but **the element handle survives**. It still holds the value; it just isn't currently in any array. Callers can hold onto a deleted element, inspect it, modify its value, and re-insert it into the array at a chosen position.

What works on a deleted element:

- **`.index`** returns `null` — the element has no position because it's not in the array.
- **`.value`** returns the value the element held at the time of deletion. Callers can also assign via `.value = $new` to change what the element holds.
- **`.index = $n`** re-inserts the element into the source array at position `$n`. Other elements shift right to make room. After this call, `.index` returns `$n`.
- **`.move_to_start`** re-inserts the element at position 0.
- **`.move_to_end`** re-inserts the element at the last position.
- **`.delete`** on an already-deleted element is a no-op.

What raises on a deleted element:

- **`.move_left`** / **`.move_left($n)`** and **`.move_right`** / **`.move_right($n)`** — these are relative-position moves. There's no current position to move relative to, so they raise. Use `.index = $n` if you know the target position.

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els[1].delete

$arr            # ['Lucy', 'Susan']
$els[1].value   # 'Edmund' — value still available
$els[1].index   # null — not currently in the array

# Re-insert:
$els[1].index = 0
$arr            # ['Edmund', 'Lucy', 'Susan']
$els[1].index   # 0

# Or change the value first, then re-insert:
$els[1].delete
$els[1].value = 'Peter'
$els[1].move_to_end
$arr            # ['Lucy', 'Susan', 'Peter']
~~~

A deleted element that's never re-inserted is fine — it just sits in memory holding its value until the caller drops the reference.

## Related

- [Array](../) — the parent Array class doc; `.elements` is one of its methods.
