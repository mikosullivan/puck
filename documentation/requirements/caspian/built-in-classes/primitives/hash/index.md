# Hash
<!--index: 5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_hash",
	"role": "spec for Caspian's built-in hash class — ordered key-value map. Covers the literal form, key/value semantics (string keys, arbitrary values), insertion-ordered iteration, and the guaranteed method surface (fetch, set, delete, keys, values, each, length, containment tests).",
	"status": "stub — literal form and ordering-preserved rule noted; method surface TBD",
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

## Ordering

**Insertion order is preserved.** Iterating a hash produces keys in the order they were inserted, not sorted or hashed. This matches the Puck object convention (see [ecoverse § Object structure](https://puck.uno/documentation/ecoverse) if you need the wire-level story) — order is data, not an implementation detail.

## Method surface

TBD. Sub-page will list guaranteed methods (`[key]` fetch, `[key] = value` set, `.delete`, `.keys`, `.values`, `.each`, `.length`, containment tests).

## Testing

- **Empty hash literal `{}` materializes to a Hash instance** — `{}.object.isa?(Hash)` is `true`.
- **Populated hash literal materializes to a Hash instance** — `{a: 1}.object.isa?(Hash)` is `true`.
- **Bare-identifier keys become string keys** — `{name: 'alice'}` is equal to `{'name': 'alice'}`.
- **Explicit string keys are preserved** — `{'name': 'alice'}` and `{name: 'alice'}` are indistinguishable at the value level.
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

## Related

- [Loops](https://puck.uno/documentation/requirements/caspian/syntax/loops) — the `.each` block form, `as $loop`, and every other loop construct.
- [Syntax § Variables and assignment](https://puck.uno/documentation/requirements/caspian/syntax/variables-and-assignment) — assignment to hash entries.
