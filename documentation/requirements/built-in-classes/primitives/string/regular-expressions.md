# Regular expressions
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_string_regular_expressions",
	"role": "spec entry point for Caspian's regular-expression surface. Caspian uses LPeg as its pattern engine; this doc names that choice and defers pattern-syntax documentation to LPeg's own documentation rather than restating it here.",
	"status": "stub — engine choice pinned; Caspian's own docs will reference LPeg's docs for pattern syntax rather than duplicating it; pattern-facing method surface on string (`.match`, `.match?`, `.replace`) will be spec'd as it lands",
	"audience": "developers writing Caspian pattern-matching code; engine implementers wiring the pattern surface"
}}
~~~

Caspian's regular-expression surface uses **[LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/)** as its pattern engine. <!-- outbound-link-allowed --> LPeg is a PEG (Parsing Expression Grammar) library, a strict superset of traditional regex — it supports alternation, recursion, named captures, and lookahead — and small enough (~50 KB) to ship in the default install.

## Pattern syntax

Caspian's pattern documentation **relies on LPeg's own documentation** rather than restating the pattern language. When writing patterns, refer to the [LPeg reference](https://www.inf.puc-rio.br/~roberto/lpeg/) <!-- outbound-link-allowed --> for what's available and how each construct behaves. This spec covers the Caspian-side surface — which methods on which classes accept patterns, what the return shapes are, and how patterns integrate with the rest of the language — but does not duplicate LPeg's pattern-syntax reference.

## Testing

### Engine availability

- **LPeg is loadable in the engine** — starting the engine and constructing a trivial pattern does not raise.
- **LPeg version bundled with the engine is the pinned version** — reading the LPeg version at runtime matches the version this spec pins.

### Basic pattern behavior (via LPeg semantics)

- **A pattern that matches its whole input returns a match**.
- **A pattern that does not match returns null** (per the Caspian-side "no match returns null" convention, once the method surface lands).
- **An invalid pattern raises at pattern-construction time**.
- **An empty pattern behavior is spec'd** — either always-matches-at-position-0 or raises; test against the settled rule.
- **Pattern operations work on UTF-8 input** — LPeg is byte-oriented; test that patterns written for byte-level constructs behave as documented, and that Caspian's pattern surface documents which constructs are char-aware vs byte-aware.

### Caspian-side surface (deferred)

- The `.match`, `.match?`, `.replace` (and any other pattern-accepting) methods each get their own Testing entries in `string/index.md` (or a dedicated pattern-surface page) as they land. Coverage should include: match position, capture returns, named captures, no-match null, gsub replacement forms, split by pattern, and integration with the string surface.
