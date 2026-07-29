# Null
<!--index: 4-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_null",
	"role": "spec for Caspian's built-in null class — represents the absence of a value. Falsy alongside false. Optional per-instance flavor allows carrying a reason without changing the null-ness (e.g., null with flavor :not_found vs :unauthorized). Method surface is deliberately narrow.",
	"status": "stub — literal form, flavor mechanism, and truthy/falsy rule noted; method surface TBD",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

**Null** represents the absence of a value. Every occurrence of the bare word `null` in Caspian source refers to a null instance.

## Literal form

- **`null`** — a bare-word literal producing a null instance.

## Truthy and falsy

`null` is one of the two **falsy** values (the other is `false`). Full rules at [syntax § Truthy and falsy](https://puck.uno/requirements/syntax/truthy-and-falsy).

## Null flavors

A null can carry an optional **flavor** — a value that names the reason for the null without changing the fact that it IS null. The flavor lives at `%bucket['flavor']` on the null instance.

**Any value can be a flavor.** Caspian does not constrain the type. A string (`'not_found'`), the symbol shorthand for one (`:unauthorized` — which is just a string with a compact syntax), a number, a hash carrying structured metadata, another object entirely — all are legal. The engine treats `%bucket['flavor']` as a per-instance tag; interpretation is up to whoever attaches and whoever reads it.

Callers who don't care about the reason treat the value as plain null (falsy, non-value). Callers who DO care inspect the flavor and branch on whatever shape the raising code chose. Default to plain null; add a flavor only when the caller's logic will actually branch on the reason.

**Downloadable subclass for null-flavor protocols.** Systems like HL7 v3 / CDA / FHIR use null flavors extensively with their own vocabulary and semantics. A subclass of Null that provides methods specifically for those protocols — a fixed value set of standard flavor codes, helpers for the HL7 hierarchy walk, protocol-shaped conversion methods, etc. — would not ship with Caspian itself but could be published as a downloadable class (`%fetch`-fetched), whether from `puck.uno` or from a third-party author. That subclass would extend, not replace, the general no-constraint rule — the base Null accepts any flavor value; the HL7-adapted subclass would layer conventions on top for callers who opt into it.

## Method surface

TBD. Sub-page will list guaranteed methods (flavor accessor, comparison, conversion).

## Testing

- **`null` literal materializes to a Null instance** — `null.object.isa?(Null)` is `true`.
- **`null` is falsy** — `if null then :yes else :no end` evaluates to `:no`.
- **`null.object.truthy?` returns `false`** — the truthy bit on a Null instance is `false`.
- **`null == null` is `true`** — two null values compare equal.
- **`null != false`** — null is not equal to false, though both are falsy.
- **`null` and `false` are distinct classes** — `null.object.isa?(Boolean)` is `false`; `false.object.isa?(Null)` is `false`.
- **`null` is distinct from an empty string** — `null == ''` is `false`.
- **`null` is distinct from `0`** — `null == 0` is `false`.
- **`null` is distinct from an empty array** — `null == []` is `false`.
- **`null` is distinct from an empty hash** — `null == {}` is `false`.
- **No interning across literals** — two separate `null` literals in source produce two Null instances that are `==` but each has its own bucket; writing `@flavor` on one does not appear on the other.
- **Bare `null` has no flavor** — `null.%bucket['flavor']` is absent (or reads as null) on a freshly materialized `null` with no flavor set.
- **Flavored null is still a Null instance** — after attaching any flavor value to a null, `.object.isa?(Null)` remains `true`.
- **Flavored null is still falsy** — attaching a flavor does not flip the truthy bit; `.object.truthy?` remains `false`.
- **Flavor accepts a string value** — a null with `%bucket['flavor'] = 'not_found'` round-trips the string on read.
- **Flavor accepts a symbol-form string** — a null with flavor `:unauthorized` reads back as the same string value.
- **Flavor accepts a number** — a null with flavor `404` reads back as `404`.
- **Flavor accepts a hash** — a null with flavor `{code: 404, reason: 'gone'}` reads back as a hash of the same shape.
- **Flavor accepts an arbitrary object** — a null with flavor set to a user-class instance reads back that instance identity.
- **Engine does not constrain flavor type** — assigning any of the above values as a flavor never raises on the assignment.
- **Two nulls with different flavors are still `==`** — flavor is metadata; the null-ness is what equality reports.
- **`null.object.isa?(Object)` is `true`** — Null ultimately extends Object.

## Related

- [Syntax § Truthy and falsy](https://puck.uno/requirements/syntax/truthy-and-falsy) — how null composes with the truthy/falsy rule.
