~~~vibecode
{"doc": "sprint-index", "sprint": "mask-classes",
	"role": "Sprint on mask classes: a mask class looks like a Caspian class from the surface, but it's actually a Lua class. Sprint's work: figure out how masks are stored in the CVM database.",
	"status": "active — starting from the pre-run database state and working forward"}
~~~

# mask-classes

Sprint on mask classes. A mask class **looks** like a Caspian class from the surface — same syntax, same shape — but it's actually implemented as a Lua class. That means we need a way to store masks in the CVM database that mirrors the surface concept without paying full class-in-Caspian machinery for it.

**Storage design isn't decided yet.** The sprint works forward from the pre-run database state, exploring what a mask actually looks like in the graph as the first mask-touching command runs.

**Working example.** The mask class we're modeling as we go is `puck.uno/color` — "color" for short in conversation. Everything the sprint captures lands as concrete operations on that specific class.

## Pages so far

- [masks](./masks) — draft spec text for the mask-class concept, single-section shape for eventual promotion to `requirements/`
- [storage](./storage) — how masks live in the CVM database; starts from the state before the first command runs and grows as the sprint layers in writes

## Status

**Active.** Storage design open. Pre-run state captured; next steps will layer in the first mask-related writes.
