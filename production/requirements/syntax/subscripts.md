# Subscripts
<!--index: 12-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_subscripts",
	"role": "spec for Caspian's bracket-subscript syntax — single-key `recv[k]`, multi-key `recv[k1, k2, ...]` walking nested containers, auto-vivification on multi-key assignment, and the trailing `?` null-safe modifier. Applies uniformly to hash and array. The `.[]` and `.[]=` method surface on those classes is what the syntax dispatches to.",
	"status": "single-key + multi-key + auto-vivify + null-safe `?` all settled; edge cases in the testing section",
	"audience": "developers writing Caspian; engine implementers wiring `.[]`/`.[]=`; tooling authors"
}}
~~~

Bracket subscript `recv[key]` is a method call — get calls `.[]`, set calls `.[]=`. The bracket form is syntactic sugar; the receiver's class decides what the method does. Hash and array both implement it; user classes can too.

## Single-key form

The familiar shape:

~~~caspian
$hash['name']              # get
$hash['name'] = 'alice'    # set
$arr[0]                    # get
$arr[0] = 99               # set
~~~

CaspianJ shape:

- Get: `[recv, "[]", {args: [key_expr]}]`
- Set: `[recv, "[]=", {args: [key_expr, value_expr]}]`

## Multi-key form

Multiple comma-separated keys inside one bracket pair walk **nested containers**:

~~~caspian
$hash['x', 'y', 'z']       # equivalent to $hash['x']['y']['z']
$hash['x', 2, 'z']         # $hash['x'][2]['z'] — position 2 is an array
$hash['x', 2, 'z'] = 'foo' # assignment walks the same path
~~~

The key type at each position tells the runtime what kind of container to expect there — a string key means a hash at that depth, an integer key means an array. The runtime walks the path key-by-key.

CaspianJ shape (same for any arity — the runtime dispatches on the args count):

- Get: `[recv, "[]", {args: [k1, k2, ..., kN]}]`
- Set: `[recv, "[]=", {args: [k1, k2, ..., kN, value]}]`

Empty subscript `recv[]` is a parse error; there's no meaningful semantics for zero keys.

## Auto-vivification on assignment

An assignment through a multi-key subscript **creates any missing containers along the path**. The type of each created container is picked by the NEXT key: string next → new hash, integer next → new array.

~~~caspian
$hash = {}
$hash['x', 'y', 'z'] = 'foo'

# $hash is now:
# {
#     'x': {
#         'y': {
#             'z': 'foo'
#         }
#     }
# }
~~~

If any of the keys are integers, the container at that depth is an array:

~~~caspian
$hash = {}
$hash['x', 2, 'z'] = 'foo'

# $hash is now:
# {
#     'x': [null, null, {
#         'z': 'foo'
#     }]
# }
~~~

Positions in a newly-created array before the assigned index are filled with `null`. Auto-vivification only happens on assignment through the subscript operator — a plain read on a missing path returns `null` and creates nothing.

## Null-safe form: trailing `?`

A trailing `?` on the closing bracket switches the subscript to **null-safe** mode. The runtime walks the path and returns `null` at the first missing step, instead of raising or auto-vivifying:

~~~caspian
$hash = {a: {b: 1}}
$hash['a', 'b']?           # 1 — path exists
$hash['a', 'z']?           # null — 'z' is missing
$hash['x', 'y', 'z']?      # null — 'x' is missing, walk halts

$hash['a', 'b']? = 42      # sets — path already exists
$hash['x', 'y', 'z']? = 42 # no-op — 'x' is missing, no auto-vivify
~~~

For reads, `?` and non-`?` differ only when the path is missing:

