# Kiera.uno HTML validator and tidying service

**Status:** Forward-looking note. Not in v1.

## Purpose

A Kiera.uno-hosted service that validates and tidies HTML
documents. Two related operations:

- **Validate** — given an HTML document, check it against the
  WHATWG HTML spec. Report any structural violations
  (unclosed tags, invalid attribute values, content-model
  breaches, missing required attributes, etc.).
- **Tidy** — given a slightly-broken HTML document, return a
  cleaned-up version that's well-formed and structurally
  valid. The HTML version of "format my code, please."

## Where it fits

- **Uma** (especially the `kiera.uno/uma/html5` subclass) is
  the local first-pass tool — it parses, manipulates, and
  serializes HTML. Uma's schema-driven approach catches many
  issues at construction time.
- **The validator/tidy service** is the heavier-weight
  authority. It runs against a full HTML5 implementation
  (probably gumbo or an equivalent server-side parser) and
  produces detailed reports. Useful for one-off checks on
  large documents, for CI pipelines that gate on validation,
  and for cleaning up ingested HTML from untrusted sources.

## Why a service rather than embedded

- A full HTML5 validator is large (hundreds of K) and
  changes over time as the spec evolves.
- Most apps don't need it on the hot path.
- A network service is the right shape: validate occasionally,
  not in every request.
- Centralizes spec-version tracking — clients automatically
  get the current standard without per-app updates.

## Possible API shape (sketch)

```
$result = %['kiera.uno/html5-validator'].validate($html)
$result.valid?           # boolean
$result.violations       # array of structured violation reports
$result.tidied           # cleaned-up version (optional, configurable)
```

Or as a Sinatra-style HTTP endpoint with a JSON request/response.

## Open

- Hosting and access model — free tier, paid tier, on-premises?
- Spec version selection (validate against HTML5.x specifically?
  the living standard?).
- Tidying preferences (preserve comments? normalize whitespace?
  indent style?).
- Relationship to Bryton — could a `bryton-html-valid` xeme
  type wrap this for "did my page validate?" tests.

## Status

Filed for future. The Uma side ships first; the validator
service follows once Uma's user base needs heavier-weight
validation.
