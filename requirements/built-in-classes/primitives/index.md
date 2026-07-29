# Primitives
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_classes_primitives",
	"role": "cover page for the primitive classes — the six classes every JSON document can contain (string, number, boolean, null, array, hash). Each has its own sub-page owning its literal forms, method surface, and materialization rules. The primitive-buckets sub-page owns the shared bucket / truthiness / no-interning model that unifies all six.",
	"status": "draft — cover page linking to the six per-primitive sub-pages plus primitive-buckets; string, number, and array are substantially spec'd; boolean, null, and hash still have TBD method-surface sections",
	"audience": "developers writing Caspian; engine implementers building the primitive runtime; class authors comparing user-defined classes to the primitive baseline"
}}
~~~

The **primitives** are the classes JSON documents are made of — the six types every JSON literal can produce. In Caspian, the same six classes cover both source literals and JSON round-tripping: a `42` in Caspian source is a Number the same way a `42` in JSON is a Number, `[1, 2, 3]` is an Array in either format, `null` is a Null, and so on. Every JSON document a program parses turns into a tree whose nodes are instances of exactly these six classes; every value a program serializes to JSON is already one.

## The six primitive classes

Each carries its own literal spec, method surface, and materialization rules on its own sub-page:

- [string](https://puck.uno/requirements/built-in-classes/primitives/string/) — sequence of Unicode characters.
- [number](https://puck.uno/requirements/built-in-classes/primitives/number/) — integer or fractional value; one class for both.
- [boolean](https://puck.uno/requirements/built-in-classes/primitives/boolean) — two-instance truth class (`true`, `false`).
- [null](https://puck.uno/requirements/built-in-classes/primitives/null) — absence of a value; optional per-instance flavor.
- [array](https://puck.uno/requirements/built-in-classes/primitives/array/) — ordered sequence of arbitrary values.
- [hash](https://puck.uno/requirements/built-in-classes/primitives/hash/) — ordered key-value map.

## The shared model

All six primitives share the same object shape — a bucket, a truthy bit, and per-instance identity (no interning of literals). That shape is what lets a Number carry downloaded methods, a Null carry a flavor, a String carry a contributors list, and every other primitive carry its own bucket state without special-casing the "singleton-looking" values:

- [primitive-buckets](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets) — how the bucket, truthiness, no-interning, and immutability rules apply uniformly across all six.

## Testing

- **Engine guarantees six primitive classes at startup** — String, Number, Boolean, Null, Array, and Hash are each resolvable by name in a fresh runtime with no user code loaded and no `%fetch` calls made.
- **String literal materializes to a String instance** — `'hello'.object.isa?(String)` is `true`.
- **Number literal materializes to a Number instance** — `42.object.isa?(Number)` is `true`.
- **Boolean literals materialize to Boolean instances** — `true.object.isa?(Boolean)` and `false.object.isa?(Boolean)` are both `true`.
- **Null literal materializes to a Null instance** — `null.object.isa?(Null)` is `true`.
- **Array literal materializes to an Array instance** — `[1, 2, 3].object.isa?(Array)` is `true`.
- **Hash literal materializes to a Hash instance** — `{a: 1}.object.isa?(Hash)` is `true`.
- **Every primitive is an Object** — each of the six primitive instances above reports `.object.isa?(Object)` as `true`.
- **JSON parse produces only primitive instances at leaves** — parsing a JSON document whose leaves are strings, numbers, booleans, and nulls yields a tree where every non-container node is an instance of one of the six primitive classes.
- **JSON round-trip preserves class** — serializing a primitive to JSON and parsing the result produces an instance of the same class (String round-trips to String, etc.).
- **No primitive requires `%fetch`** — code that uses the six literal forms runs in an engine with the network completely disabled; no `%fetch` calls happen.

## Related

- [built-in-classes](https://puck.uno/requirements/built-in-classes/) — the parent hub; the primitives are one of the two groupings alongside the object namespace.
- [bucket-access](https://puck.uno/requirements/built-in-classes/bucket-access) — the sigils and shorthands (`@field`, `%bucket`, `$obj.@field`) programs use to read and write bucket entries on any object, primitive or not.
- [syntax/literals](https://puck.uno/requirements/syntax/) — the source-level literal forms that materialize into primitive instances.
