# Hash
<!--index: 5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_hash",
	"role": "spec for Caspian's built-in hash class — ordered key-value map. Covers the literal form, key/value semantics (string keys, arbitrary values), insertion-ordered iteration, the guaranteed method surface (fetch, set, delete, keys, values, each, length, containment tests), and an opt-in note_deleted feature for recording explicit deletions that layered-lookup consumers like %chain and scope frames build on.",
	"status": "stub — literal form, ordering-preserved rule, and note_deleted opt-in feature spec'd; broader method surface TBD",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

A **hash** is an ordered map from string keys to arbitrary values. Every hash literal in Caspian source materializes into an instance.

## Literal form

~~~caspian
$table = {name: 'alice', age: 30, admin: true}
~~~

- Keys written as bare identifiers become string keys — `{name: ...}` is `{'name': ...}`.
- Keys can also be written as explicit strings — `{'name': 'alice'}`.
- Values can be any value.

**Keys are strings.** Unlike some languages (Ruby symbols, Python where any hashable is a key, JavaScript's ability to use numbers or symbols), Caspian hash keys are always strings.

In hash literal syntax, whatever token appears before the `:` becomes the string key. All three of these produce the same hash:

~~~caspian
{foo: 'bar'}       # bare identifier
{'foo': 'bar'}     # single-quoted string
{"foo": 'bar'}     # double-quoted string
~~~

Numeric-looking tokens work the same way — `{42: 'x'}` produces a hash with the string key `'42'`, identical to `{'42': 'x'}`.

At runtime, `[]` and `[]=` still require a string — `$h[42] = 'x'` and `$h[42]` raise because `42` is a number, not a string. The literal parser's "anything-before-colon-becomes-a-string" rule is a parse-time convenience, not a runtime coercion.

## Ordering

**Insertion order is preserved.** Iterating a hash produces keys in the order they were inserted, not sorted or hashed. This matches the Puck object convention (see [ecoverse § Object structure](https://puck.uno/documentation/ecoverse) if you need the wire-level story) — order is data, not an implementation detail.

## Method surface

TBD. Sub-page will list guaranteed methods (`[key]` fetch, `[key] = value` set, `.delete`, `.keys`, `.values`, `.each`, `.length`, containment tests).

## Noting deleted keys

Some consumers need to distinguish between "the key was never here" and "the key was explicitly deleted." Plain hashes don't carry that distinction — a `.delete` followed by `.has_key?` returns `false`, indistinguishable from a key that was never set. An opt-in feature lets a hash record its deletions.

### Opt-in per hash

Set `.note_deleted = true` to turn on deletion tracking. Off by default — hashes that don't need the feature don't pay the memory cost of a tombstone set.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.note_deleted # true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
~~~

### The key doesn't need to have existed

`.delete` on a note-deleted hash records the key even if it was never present. The tombstone is a statement about visibility, not a record of what used to be there.

~~~caspian
$hsh = {}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
~~~

### `.deleted?` raises on non-note-deleted hashes

If a hash isn't tracking deletions, it can't answer `.deleted?` honestly — returning `false` would be misleading (the key might have been deleted; the hash didn't record it). Raising is properly fail-loud.

~~~caspian
$hsh = {'a': 'b'}
$hsh.delete 'a'
$hsh.deleted? 'a' # raises
~~~

### Toggling off wipes the tombstones

Setting `.note_deleted = false` discards the recorded deletions. Turning it back on starts fresh — no silent preservation.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
$hsh.note_deleted = false
$hsh.note_deleted = true
$hsh.deleted? 'a' # false
~~~

### Re-assigning un-tombstones the key

Setting a key that was previously tombstoned removes it from the tombstone set. `.has_key?` and `.deleted?` can never both be true for the same key.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
$hsh['a'] = 'bar'
$hsh.deleted? 'a' # false
~~~

### Why this exists

Layered lookup patterns — `%chain` frames, scope frames, and similar walk-a-chain-of-hashes designs — need to distinguish "this layer never had the key" from "this layer explicitly deleted it." Without a tombstone marker, deleting a key in an inner layer silently un-shadows whatever was in an outer layer. The consumer (chain runtime, scope runtime, etc.) opts each frame in with `.note_deleted = true` so the walker can stop on an explicit delete instead of falling through.

## Testing

- **Empty hash literal `{}` materializes to a Hash instance** — `{}.object.isa?(Hash)` is `true`.
- **Populated hash literal materializes to a Hash instance** — `{a: 1}.object.isa?(Hash)` is `true`.
- **Bare-identifier keys become string keys** — `{name: 'alice'}` is equal to `{'name': 'alice'}`.
- **Explicit string keys are preserved** — `{'name': 'alice'}` and `{name: 'alice'}` are indistinguishable at the value level.
- **Numeric-looking literal key stringifies** — `{42: 'x'}` equals `{'42': 'x'}`; both keyed by the string `'42'`.
- **Bare, single-quoted, and double-quoted key forms are equivalent** — `{foo: 'bar'}`, `{'foo': 'bar'}`, and `{"foo": 'bar'}` all produce the same hash.
- **Non-string key on `[]=` raises** — `$h[42] = 'x'` raises; the setter accepts only string keys.
- **Non-string key on `[]` raises** — `{'42': 'x'}[42]` raises; the getter accepts only string keys. `{'42': 'x'}['42']` is `'x'`.
- **Values may be any type** — a hash with a mix of number, string, boolean, null, array, hash, and user-object values constructs without error and reads each value back at its original identity.
- **Insertion order is preserved on iteration** — iterating `{c: 3, a: 1, b: 2}` yields keys in the order `c`, `a`, `b`, not alphabetical, not hashed.
- **Insertion order is preserved after overwriting an existing key** — writing a new value at an existing key does not move it to the end; its original position is kept.
- **Empty hash is truthy** — `if {} then :yes else :no end` evaluates to `:yes`.
- **Empty hash has length zero** — `{}.length` is `0`.
- **Populated hash length reflects entries** — `{a: 1, b: 2, c: 3}.length` is `3`.
- **Get by present key returns the value** — `{a: 1}['a']` is `1`.
- **Get by missing key returns `null`** — `{a: 1}['missing']` is `null`; the read does not raise.
- **Set by key adds a new entry** — after `$h = {}; $h['x'] = 5`, `$h['x']` is `5`.
- **Set by key overwrites an existing entry** — after `$h = {a: 1}; $h['a'] = 2`, `$h['a']` is `2`.
- **`.keys` returns keys in insertion order** — `{c: 3, a: 1}.keys` is `['c', 'a']`.
- **`.values` returns values in insertion order** — `{c: 3, a: 1}.values` is `[3, 1]`.
- **`.each` yields key/value pairs in insertion order** — collecting the pairs from `.each` on `{c: 3, a: 1}` produces `[['c', 3], ['a', 1]]`.
- **`.each` on empty hash yields nothing** — the block body never runs for `{}.each`.
- **Nested hashes compose** — `{outer: {inner: 42}}['outer']['inner']` is `42`.
- **Hash equality is recursive** — `{a: {b: 1}} == {a: {b: 1}}` is `true`.
- **Hashes with different insertion orders but same entries compare equal** — `{a: 1, b: 2} == {b: 2, a: 1}` is `true`; equality does not require matching order.
- **Hashes with different entries compare unequal** — `{a: 1} == {a: 2}` is `false`.
- **Unicode string keys are supported** — a hash keyed by a non-ASCII string (e.g. `'café'`) reads and writes at that key without normalization.
- **Empty and populated hashes are distinct instances** — two `{}` literals produce two Hash instances (no interning); mutating one does not affect the other.
- **Hash is truthy after all entries are removed** — a hash whose entries were all deleted still evaluates as truthy; only `false` and `null` are falsy.
- **`.note_deleted` defaults to `false`** — a freshly-constructed hash reads `.note_deleted` as `false`.
- **Enabling `.note_deleted` opts the hash in to deletion tracking** — after `.note_deleted = true`, `.delete` records the key in the tombstone set.
- **`.deleted?` returns `true` for a key deleted after opt-in** — after `$hsh = {'a': 'b'}; $hsh.note_deleted = true; $hsh.delete 'a'`, `$hsh.deleted? 'a'` is `true`.
- **`.deleted?` raises on a hash where `.note_deleted` is `false`** — regardless of whether the key was ever present, calling `.deleted?` on a non-note-deleted hash raises.
- **`.delete` on a note-deleted hash records a key that never existed** — after `$hsh = {}; $hsh.note_deleted = true; $hsh.delete 'a'`, `$hsh.deleted? 'a'` is `true`.
- **Setting `.note_deleted = false` wipes the tombstone set** — after toggling off then back on, a previously-tombstoned key is no longer `.deleted?`.
- **Re-assigning a tombstoned key un-tombstones it** — after `$hsh.delete 'a'; $hsh['a'] = 'bar'`, `$hsh.deleted? 'a'` is `false` and `$hsh.has_key? 'a'` is `true`.

## Related

- [Loops](https://puck.uno/documentation/requirements/syntax/loops) — the `.each` block form, `as $loop`, and every other loop construct.
- [Syntax § Variables and assignment](https://puck.uno/documentation/requirements/syntax/variables-and-assignment) — assignment to hash entries.
