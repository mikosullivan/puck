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

Full lexer rules live under [syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals).

## Ordering

**Insertion order is preserved.** Iterating a hash produces keys in the order they were inserted, not sorted or hashed. This matches the Puck object convention (see [ecoverse § Object structure](https://puck.uno/documentation/ecoverse) if you need the wire-level story) — order is data, not an implementation detail.

## Method surface

TBD. Sub-page will list guaranteed methods (`[key]` fetch, `[key] = value` set, `.delete`, `.keys`, `.values`, `.each`, `.length`, containment tests).

## Related

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the source-level literal form.
- [Syntax § Blocks and iteration](https://puck.uno/documentation/requirements/caspian/syntax/blocks-and-iteration) — the `.each` block form.
- [Syntax § Variables and assignment](https://puck.uno/documentation/requirements/caspian/syntax/variables-and-assignment) — assignment to hash entries.
