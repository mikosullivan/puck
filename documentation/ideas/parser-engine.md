# Common parser engine

~~~vibecode
{"vibecode": {
	"doc": "parser-engine",
	"role": "forward-direction note: v1 keeps parsers hand-rolled and small; if the count grows to ~4-5 distinct parsers, revisit options like bundling LPeg or building a shared engine",
	"key_concepts": ["hand_rolled_parsers", "lpeg_bundling_option", "common_engine_trigger",
		"schema_driven_alternative"],
	"status": "deferred"
}}
~~~

<a id="context"></a>
## Context

In v1, each parser is hand-rolled:

- JSON parser: ~100 lines, simple.
- CSS selector parser: ~200–400 lines.
- HTML parser (Uma): schema-driven, ~1500 lines, but schemas
  (like html5.json) are easy enough for developers to write.
- Caspian itself: in Lua bootstrap, not part of the standard
  library.

The hand-rolled approach keeps each parser purpose-built and
small. Schemas (the Uma model) cover the "user-defined markup
language" case without requiring grammar authoring.

<a id="when-to-revisit"></a>
## When to revisit

If we find ourselves accumulating hand-rolled parsers — say
we add a few more parsers for new file formats, query
languages, or domain-specific syntaxes — the duplication cost
adds up. At some point a common parser engine pays for itself.

Trigger to reconsider: **4 or 5 distinct hand-rolled parsers
in the framework**, with the prospect of more.

<a id="options-if-we-revisit"></a>
## Options if we revisit

<a id="bundle-lpeg"></a>
### Bundle LPeg

- Roberto Ierusalimschy's PEG engine for Lua. Battle-tested,
  ~80–100 KB compiled, ~15 years of maintenance.
- Pros: don't write a parsing engine ourselves; well-understood
  PEG semantics; fast.
- Cons: native dependency (more binary surface); LPeg is C, so
  grammar errors might surface awkwardly across the Caspian/Lua
  boundary.

<a id="roll-our-own-peg-or-parser-combinator-engine-in-caspian"></a>
### Roll our own PEG (or parser-combinator) engine in Caspian

- ~500–1500 lines of Caspian for a usable engine.
- Pros: stays in our ecosystem; no native dependency; we
  control the semantics (good error messages, debug hooks).
- Cons: a substantial chunk of code to write and maintain.
- Likely the right choice if we revisit — keeps the framework
  self-contained.

<a id="parser-combinators"></a>
### Parser combinators

- Same effective result as PEG with a different API style.
- Composable primitives (literal, alternation, sequence, etc.)
  combined into parsers as data structures.
- Pros: very ergonomic for users defining their own languages;
  easy to compose.
- Cons: parser-combinator engines can be slow for large inputs
  without aggressive optimization.

<a id="constraint-dont-displace-the-schema-model"></a>
## Constraint: don't displace the schema model

Whatever engine lands, **Uma's schema-driven approach stays
the user-facing way to define tag-based markup languages.**
Writing html5.json (or a sibling for another markup) must
remain low-learning-curve. A parser engine is for the
framework's own use, not a substitute for the schema config.

If a future engine could *also* be reachable as a
`%utils.peg.parse(grammar, string)` or similar — for use cases
where a real grammar is appropriate (mini-languages, DSLs,
custom query syntaxes) — that's a bonus. But the schema-as-
config story stays the headline.

<a id="status"></a>
## Status

Not committed. Revisit when we have 4–5 hand-rolled parsers and
can see the curve bending.
