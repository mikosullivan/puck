# Array
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_array",
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

Full lexer rules live under [syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals).

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

The symmetric-indexing pattern relies on **[negative zero](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/#negative-zero)**. `-0` is a distinct signed-zero value that equals `0` in every other context (arithmetic, comparison, hash keys) but reads as "0 from the end" when used as an array index.

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
| `.shuffle` | Returns a new array with the same items in a random order. Draws from `%random`. |
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
| `.sample` | Returns a randomly selected element from the array. Draws from `%random`. Raises on an empty array. |
| `.sample($n)` | Returns a new array of `$n` randomly selected elements without replacement — the same element is never returned twice. Raises if `$n` is negative or larger than `.length`. Pass `allow_duplicates: true` to sample WITH replacement — the same element may then appear more than once and `$n` may exceed `.length`. |
| `.push($item)` | Appends `$item` to the end of the array. Returns the array. Modifies in place. |
| `.pop` | Removes and returns the last element. Returns `null` on an empty array. Modifies in place. |
| `.pop($n)` | Removes the last `$n` elements and returns them as a new array. If `$n` is greater than `.length`, returns all remaining elements. Raises on negative `$n`. Modifies in place. |
| `.unshift($item)` | Inserts `$item` at the beginning of the array. Returns the array. Modifies in place. |
| `.shift` | Removes and returns the first element. Returns `null` on an empty array. Modifies in place. |
| `.shift($n)` | Removes the first `$n` elements and returns them as a new array. If `$n` is greater than `.length`, returns all remaining elements. Raises on negative `$n`. Modifies in place. |
| `.each` | Takes a block called once per element with the element as its argument. Returns the block's last-expression value from the last iteration; if `$loop.return $value` fires inside the block, returns `$value` instead — the "use `.each` as a search" pattern. Returns `null` if the array is empty (no iterations, no last expression). Bind `as $loop` to get access to `$loop.index`, `$loop.count`, `$loop.break`, `$loop.next`, and `$loop.return $value` — see [loops § Loop object methods](https://puck.uno/documentation/requirements/caspian/syntax/loops#loop-object-methods). There is no separate `.each_with_index`; use `as $loop`. |

Note: `.push`, `.pop`, `.unshift`, and `.shift` don't follow the `!` naming convention because they don't have return-new-array counterparts — the names inherently signal mutation, and there's nothing to distinguish from. The `!` suffix marks the mutating side of a **pair**; when only one form exists, the suffix is redundant.

### Query and predicates

| Method | Description |
|---|---|
| `.length` | Number of elements as a [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/). |
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
| `.join($sep)` | Concatenates every element's string form with `$sep` between them. `$sep` is optional — omitted defaults to empty string. Each element is converted to string via its `.to.string` (per the [conversion protocol](https://puck.uno/documentation/ideas/conversion)) or `.to_string` in the interim. |
| `.to_hash` | Converts an array of `[key, value]` pairs into a hash. Raises if any element isn't a two-element array. Migrates to `.to.hash` once the conversion protocol lands. |

## Set operations

Set-theoretic operations on arrays — union, intersection, difference, symmetric difference, and subset relationships. Every combination and predicate operation gets **two names**: a Unicode mathematical symbol and a plain-English method name. Both compile to the same call.

The Unicode symbol forms follow the [no-dot method rule](https://puck.uno/documentation/ideas/no-dot-methods) — the symbol sits between the receiver and the argument, separated by spaces, with no dot: `$a ∪ $b`. Parens around the argument are optional (Caspian's general rule for any method call). The English forms keep the dot: `$a.union($b)`.

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

The [ideas/array-methods](https://puck.uno/documentation/ideas/array-methods) brainstorm has been resolved end-to-end; every candidate is either included above (in the method surface / set operations), listed here as excluded, or has moved into a separate ideas doc ([set-operations-by-key](https://puck.uno/documentation/ideas/set-operations-by-key) for the deferred key-projection kwarg on set operations).

## Related

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the source-level literal form.
- [Loops](https://puck.uno/documentation/requirements/caspian/syntax/loops) — the `.each` block form, `as $loop`, and every other loop construct.
- [Syntax § Variables and assignment](https://puck.uno/documentation/requirements/caspian/syntax/variables-and-assignment) — assignment to array indices.
