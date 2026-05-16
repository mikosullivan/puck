# Common parser engine

**Status:** Filed as a forward direction. Not in v1.

## Context

In v1, each parser is hand-rolled:

- JSON parser: ~100 lines, simple.
- CSS selector parser: ~200–400 lines.
- HTML parser (Uma): schema-driven, ~1500 lines, but schemas
  (like html5.json) are easy enough for developers to write.
- KScript itself: in Lua bootstrap, not part of the standard
  library.

The hand-rolled approach keeps each parser purpose-built and
small. Schemas (the Uma model) cover the "user-defined markup
language" case without requiring grammar authoring.

## When to revisit

If we find ourselves accumulating hand-rolled parsers — say
we add a few more parsers for new file formats, query
languages, or domain-specific syntaxes — the duplication cost
adds up. At some point a common parser engine pays for itself.

Trigger to reconsider: **4 or 5 distinct hand-rolled parsers
in the framework**, with the prospect of more.

## Options if we revisit

### Bundle LPeg

- Roberto Ierusalimschy's PEG engine for Lua. Battle-tested,
  ~80–100 KB compiled, ~15 years of maintenance.
- Pros: don't write a parsing engine ourselves; well-understood
  PEG semantics; fast.
- Cons: native dependency (more binary surface); LPeg is C, so
  grammar errors might surface awkwardly across the KScript/Lua
  boundary.

### Roll our own PEG (or parser-combinator) engine in KScript

- ~500–1500 lines of KScript for a usable engine.
- Pros: stays in our ecosystem; no native dependency; we
  control the semantics (good error messages, debug hooks).
- Cons: a substantial chunk of code to write and maintain.
- Likely the right choice if we revisit — keeps the framework
  self-contained.

### Parser combinators

- Same effective result as PEG with a different API style.
- Composable primitives (literal, alternation, sequence, etc.)
  combined into parsers as data structures.
- Pros: very ergonomic for users defining their own languages;
  easy to compose.
- Cons: parser-combinator engines can be slow for large inputs
  without aggressive optimization.

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

## Status

Not committed. Revisit when we have 4–5 hand-rolled parsers and
can see the curve bending.
