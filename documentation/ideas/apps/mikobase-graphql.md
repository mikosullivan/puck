# Mikobase GraphQL support

**Status:** Forward-looking note. Way past v1.

## Idea (Joaquin)

Eventually, expose Mikobase data via GraphQL — clients can issue
GraphQL queries against a Mikobase and receive structured
responses, the same shape they'd get from any GraphQL backend.

## Why (Joachim)

- GraphQL is widely understood; many front-end ecosystems
  expect it.
- The Mikobase schema (classes + records) maps naturally onto
  GraphQL's type system.
- Q0 queries already do the equivalent work; a GraphQL layer
  is mostly translation between query languages.

## Sketch (not committed)

- Each Mikobase class becomes a GraphQL type.
- Class properties become GraphQL fields.
- References between records become GraphQL relationships.
- A Mikobase server endpoint accepts POSTs of GraphQL queries
  and returns the resolved JSON.

## Implementation cost (Cartwright)

Substantial. Beyond bundling a GraphQL parser (Lua has
`graphql-lua` or similar; size ~1500–3000 lines), the
translation layer needs to:

- Map GraphQL queries to Q0 expressions.
- Walk Mikobase's class graph for nested selections.
- Handle pagination, filtering, sorting per the GraphQL
  conventions.
- Implement GraphQL's introspection (schema queries) over
  the Mikobase class catalog.

## Status (Picard)

Not in v1. Not in v2. Filed so the design space doesn't get
forgotten. Revisit when Mikobase has stabilized and there's a
real client demand for GraphQL access.
