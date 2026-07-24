# Boolean
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_boolean",
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

`false` is one of the two **falsy** values (the other is `null`). Every other value in Caspian — including `0`, `''`, `[]`, `{}`, and any user-defined object — is truthy. Full rules at [syntax § Truthy and falsy](https://puck.uno/documentation/requirements/syntax/truthy-and-falsy).

## Method surface

TBD. Sub-page will list guaranteed methods (logical operators — `and`, `or`, `not` — comparison, conversion).

## Testing

- **`true` literal materializes to a boolean instance** — `true.object.isa?(Boolean)` is `true`.
- **`false` literal materializes to a boolean instance** — `false.object.isa?(Boolean)` is `true`.
- **`true` is the same shared instance every time** — the object identity of `true` in one expression equals the object identity of `true` in a separate expression; there is only one `true` object in the runtime.
- **`false` is the same shared instance every time** — same identity check as `true`, applied to `false`.
- **`true` and `false` are distinct instances** — `true` and `false` are not identity-equal and not `==`.
- **`true.object.truthy?` returns `true`** — the truthy bit on the `true` instance is `true`.
- **`false.object.truthy?` returns `false`** — the truthy bit on the `false` instance is `false`.
- **`if true` branches into the then-body** — a condition of literal `true` runs the consequent.
- **`if false` branches into the else-body** — a condition of literal `false` skips the consequent and runs any `else`.
- **`0` is truthy** — `if 0 then :yes else :no end` evaluates to `:yes`; only `false` and `null` are falsy.
- **empty string is truthy** — `if '' then :yes else :no end` evaluates to `:yes`.
- **empty array is truthy** — `if [] then :yes else :no end` evaluates to `:yes`.
- **empty hash is truthy** — `if {} then :yes else :no end` evaluates to `:yes`.
- **`null` is falsy** — `if null then :yes else :no end` evaluates to `:no`.
- **`true == true`** — boolean equality holds for equal literals.
- **`false == false`** — same for false.
- **`true != false`** — booleans of different truth values are not equal.
- **`true` is not `==` to `1` or any other truthy non-boolean** — booleans are their own class, not a coercion of any number or string.
- **`false` is not `==` to `null`** — both are falsy but they are distinct values; the distinction survives equality.
- **`and` short-circuits on `false`** — `false and raise('nope')` returns `false` without raising.
- **`or` short-circuits on `true`** — `true or raise('nope')` returns `true` without raising.
- **`not true` is `false`** — logical negation flips the literal.
- **`not false` is `true`** — same, other direction.
- **`not null` is `true`** — negating a falsy non-boolean produces `true`.
- **`not 0` is `false`** — negating a truthy value produces `false`.
- **`true.object.isa?(Object)` is `true`** — every boolean is ultimately an Object.

## Related

- [Syntax § Truthy and falsy](https://puck.uno/documentation/requirements/syntax/truthy-and-falsy) — how booleans compose with Caspian's truthy/falsy rule.
- [Syntax § Operators](https://puck.uno/documentation/requirements/syntax/operators) — the logical operators that dispatch to boolean methods.
