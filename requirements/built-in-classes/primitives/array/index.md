# Array
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_array",
	"role": "spec for Caspian's built-in array class — ordered sequence of arbitrary values with integer indexing. Zero-based. Covers the literal form, the symmetric-indexing convention, the `!` return-new-vs-in-place naming convention, the guaranteed method surface (push/pop/shift/unshift, sample, each, query, aggregation, modification, cycling, dig, conversion), set-theoretic operations (union, intersection, difference, symmetric difference, subset predicates, disjoint) with Unicode-symbol dual naming, and the Excluded methods table listing what's been rejected.",
	"status": "draft — literal form, indexing, ! convention, core method surface, and set operations spec'd; a few narrower questions may still surface as the language exercises the surface",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

An **array** is an ordered sequence of arbitrary values, indexed by integer position. Every array literal in Caspian source materializes into an instance.

## Literal form

~~~caspian
$items = [1, 2, 3]
$mixed = ['alice', 42, true, null, [1, 2], {name: 'inner'}]
~~~

## Zero-based indexing, from both ends

Arrays are **zero-indexed on both sides**. Positive indices count from the start; negative indices count from the end. Zero starts at each side — `$arr[0]` is the first element, `$arr[-0]` is the last.

~~~caspian
$arr = ['a', 'b', 'c', 'd', 'e']

$arr[0]    # 'a' — 0 from the start
$arr[1]    # 'b' — 1 from the start
$arr[4]    # 'e' — 4 from the start (last)

$arr[-0]   # 'e' — 0 from the end (last)
$arr[-1]   # 'd' — 1 from the end
$arr[-4]   # 'a' — 4 from the end (first)
~~~

