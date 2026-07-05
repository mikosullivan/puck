# Null
<!--index: 4-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_null",
	"role": "spec for Caspian's built-in null class — represents the absence of a value. Falsy alongside false. Optional per-instance flavor allows carrying a reason without changing the null-ness (e.g., null with flavor :not_found vs :unauthorized). Method surface is deliberately narrow.",
	"status": "stub — literal form, flavor mechanism, and truthy/falsy rule noted; method surface TBD",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

**Null** represents the absence of a value. Every occurrence of the bare word `null` in Caspian source refers to a null instance.

## Literal form

- **`null`** — a bare-word literal producing a null instance.

## Truthy and falsy

`null` is one of the two **falsy** values (the other is `false`). Full rules at [syntax § Truthy and falsy](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy).

## Null flavors

A null can carry an optional **flavor** — a small tag that names the reason for the null without changing the fact that it IS null. Examples: `null :not_found`, `null :unauthorized`, `null :expired`.

Callers who don't care about the reason treat the value as plain null (falsy, non-value). Callers who DO care can inspect the flavor. Default to plain null; add a flavor only when the caller's logic will actually branch on the reason. Full rules for when to add flavors live in developer-side prose; the runtime support is a per-instance tag on the null.

## Method surface

TBD. Sub-page will list guaranteed methods (flavor accessor, comparison, conversion).

## Related

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the `null` literal form.
- [Syntax § Truthy and falsy](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy) — how null composes with the truthy/falsy rule.