- Without `?`: reading a missing key at the FINAL step returns `null` (per hash / array semantics). Reading through a missing intermediate raises (there's nothing to index into).
- With `?`: any missing step in the path returns `null`; no raise.

For writes, `?` and non-`?` differ in vivification behavior:

- Without `?`: assignment auto-vivifies missing containers along the path.
- With `?`: assignment SKIPS silently if the path doesn't exist. The container is not modified.

The `?` applies to the whole subscript, regardless of arity — single-key or multi-key.

CaspianJ shape (distinct method names carry the null-safe intent through to the runtime):

- Get: `[recv, "[]?", {args: [k1, ..., kN]}]`
- Set: `[recv, "[]?=", {args: [k1, ..., kN, value]}]`

## Testing

### Single-key

- **Single-key get on a present key returns the value** — `{a: 1}['a']` is `1`.
- **Single-key get on a missing key returns null (hash)** — `{}['missing']` is `null`.
- **Single-key set adds a new entry** — `$h = {}; $h['x'] = 5; $h['x']` is `5`.
- **Single-key set on an array replaces at that index** — `$a = [0, 0, 0]; $a[0] = 99; $a[0]` is `99`.

### Multi-key walks

- **All-string multi-key walks nested hashes** — `{a: {b: {c: 1}}}['a', 'b', 'c']` is `1`.
- **Integer key steps into an array** — `{a: [10, 20, 30]}['a', 1]` is `20`.
- **Mixed string / integer keys walk the corresponding container type at each depth** — `{a: [null, {b: 1}]}['a', 1, 'b']` is `1`.
- **Empty subscript `$recv[]` is a parse error** — no runtime semantics.

### Auto-vivification

- **Multi-key set on empty hash creates the nested path** — `$h = {}; $h['x', 'y', 'z'] = 'foo'; $h` equals `{x: {y: {z: 'foo'}}}`.
- **Integer key in the path materializes an array** — `$h = {}; $h['x', 2, 'z'] = 'foo'; $h` equals `{x: [null, null, {z: 'foo'}]}`.
- **Positions before the assigned integer index fill with null** — `$h = {}; $h['x', 3] = 'foo'; $h['x']` equals `[null, null, null, 'foo']`.
- **Existing partial path is preserved** — `$h = {x: {y: {}}}; $h['x', 'y', 'z'] = 'foo'; $h['x']['y']['z']` is `'foo'` and `$h['x']['y']` is the same hash object (not replaced).
- **Reading a missing multi-key path does NOT vivify** — after `$h = {}; $h['x', 'y', 'z']`, `$h` is still `{}` (the empty hash).
- **Type conflict on the path raises** — writing `$h['x'] = 5; $h['x', 'y'] = 1` raises: `$h['x']` is a scalar, not a container.

### Null-safe `?`

- **`?` get returns the value when path exists** — `{a: {b: 1}}['a', 'b']?` is `1`.
- **`?` get returns null when a final key is missing** — `{a: {b: 1}}['a', 'z']?` is `null`.
- **`?` get returns null when an intermediate key is missing** — `{}['x', 'y', 'z']?` is `null` (no raise).
- **`?` get without `?` raises on missing intermediate** — `{}['x', 'y', 'z']` raises (indexing into `null`).
- **`?` set no-ops when path is missing** — `$h = {}; $h['x', 'y']? = 42; $h` is still `{}`.
- **`?` set writes when path exists** — `$h = {x: {}}; $h['x', 'y']? = 42; $h['x']['y']` is `42`.
- **`?` on single-key get returns null on missing** — `$h = {}; $h['missing']?` is `null` (equivalent to plain get on a hash, but formally the null-safe path).
- **`?` on single-key set no-ops when receiver is null** — a null receiver plus `?` set does nothing rather than raising.

## Related

- [Hash](https://puck.uno/requirements/built-in-classes/primitives/hash/) — the class whose `.[]` and `.[]=` implementations back hash subscripts.
- [Array](https://puck.uno/requirements/built-in-classes/primitives/array/) — same for array.
- [Variables and assignment](https://puck.uno/requirements/syntax/variables-and-assignment) — how subscript-target assignment fits with the general `=` operator.
- [Pipes](https://puck.uno/requirements/syntax/pipes) — `|&` is the pipe-family analog of the null-safe idea (sticky null-propagation through a chain).
