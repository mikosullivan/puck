# Boolean
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_boolean",
	"role": "spec for Caspian's built-in boolean class — two-instance class (true and false). Covers the literal forms, the truthy/falsy rule (false is falsy; every value other than false and null is truthy), and the guaranteed method surface (logical operators, comparison).",
	"status": "stub — literal forms and truthy/falsy rule noted; method surface TBD",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

A **boolean** represents a two-valued truth. The class has exactly two instances: `true` and `false`. Every occurrence of the bare word `true` or `false` in Caspian source refers to the same shared instance — there aren't multiple `true` objects floating around.

## Literal forms

- **`true`** — the true instance.
- **`false`** — the false instance.

Both are bare-word literals; no sigil.

## Truthy and falsy

`false` is one of the two **falsy** values (the other is `null`). Every other value in Caspian — including `0`, `''`, `[]`, `{}`, and any user-defined object — is truthy. Full rules at [syntax § Truthy and falsy](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy).

## Method surface

TBD. Sub-page will list guaranteed methods (logical operators — `and`, `or`, `not` — comparison, conversion).

## Related

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the source-level literal forms.
- [Syntax § Truthy and falsy](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy) — how booleans compose with Caspian's truthy/falsy rule.
- [Syntax § Operators](https://puck.uno/documentation/requirements/caspian/syntax/operators) — the logical operators that dispatch to boolean methods.