The symmetric-indexing pattern relies on **[negative zero](https://puck.uno/requirements/built-in-classes/number/#negative-zero)**. `-0` is a distinct signed-zero value that equals `0` in every other context (arithmetic, comparison, hash keys) but reads as "0 from the end" when used as an array index.

This is a deliberate departure from Ruby and Python conventions where `$arr[-1]` is the last element. In Caspian, `$arr[-1]` is the SECOND-to-last (1 from the end); `$arr[-0]` is the last (0 from the end). The trade-off is worth it because the from-start and from-end index schemes now match — you never have to remember "0 from the front but 1 from the back."

**Out-of-range indices raise.** `$arr[5]` on a 5-element array raises; so does `$arr[-5]`.

## The `!` convention: return-new vs in-place

Methods that would produce a modified array come in **pairs**: the plain form returns a new array; the `!`-suffixed form modifies the receiver in place and returns it. Callers pick based on whether they need to preserve the original.

| Method | Description |
|---|---|
| `.unique` | Returns a new array with duplicate values removed, preserving first-occurrence order. |
| `.unique!` | Modifies the array in place, removing duplicate values. Returns the array. |
| `.compact` | Returns a new array with `null` values removed, preserving order. Only nulls are removed — `false`, `0`, `''`, `[]`, `{}` all stay. |
| `.compact!` | Modifies the array in place, removing `null` values. Returns the array. Same null-only rule. |
| `.keep` | Called without a block, returns a new array containing only the truthy items. Called with a block, returns a new array containing every item for which the block returned truthy. |
| `.keep!` | Same as `.keep` but modifies the array in place. Returns the array. |
| `.reject` | Called without a block, returns a new array containing only the falsy items (i.e., only `null` and `false`, since those are the only falsy values). Called with a block, returns a new array containing every item for which the block returned falsy. |
| `.reject!` | Same as `.reject` but modifies the array in place. Returns the array. |
| `.shuffle` | Returns a new array with the same items in a random order. Draws from `%('core:random')`. |
| `.shuffle!` | Modifies the array in place, reordering the items randomly. Returns the array. |
| `.import($items)` | Returns a new array with `$items` appended. If `$items` is an array, its elements are appended (one level of unwrapping — inner arrays stay as arrays). If `$items` is a scalar, it's appended as a single element. |
| `.import!($items)` | Same as `.import` but modifies the array in place. Returns the array. |
| `.map` | Takes a block called once per element with the element as its argument. Returns a new array of the block's return values. |
| `.map!` | Same as `.map` but modifies the array in place, replacing each element with the block's return value. Returns the array. |
| `.flatten` | Returns a new array with nested arrays unwrapped. Default unwraps ONE level — inner arrays inside those stay as arrays. Pass `depth: N` to unwrap N levels; pass `depth: :all` to unwrap recursively to the bottom. |
| `.flatten!` | Same as `.flatten` but modifies the array in place. Returns the array. Same `depth:` kwarg. |
| `.rotate($n)` | Returns a new array rotated left by `$n` positions — the first `$n` elements move to the end. Negative `$n` rotates right. |
| `.rotate!($n)` | Same as `.rotate` but modifies the array in place. Returns the array. |
| `.reverse` | Returns a new array with the elements in reverse order. |
| `.reverse!` | Reverses the array in place. Returns the array. |

Block form for `.keep` and `.reject`:

~~~caspian
$items = [1, 2, 3, 4, 5]

$evens = $items.keep do ($n)
	return $n.even?
end
# $evens is [2, 4]

$odds = $items.reject do ($n)
	return $n.even?
end
# $odds is [1, 3, 5] — items where the block returned false are kept
~~~

Same convention for any future mutating pair: `.sort` / `.sort!`, `.reverse` / `.reverse!`, etc.

### `.import` vs `.push`

Both add to the end of the array; they differ in whether the argument gets unwrapped:

~~~caspian
[1, 2].push([3, 4])            # [1, 2, [3, 4]]   — push never unwraps
[1, 2].import([3, 4])          # [1, 2, 3, 4]     — import unwraps one level

[1, 2].push('foo')             # [1, 2, 'foo']    — same in both for scalars
[1, 2].import('foo')           # [1, 2, 'foo']
~~~

Pick `.push` when you want to add a single item as-is; pick `.import` when you want to append every element of another sequence.

### `+` operator and `+=` compound assignment

Because operators are methods on the left operand's class, array's `+` method IS `.import`. `$arr + $other_arr` is equivalent to `$arr.import($other_arr)` — returns a new array, doesn't mutate.

`$arr += $other_arr` desugars to `$arr = $arr + $other_arr` — a rebind, not an in-place mutation. That produces the same visible result as `$arr.import!($other_arr)` **when the array isn't shared**, but diverges when it is:

~~~caspian
$a = [1, 2]
$b = $a                        # $b references the same array as $a

$a += [3, 4]                   # $a is now a new [1, 2, 3, 4]; $b is still [1, 2]

$c = [1, 2]
$d = $c
$c.import!([3, 4])             # $c AND $d both see [1, 2, 3, 4] — same object mutated
~~~

Pick `.import!` when you want the shared object to change; pick `+=` when you want to leave whoever else holds the reference alone.

## Method surface

| Method | Description |
|---|---|
| `.sample` | Returns a randomly selected element from the array. Draws from `%('core:random')`. Raises on an empty array. |
| `.sample($n)` | Returns a new array of `$n` randomly selected elements without replacement — the same element is never returned twice. Raises if `$n` is negative or larger than `.length`. Pass `allow_duplicates: true` to sample WITH replacement — the same element may then appear more than once and `$n` may exceed `.length`. |
| `.push($item)` | Appends `$item` to the end of the array. Returns the array. Modifies in place. |
| `.pop` | Removes and returns the last element. Returns `null` on an empty array. Modifies in place. |
| `.pop($n)` | Removes the last `$n` elements and returns them as a new array. If `$n` is greater than `.length`, returns all remaining elements. Raises on negative `$n`. Modifies in place. |
| `.unshift($item)` | Inserts `$item` at the beginning of the array. Returns the array. Modifies in place. |
| `.shift` | Removes and returns the first element. Returns `null` on an empty array. Modifies in place. |
| `.shift($n)` | Removes the first `$n` elements and returns them as a new array. If `$n` is greater than `.length`, returns all remaining elements. Raises on negative `$n`. Modifies in place. |
| `.each` | Takes a block called once per element with the element as its argument. Returns the block's last-expression value from the last iteration; if `$loop.return $value` fires inside the block, returns `$value` instead — the "use `.each` as a search" pattern. Returns `null` if the array is empty (no iterations, no last expression). Bind `as $loop` to get access to `$loop.index`, `$loop.count`, `$loop.break`, `$loop.next`, and `$loop.return $value` — see [loops § Loop object methods](https://puck.uno/requirements/syntax/loops#loop-object-methods). There is no separate `.each_with_index`; use `as $loop`. |

Note: `.push`, `.pop`, `.unshift`, and `.shift` don't follow the `!` naming convention because they don't have return-new-array counterparts — the names inherently signal mutation, and there's nothing to distinguish from. The `!` suffix marks the mutating side of a **pair**; when only one form exists, the suffix is redundant.

### Query and predicates

| Method | Description |
|---|---|
| `.length` | Number of elements as a [number](https://puck.uno/requirements/built-in-classes/number/). |
| `.empty?` / `.∅?` | True if the array has no elements. `∅?` is a Unicode alias — `∅` is the empty-set symbol; both names call the same method. |
| `.any?` / `.∃?` | True if the array has at least one element. Complement of `.empty?`. `∃?` is a Unicode alias — `∃` is the mathematical "there exists" quantifier; both names call the same method. No block form — for "does any element satisfy this predicate," use `.keep(block).any?`. |
| `.first` | The first element. Same as `$arr[0]`. Raises on an empty array. |
| `.last` | The last element. Same as `$arr[-0]`. Raises on an empty array. |
| `.includes?($x)` | True if any element equals `$x`. |
| `.excludes?($x)` | True if no element equals `$x`. Complement of `.includes?`. |

### Aggregation

| Method | Description |
|---|---|
| `.sum` | Sum of all numeric elements. Raises on an empty array or on any non-numeric element. |
| `.product` | Product of all numeric elements. Raises on an empty array or on any non-numeric element. |
| `.min` | Smallest element by natural ordering. Raises on an empty array. |
| `.max` | Largest element by natural ordering. Raises on an empty array. |
| `.min_by` | Takes a block returning a comparable key per element. Returns the element with the smallest key. Raises on an empty array. |
| `.max_by` | Takes a block returning a comparable key per element. Returns the element with the largest key. Raises on an empty array. |

### Modification (mutating, no return-new counterpart)

| Method | Description |
|---|---|
| `.insert($index, $item)` | Inserts `$item` at `$index`, shifting later elements right. `$index` may be any integer in `[0, .length]` inclusive (position at `.length` appends). Modifies in place. Returns the array. Raises on out-of-range `$index`. |
| `.remove($index)` | Removes and returns the element at `$index`. Later elements shift left. Modifies in place. Raises on out-of-range `$index`. |
| `.clear` | Removes every element. Modifies in place. Returns the empty array. |

### Cycling

| Method | Description |
|---|---|
| `.cycle` | Returns the first element and rotates the array left by one position in place. Useful for round-robin patterns — cycling line colors, alternating table rows, distributing work across a fixed set. Raises on an empty array. Mutates; no return-new counterpart (per the `!` convention, a bang variant isn't needed when only one form exists). |

Worked example:

~~~caspian
$colors = ['red', 'green', 'blue']

$row_1_color = $colors.cycle   # 'red';   $colors is now ['green', 'blue', 'red']
$row_2_color = $colors.cycle   # 'green'; $colors is now ['blue', 'red', 'green']
$row_3_color = $colors.cycle   # 'blue';  $colors is now ['red', 'green', 'blue']
$row_4_color = $colors.cycle   # 'red';   $colors is now ['green', 'blue', 'red']
~~~

Related but distinct: `.rotate` / `.rotate!` return the rotated array (whole array); `.cycle` returns the element that was first (single value) AND rotates in place.

### Nested access

| Method | Description |
|---|---|
| `.dig($key1, $key2, ...)` | Traverse a nested structure — arrays inside arrays, hashes inside arrays, and so on — with the given sequence of keys. Returns `null` at the first missing key or `null` value; never raises on missing keys. `$response.dig('users', 0, 'name')` returns `null` if `users` doesn't exist, or if it exists but has no element at index 0, or if that element doesn't have a `name` key. |

### Conversion

| Method | Description |
|---|---|
| `.join($sep)` | Concatenates every element's string form with `$sep` between them. `$sep` is optional — omitted defaults to empty string. Each element is converted to string via its `.to.string` (per the conversion protocol) or `.to_string` in the interim. |
| `.to_hash` | Converts an array of `[key, value]` pairs into a hash. Raises if any element isn't a two-element array. Migrates to `.to.hash` once the conversion protocol lands. |

## Set operations

Set-theoretic operations on arrays — union, intersection, difference, symmetric difference, and subset relationships. Every combination and predicate operation gets **two names**: a Unicode mathematical symbol and a plain-English method name. Both compile to the same call.

The Unicode symbol forms follow the no-dot method rule — the symbol sits between the receiver and the argument, separated by spaces, with no dot: `$a ∪ $b`. Parens around the argument are optional (Caspian's general rule for any method call). The English forms keep the dot: `$a.union($b)`.

### Combination operations

Return a new array; never mutate the receiver.

| Symbol | Method | Description |
|---|---|---|
| `$a ∪ $b` | `$a.union($b)` | All elements from either, duplicates removed. Returns `$a`'s elements in order followed by `$b`-only elements in `$b`'s order. |
| `$a ∩ $b` | `$a.intersection($b)` | Only elements present in both. Returns `$a`'s elements that are also in `$b`, in `$a`'s order. |
| [none] | `$a.difference($b)` | Elements of `$a` not in `$b`, in `$a`'s order. English form only — the standard mathematical symbol `\` (formalized as `∖`) renders identically to a backslash in most fonts, so difference gets no symbol form. |
| `$a △ $b` | `$a.symmetric_difference($b)` | Elements in exactly one of `$a` or `$b` — the two-sided "what's not shared." Returns `$a`'s exclusive elements in `$a`'s order, followed by `$b`'s exclusive elements in `$b`'s order. |

### Set predicates

Return a boolean.

| Symbol | Method | Description |
|---|---|---|
| `$a ⊂ $b` | `$a.proper_subset_of?($b)` | True if every element of `$a` is in `$b` AND `$b` has at least one element not in `$a`. |
| `$a ⊆ $b` | `$a.subset_of?($b)` | True if every element of `$a` is in `$b`. Equal arrays satisfy this. |
| [none] | `$a.disjoint?($b)` | True if `$a` and `$b` share no elements. English form only — no standard Unicode symbol exists. |

`.empty?` / `.∅?` and `.any?` / `.∃?` are also set-theoretic in flavor and documented in the [Query and predicates](#query-and-predicates) table above.

### Equality basis for set operations

Set operations compare elements with `==`. Caspian's `==` does a full recursive comparison of the structure — nested arrays and hashes are walked all the way down, and both must be in the same order to match.

### Excluded set-operation forms

Considered and rejected:

- **Ruby-style operator forms** (`|` for union, `&` for intersection, `-` for difference). `|` collides with the pipe operator; the others are just alternate spellings for surface Caspian already covers with the Unicode symbols and named methods. Adding a third form is friction, not clarity.
- **`⊃` (proper superset) and `⊇` (superset or equal).** Reversed-argument form covers these: `$a ⊃ $b` is the same as `$b ⊂ $a`, so adding both directions is duplicate surface.
- **`∖` (U+2216 SET MINUS) as the symbol for difference.** Renders identically to a backslash in most fonts; visual clash defeats the point of using a symbol.
- **Binary element-containment operators** (`∈`/`in`, `∉`/`not_in`). Element containment stays with the settled `.includes?($x)` and `.excludes?($x)` methods on the array.

## Excluded methods

The following names have been considered and deliberately excluded from the array surface.

**Rejected on merit:**

| Method | Reason |
|---|---|
| `.zip` | Pairing parallel arrays is better handled explicitly with `.each` and paired indexing. |
| `.reduce` (a.k.a. `.fold`) | Fold/reduce reads badly in most real code; `.each` with an outer accumulator is clearer. |
| `.take($n)` | Subsumed by `.pop($n)` and `.shift($n)`, which cover take-from-end and take-from-front with mutation. |
| `.each_with_index` | Subsumed by `as $loop` on `.each`, which gives `$loop.index` (and `$loop.count`, `$loop.break`, `$loop.next`). |
| `.frozen?` | Ruby's mutation-lock predicate; Caspian's role/object model handles mutation gating differently. |

**Alias names rejected (one name per operation):**

| Method | Reason |
|---|---|
| `.size` | Ruby's alias for `.length`; use `.length`. |
| `.each_index` | Obscure; use `.each ... as $loop` and read `$loop.index`. |
| `.collect` | Ruby's alias for `.map`; use `.map`. |
| `.inject` | Ruby's alias for `.reduce`, which is itself excluded. |
| `.detect` | Ruby's alias for `.find`; if a find-like method lands later, its name is `.find`. |

## `<+` append operator

`$arr <+ $item` appends `$item` to the array — equivalent to `$arr.push($item)`. The operator lives in [syntax/operators § `<+` append](https://puck.uno/requirements/syntax/operators/#-append); on an Array receiver it dispatches to the same code path as `.push`.

~~~caspian
$arr = []
$arr <+ 'first'
$arr <+ 'second'
$arr                       # ['first', 'second']
~~~

`<<` was considered and rejected — it collides with the heredoc opener (`<<EOF`) and the disambiguation rules were too invasive for every downstream tool.

## Testing

### Literal form

- **Empty array literal** — `[]` produces an Array with `.length` 0.
- **Single-element literal** — `[42]` produces a 1-element array whose first element is `42`.
- **Homogeneous literal** — `[1, 2, 3]` produces `[1, 2, 3]` with `.length` 3.
- **Mixed-type literal** — `['alice', 42, true, null, [1, 2], {name: 'inner'}]` preserves each element by type and order.
- **Trailing comma tolerated** — `[1, 2, 3,]` parses as `[1, 2, 3]` (if the syntax allows; otherwise raises predictably).
- **Nested-array literal** — `[[1, 2], [3, 4]]` produces a 2-element array whose entries are themselves arrays.
- **Every literal materializes a fresh instance** — two `[1, 2]` literals in source produce two distinct Array objects that compare `==` but are not identity-equal.

### Zero-based symmetric indexing

- **Positive index from start** — for `$arr = ['a', 'b', 'c', 'd', 'e']`, `$arr[0]` returns `'a'`.
- **Positive index middle** — `$arr[2]` returns `'c'`.
- **Positive last index** — `$arr[4]` returns `'e'`.
- **`-0` returns the last element** — `$arr[-0]` returns `'e'`.
- **`-1` returns the second-to-last element** — `$arr[-1]` returns `'d'`, NOT `'e'`.
- **Negative index to first** — `$arr[-4]` returns `'a'`.
- **Out-of-range positive raises** — `$arr[5]` on a 5-element array raises.
- **Out-of-range negative raises** — `$arr[-5]` on a 5-element array raises.
- **Any index on empty array raises** — `[][0]`, `[][-0]`, `[][1]` all raise.
- **`-0` equals `0` arithmetically** — `-0 == 0` is `true`, but `$arr[-0]` and `$arr[0]` return different elements when `.length > 1`.
- **Index by expression** — `$arr[1 + 1]` returns `'c'` for the sample array above.

### `.push`

- **`.push` appends a single element** — `[1, 2].push(3)` returns the array now equal to `[1, 2, 3]`.
- **`.push` mutates in place** — after `$a = [1, 2]; $a.push(3)`, `$a` is `[1, 2, 3]`.
- **`.push` returns the receiver (identity)** — the return value IS the same object as the receiver.
- **`.push` never unwraps** — `[1, 2].push([3, 4])` returns `[1, 2, [3, 4]]`.
- **`.push` accepts null** — `[1].push(null)` returns `[1, null]`.
- **`.push` on an empty array** — `[].push('a')` returns `['a']`.
- **`.push` with no argument raises** — `[].push()` raises.
- **`<+` operator appends** — `$arr = [1, 2]; $arr <+ 3; $arr` returns `[1, 2, 3]`.
- **`<+` on an array is equivalent to `.push`** — `$a = []; $a <+ 'x'; $b = []; $b.push('x'); $a == $b` is `true`.
- **`<+` never unwraps** — `$arr = [1, 2]; $arr <+ [3, 4]; $arr` returns `[1, 2, [3, 4]]` (same rule as `.push`).

### `.pop`

- **`.pop` removes and returns the last element** — `[1, 2, 3].pop` returns `3`; the array becomes `[1, 2]`.
- **`.pop` on empty returns null** — `[].pop` returns `null`, no raise.
- **`.pop($n)` returns a new array of the last `$n`** — `[1, 2, 3, 4].pop(2)` returns `[3, 4]`; array becomes `[1, 2]`.
- **`.pop($n)` where `$n > .length` returns all remaining** — `[1, 2].pop(5)` returns `[1, 2]`; array becomes `[]`.
- **`.pop($n)` with `$n == 0`** — returns `[]`; array unchanged.
- **`.pop($n)` with negative `$n` raises**.

### `.unshift`

- **`.unshift` prepends** — `[2, 3].unshift(1)` returns the array now equal to `[1, 2, 3]`.
- **`.unshift` mutates in place** — after `$a = [2, 3]; $a.unshift(1)`, `$a` is `[1, 2, 3]`.
- **`.unshift` returns the receiver (identity)**.
- **`.unshift` never unwraps** — `[3].unshift([1, 2])` returns `[[1, 2], 3]`.
- **`.unshift` accepts null** — `[1].unshift(null)` returns `[null, 1]`.

### `.shift`

- **`.shift` removes and returns the first element** — `[1, 2, 3].shift` returns `1`; array becomes `[2, 3]`.
- **`.shift` on empty returns null** — `[].shift` returns `null`, no raise.
- **`.shift($n)` returns a new array of the first `$n`** — `[1, 2, 3, 4].shift(2)` returns `[1, 2]`; array becomes `[3, 4]`.
- **`.shift($n)` where `$n > .length` returns all remaining** — `[1, 2].shift(5)` returns `[1, 2]`; array becomes `[]`.
- **`.shift($n)` with negative `$n` raises**.

### `.sample`

- **`.sample` returns an element from the array** — result is one of the elements.
- **`.sample` on empty raises**.
- **`.sample($n)` returns a new array of `$n` elements** — `.length == $n`.
- **`.sample($n)` without replacement** — no duplicate elements in the result (given distinct source elements).
- **`.sample($n)` with `$n > .length` raises** by default.
- **`.sample($n)` with negative `$n` raises**.
- **`.sample($n, allow_duplicates: true)` may produce duplicates** and permits `$n > .length`.
- **`.sample($n, allow_duplicates: true)` with `$n == 0`** returns `[]`.
- **`.sample` draws from `%('core:random')`** — swapping the RNG source changes the draw deterministically.

### `.each`

- **`.each` calls the block once per element** — `[1, 2, 3].each do ($x) $sum += $x end` iterates 3 times.
- **`.each` on empty returns `null`** — no iterations, no last-expression value.
- **`.each` returns the block's last-expression value from the last iteration** by default.
- **`.each` returns `$value` when `$loop.return $value` fires inside the block**.
- **`as $loop` binding provides `$loop.index`** — 0-based iteration index available inside the block.
- **`as $loop` binding provides `$loop.count`** — total number of elements.
- **`$loop.break` inside `.each`** stops iteration and returns null (or the value passed if any).
- **`$loop.next` inside `.each`** skips to the next element.

### `.map`

- **`.map` returns a new array of block return values** — `[1, 2, 3].map do ($x) $x * 2 end` returns `[2, 4, 6]`.
- **`.map` does not mutate the receiver** — original array unchanged.
- **`.map` on empty returns `[]`**.
- **`.map!` replaces each element in place** and returns the receiver.
- **`.map!` returns identity** — the receiver.

### `.keep`

- **`.keep` (no block) returns truthy items** — `[1, null, 0, false, 'a'].keep` returns `[1, 0, 'a']` (only `null` and `false` are falsy).
- **`.keep` (block) returns items where block returned truthy** — `[1, 2, 3, 4].keep do ($n) $n.even? end` returns `[2, 4]`.
- **`.keep` does not mutate the receiver**.
- **`.keep!` mutates the receiver in place** and returns identity.
- **`.keep` on empty returns `[]`**.
- **`.keep` preserves order**.

### `.reject`

- **`.reject` (no block) returns falsy items** — `[1, null, 0, false, 'a'].reject` returns `[null, false]`.
- **`.reject` (block) returns items where block returned falsy** — `[1, 2, 3, 4, 5].reject do ($n) $n.even? end` returns `[1, 3, 5]`.
- **`.reject` does not mutate the receiver**.
- **`.reject!` mutates in place** and returns identity.
- **`.reject` preserves order**.

### `.unique`

- **`.unique` removes duplicates, preserves first-occurrence order** — `[1, 2, 1, 3, 2].unique` returns `[1, 2, 3]`.
- **`.unique` uses `==` for equality** — `[[1, 2], [1, 2]].unique` returns `[[1, 2]]` (structural equality).
- **`.unique` on empty returns `[]`**.
- **`.unique` on all-distinct returns a copy in same order**.
- **`.unique!` mutates in place** and returns identity.

### `.compact`

- **`.compact` removes only `null`** — `[1, null, 0, false, '', [], {}].compact` returns `[1, 0, false, '', [], {}]`.
- **`.compact` preserves order**.
- **`.compact` on all-null returns `[]`**.
- **`.compact` on no-nulls returns a copy**.
- **`.compact!` mutates in place** and returns identity.

### `.shuffle`

- **`.shuffle` returns a new array with the same elements** — same multiset.
- **`.shuffle` does not mutate the receiver**.
- **`.shuffle` draws from `%('core:random')`** — a fixed seed produces a deterministic permutation.
- **`.shuffle` on empty returns `[]`**.
- **`.shuffle` on a single-element array returns `[x]`**.
- **`.shuffle!` mutates in place** and returns identity.

### `.import`

- **`.import` returns a new array with one-level unwrapping** — `[1, 2].import([3, 4])` returns `[1, 2, 3, 4]`.
- **`.import` with a scalar appends as a single element** — `[1, 2].import('foo')` returns `[1, 2, 'foo']`.
- **`.import` unwraps only one level** — `[1].import([[2, 3]])` returns `[1, [2, 3]]`.
- **`.import` does not mutate the receiver**.
- **`.import` accepts null** — `[1].import(null)` returns `[1, null]`.
- **`.import` accepts an empty array** — `[1].import([])` returns `[1]`.
- **`.import!` mutates in place** and returns identity.

### `.push` vs `.import`

- **`.push([1, 2])` never unwraps** — `[].push([1, 2])` returns `[[1, 2]]`.
- **`.import([1, 2])` unwraps** — `[].import([1, 2])` returns `[1, 2]`.
- **Both agree on scalars** — `.push('x')` and `.import('x')` both append `'x'` as one element.

### `+` and `+=`

- **`$a + $b` desugars to `$a.import($b)`** — `[1, 2] + [3, 4]` returns `[1, 2, 3, 4]`.
- **`$a + $b` does not mutate `$a`**.
- **`$a += $b` rebinds `$a`, does not mutate** — after `$a = [1, 2]; $b = $a; $a += [3, 4]`, `$b` is still `[1, 2]`.
- **`$a.import!($b)` mutates through shared references** — after `$a = [1, 2]; $b = $a; $a.import!([3, 4])`, `$b` is `[1, 2, 3, 4]`.

### `.flatten`

- **`.flatten` unwraps one level by default** — `[1, [2, [3, 4]], 5].flatten` returns `[1, 2, [3, 4], 5]`.
- **`.flatten(depth: 0)` is a copy** — no unwrapping.
- **`.flatten(depth: 2)` unwraps two levels** — `[1, [2, [3, 4]], 5].flatten(depth: 2)` returns `[1, 2, 3, 4, 5]`.
- **`.flatten(depth: :all)` recursively unwraps to the bottom** — `[1, [2, [3, [4]]]].flatten(depth: :all)` returns `[1, 2, 3, 4]`.
- **`.flatten` does not touch non-array elements** — hashes stay hashes.
- **`.flatten` on empty returns `[]`**.
- **`.flatten!` mutates in place** and returns identity.

### `.rotate`

- **`.rotate($n)` rotates left by `$n`** — `[1, 2, 3, 4].rotate(1)` returns `[2, 3, 4, 1]`.
- **`.rotate(0)` returns a copy in same order**.
- **`.rotate` with negative `$n` rotates right** — `[1, 2, 3, 4].rotate(-1)` returns `[4, 1, 2, 3]`.
- **`.rotate($n)` where `$n > .length` wraps** — `[1, 2, 3].rotate(4)` returns `[2, 3, 1]`.
- **`.rotate` does not mutate the receiver**.
- **`.rotate` on empty returns `[]`**.
- **`.rotate!` mutates in place** and returns identity.

### `.reverse`

- **`.reverse` returns elements in reverse order** — `[1, 2, 3].reverse` returns `[3, 2, 1]`.
- **`.reverse` does not mutate the receiver**.
- **`.reverse` on empty returns `[]`**.
- **`.reverse` on single element returns `[x]`**.
- **`.reverse!` mutates in place** and returns identity.

### `.insert`

- **`.insert($index, $item)` inserts at position `$index`** — `[1, 2, 4].insert(2, 3)` returns `[1, 2, 3, 4]`.
- **`.insert(0, $item)` prepends** — same as `.unshift`.
- **`.insert(.length, $item)` appends** — same as `.push` for that position.
- **`.insert` returns the receiver (identity)**.
- **`.insert` with out-of-range `$index` raises** — `[1, 2].insert(5, 'x')` raises.
- **`.insert` with negative `$index` raises** (unless negative indexing is explicitly supported — spec says integer in `[0, .length]`).

### `.remove`

- **`.remove($index)` removes and returns the element at `$index`** — `[1, 2, 3].remove(1)` returns `2`; array becomes `[1, 3]`.
- **`.remove` shifts later elements left**.
- **`.remove` with out-of-range `$index` raises**.

### `.clear`

- **`.clear` empties the array** — after `[1, 2, 3].clear`, `.length` is 0.
- **`.clear` returns the receiver (identity)**.
- **`.clear` on already-empty is a no-op**.
- **`.clear` visible through shared references** — after `$a = [1, 2]; $b = $a; $a.clear`, `$b` is `[]`.

### `.cycle`

- **`.cycle` returns the first element and rotates left by one in place** — for `$c = ['red', 'green', 'blue']`, `$c.cycle` returns `'red'` and `$c` becomes `['green', 'blue', 'red']`.
- **Repeated `.cycle` calls round-robin the elements**.
- **`.cycle` on empty raises**.
- **`.cycle` mutates through shared references**.

### `.dig`

- **`.dig` traverses nested keys** — `[[1, 2], [3, 4]].dig(1, 0)` returns `3`.
- **`.dig` returns null at first missing key** — `[[1]].dig(0, 5)` returns `null`, no raise.
- **`.dig` returns null on missing hash key** — `[{a: 1}].dig(0, 'b')` returns `null`.
- **`.dig` never raises on missing keys** — even out-of-range indices return null.
- **`.dig` with no arguments** returns the array itself (or raises — clarify per spec).
- **`.dig` short-circuits on intermediate null** — `[null].dig(0, 'x')` returns `null`.

### `.join`

- **`.join` with separator** — `[1, 2, 3].join('-')` returns `'1-2-3'`.
- **`.join` with no argument uses empty separator** — `[1, 2, 3].join` returns `'123'`.
- **`.join` calls `.to_string` on each element** — mixed-type arrays stringify each entry.
- **`.join` on empty returns `''`**.
- **`.join` on single element returns that element's string form**.

### `.to_hash`

- **`.to_hash` converts pairs** — `[['a', 1], ['b', 2]].to_hash` returns `{a: 1, b: 2}`.
- **`.to_hash` on empty returns `{}`**.
- **`.to_hash` raises on non-pair element** — `[['a', 1], ['b']].to_hash` raises.
- **`.to_hash` raises on non-array element** — `[['a', 1], 'b'].to_hash` raises.
- **Later pairs overwrite earlier keys** — `[['a', 1], ['a', 2]].to_hash` returns `{a: 2}`.

### `.length`

- **`.length` on empty is `0`**.
- **`.length` on n-element array is `n`**.
- **`.length` returns a `Number`**.

### `.empty?` / `.∅?`

- **`.empty?` on `[]` is `true`**.
- **`.empty?` on `[null]` is `false`** — one element counts.
- **`.∅?` is identical to `.empty?`** — same value on same receivers.

### `.any?` / `.∃?`

- **`.any?` on `[]` is `false`**.
- **`.any?` on `[1]` is `true`**.
- **`.any?` on `[null]` is `true`** — presence, not truthiness.
- **`.∃?` is identical to `.any?`**.

### `.first` / `.last`

- **`.first` returns element at index 0** — `['a', 'b'].first` returns `'a'`.
- **`.last` returns element at index -0** — `['a', 'b'].last` returns `'b'`.
- **`.first` on empty raises**.
- **`.last` on empty raises**.
- **`.first` on single element** returns that element; same as `.last`.

### `.includes?` / `.excludes?`

- **`.includes?` finds by `==`** — `[1, 2, 3].includes?(2)` is `true`.
- **`.includes?` finds nested equality** — `[[1, 2]].includes?([1, 2])` is `true`.
- **`.includes?` on empty is `false`**.
- **`.includes?(null)` finds null presence** — `[null].includes?(null)` is `true`.
- **`.excludes?` is `!.includes?`** — `[1, 2].excludes?(3)` is `true`; `[1, 2].excludes?(1)` is `false`.

### Aggregation

- **`.sum` sums all elements** — `[1, 2, 3].sum` returns `6`.
- **`.sum` on empty raises**.
- **`.sum` on non-numeric element raises** — `[1, 'a'].sum` raises.
- **`.sum` accepts mixed number subclasses** — `[0xFF, 1].sum` returns 256 with the leftmost subclass.
- **`.product` multiplies all elements** — `[2, 3, 4].product` returns `24`.
- **`.product` on empty raises**.
- **`.product` on non-numeric raises**.
- **`.min` returns smallest** — `[3, 1, 2].min` returns `1`.
- **`.max` returns largest** — `[3, 1, 2].max` returns `3`.
- **`.min` on empty raises**.
- **`.max` on empty raises**.
- **`.min_by` uses block-returned key** — `['aa', 'b', 'ccc'].min_by do ($s) $s.length end` returns `'b'`.
- **`.max_by` uses block-returned key** — same array, `.max_by`, returns `'ccc'`.
- **`.min_by` / `.max_by` on empty raise**.

### Set operations — combinations

- **`.union` combines, removes duplicates, preserves order** — `[1, 2].union([2, 3])` returns `[1, 2, 3]`.
- **`.union` is symbolically `∪`** — `[1, 2] ∪ [2, 3]` returns the same value.
- **`.union` with empty right** — `[1, 2].union([])` returns `[1, 2]`.
- **`.union` on both empty returns `[]`**.
- **`.intersection` returns shared elements in receiver's order** — `[1, 2, 3].intersection([3, 2, 4])` returns `[2, 3]`.
- **`.intersection` is symbolically `∩`**.
- **`.intersection` with disjoint arrays returns `[]`**.
- **`.difference` returns receiver minus right** — `[1, 2, 3].difference([2])` returns `[1, 3]`.
- **`.difference` preserves receiver's order**.
- **`.difference` with empty right returns a copy of receiver**.
- **`.difference` with equal right returns `[]`**.
- **`.symmetric_difference` returns elements in exactly one** — `[1, 2, 3].symmetric_difference([2, 3, 4])` returns `[1, 4]`.
- **`.symmetric_difference` is symbolically `△`**.
- **Set combinations do not mutate the receiver**.
- **Set operations dedupe via `==`** — `[[1], [1]].union([[1]])` returns `[[1]]`.
- **Set operations use recursive `==` for nested structures**.

### Set operations — predicates

- **`.proper_subset_of?` true when strictly smaller subset** — `[1, 2].proper_subset_of?([1, 2, 3])` is `true`.
- **`.proper_subset_of?` false when equal** — `[1, 2].proper_subset_of?([1, 2])` is `false`.
- **`.proper_subset_of?` is symbolically `⊂`**.
- **`.subset_of?` true when equal** — `[1, 2].subset_of?([1, 2])` is `true`.
- **`.subset_of?` true when strictly smaller** — `[1].subset_of?([1, 2])` is `true`.
- **`.subset_of?` false when receiver has an element not in the right** — `[1, 4].subset_of?([1, 2, 3])` is `false`.
- **`.subset_of?` is symbolically `⊆`**.
- **`.disjoint?` true when no shared elements** — `[1, 2].disjoint?([3, 4])` is `true`.
- **`.disjoint?` false when any shared** — `[1, 2].disjoint?([2, 3])` is `false`.
- **Empty is subset of anything** — `[].subset_of?([1, 2])` is `true`; `[].proper_subset_of?([1, 2])` is `true`; `[].disjoint?([1, 2])` is `true`.
- **Anything is disjoint from empty** — `[1, 2].disjoint?([])` is `true`.

### Excluded methods

- **`.zip`, `.reduce`, `.take`, `.each_with_index`, `.frozen?`, `.size`, `.collect`, `.inject`, `.detect` do not exist** — calling any raises with a method-not-found error.

## Related

- [Loops](https://puck.uno/requirements/syntax/loops) — the `.each` block form, `as $loop`, and every other loop construct.
- [Syntax § Variables and assignment](https://puck.uno/requirements/syntax/variables-and-assignment) — assignment to array indices.
