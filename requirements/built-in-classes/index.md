# Built-in classes
<!--index: 10-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_classes",
	"role": "cover page for the classes the engine guarantees at startup — the six JSON-primitive types that literals materialize into (catalog owned by primitives/) plus the primitive-buckets model that spec's how they carry buckets and truthiness. Function/closure/method surfaces live at functions/; the meta-class lives at classes/definition/. Sub-pages own each class's surface; this page is the entry point.",
	"status": "draft — all six JSON-primitive sub-pages authored; string, number, and array are substantially spec'd; boolean, null, and hash still have TBD method-surface sections; primitive-buckets and bucket-access utility pages also live here",
	"audience": "developers writing Caspian; engine implementers building the built-in class surface; tooling authors"
}}
~~~

Some classes are **built in** — the engine guarantees they exist at startup, and literals in Caspian source materialize into instances of them. A `42` in Caspian source is an instance of the number class; `'hi'` is an instance of the string class; `[1, 2, 3]` is an instance of the array class. Programs can rely on these being present without any `%import` call to download them.

## Scope

The built-in class catalog covers:

- **Primitive classes** — the types every literal form produces. See [primitives/](https://puck.uno/requirements/built-in-classes/primitives/) for the catalog.
- **Guaranteed method surfaces** — the methods each built-in class exposes to Caspian code (arithmetic on number, `.length` and `.each` on array/hash, string comparison and slicing, etc.).
- **Materialization rules** — how a literal in source becomes an instance of the corresponding class at runtime.

Function, closure, and method classes are also built into the engine, but their surface lives on a separate hub — see [What lives elsewhere](#what-lives-elsewhere) below.

## JSON primitives

The six classes every JSON document can contain — string, number, boolean, null, array, hash — live under [primitives/](https://puck.uno/requirements/built-in-classes/primitives/), which owns the catalog and links out to each per-class sub-page. The [primitive-buckets](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets) sub-page under `primitives/` owns the shared bucket / truthiness / no-interning model that unifies all six.

## What's not covered here yet

- **Guaranteed method surfaces on boolean, null, and hash** — those three sub-pages are still stubs. `string`, `number`, and `array` have substantial method catalogs already; the remaining three fill in as they get spec'd.

## What lives elsewhere

- **Source-level literal forms** — each per-class sub-page under [primitives/](https://puck.uno/requirements/built-in-classes/primitives/) owns its own literal spec.
- [Functions](https://puck.uno/requirements/functions/) — the function surface, including the three function types, call semantics, parameter mechanics, and the method-object surface. The runtime class surface for these lives on that hub, not here.
- [Classes § Definition](https://puck.uno/requirements/classes/definition/) — how user classes are defined. The meta-class (the class of classes) is built into the engine; its runtime surface is spec'd there.

## Testing

- **Engine guarantees each primitive class at startup** — String, Number, Boolean, Null, Array, and Hash are each resolvable in a fresh runtime with no user code loaded and no `%import` calls made.
- **Number literal materializes without `%import`** — evaluating `42` in an engine with the network disabled produces a Number instance and does not attempt any `%import` fetch.
- **String literal materializes without `%import`** — same test with `'hi'`.
- **Boolean literals materialize without `%import`** — same test with `true` and `false`.
- **Null literal materializes without `%import`** — same test with `null`.
- **Array literal materializes without `%import`** — same test with `[1, 2, 3]`.
- **Hash literal materializes without `%import`** — same test with `{a: 1}`.
- **`42.object.isa?(Number)`** is `true`.
- **`'hi'.object.isa?(String)`** is `true`.
- **`true.object.isa?(Boolean)`** is `true`.
- **`false.object.isa?(Boolean)`** is `true`.
- **`null.object.isa?(Null)`** is `true`.
- **`[1, 2, 3].object.isa?(Array)`** is `true`.
- **`{a: 1}.object.isa?(Hash)`** is `true`.
- **Object class is also guaranteed at startup** — `%('puck.uno/object')` returns a class value in a fresh runtime.
- **Every value is an Object** — for each primitive literal above, `.object.isa?(Object)` is `true`.
