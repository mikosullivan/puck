# Built-in classes
<!--index: 10-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_classes",
	"role": "cover page for the classes the engine guarantees at startup — the types that literals materialize into (string, number, boolean, null, array, hash) plus function/closure/class themselves. Sub-pages spec each class's surface; this page is the entry point.",
	"status": "stub — cover page in place, per-class sub-pages to follow",
	"audience": "developers writing Caspian; engine implementers building the built-in class surface; tooling authors"
}}
~~~

Some classes are **built in** — the engine guarantees they exist at startup, and literals in Caspian source materialize into instances of them. A `42` in Caspian source is an instance of the number class; `'hi'` is an instance of the string class; `[1, 2, 3]` is an instance of the array class. Programs can rely on these being present without any `%puck` call to download them.

## Scope

The built-in class catalog covers:

- **Primitive classes** — the types every literal form produces: string, number, boolean, null, array, hash.
- **Callable classes** — function, closure, and the class class itself.
- **Guaranteed method surfaces** — the methods each built-in class exposes to Caspian code (arithmetic on number, `.length` and `.each` on array/hash, string comparison and slicing, etc.).
- **Materialization rules** — how a literal in source becomes an instance of the corresponding class at runtime.

## JSON primitives

The six classes every JSON document can contain, each with its own sub-page:

- [string](https://puck.uno/documentation/requirements/caspian/built-in-classes/string) — sequence of Unicode characters.
- [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/) — integer or fractional value; one class for both.
- [boolean](https://puck.uno/documentation/requirements/caspian/built-in-classes/boolean) — two-instance truth class (`true`, `false`).
- [null](https://puck.uno/documentation/requirements/caspian/built-in-classes/null) — absence of a value; optional per-instance flavor.
- [hash](https://puck.uno/documentation/requirements/caspian/built-in-classes/hash) — ordered key-value map.
- [array](https://puck.uno/documentation/requirements/caspian/built-in-classes/array) — ordered sequence of arbitrary values.

Each of the JSON-primitive pages is currently a stub — literal forms noted, method surfaces to follow.

## What's not covered here yet

- **Callable classes** — function, closure, and the class class itself. Sub-pages to come as their runtime surfaces get spec'd.
- **Guaranteed method surfaces** — the concrete method catalog for each built-in class.
- **Materialization rules** — how a literal in source becomes an instance of the corresponding class at runtime.

## What lives elsewhere

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the source-level literal forms that produce these classes.
- [Syntax § Functions and closures](https://puck.uno/documentation/requirements/caspian/syntax/functions-and-closures/) — the syntax for defining callables; the runtime class surface belongs here once written.
- [Syntax § Classes](https://puck.uno/documentation/requirements/caspian/syntax/classes) — the syntax for defining a user class; the class class itself is a built-in.
