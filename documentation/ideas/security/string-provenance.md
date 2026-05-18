# Idea: String Provenance

Not implemented. Probably too expensive and complicated for the current
implementation, but worth recording so future decisions can build on it. A reasonable
direction is for this to eventually be an **opt-in feature for a higher level of
security**, not the default behavior of the runtime.

## The Idea

Every string carries its **complete construction history** — not just "this string
exists and is tainted," but the full record of every operation and every original
source that went into building it. You wouldn't just know what a string is; you
would know every step that produced it and where those original strings came from.

The mechanism is two kinds of string:

- **Base strings** — original strings that physically exist somewhere. They are the
  only strings actually stored in memory (or on disk, if cached out). Every base
  string has a source (a file location, a request field, an eval origin, a
  function's output, etc.).
- **Query strings** — what the developer manipulates. A query string is not a
  string at all in the storage sense; it is a description of a query against one or
  more base strings or other query strings. Operations on query strings produce new
  query strings, not new content.

The developer does not interact with base strings directly. From the developer's
point of view, base strings and query strings have the same methods and behave the
same way. The distinction is internal.

```
$string = "Falstaff"    # creates a base string; $string is a query that returns it

$foo = $string[0, 2]    # returns a query string that asks for the first three
                          # characters of $string's base

$bar = $foo.upper_case  # returns a query that asks $foo for its result, then
                          # uppercases it. $foo in turn queries $string.
```

When `$bar`'s value is actually needed — printed, compared, passed to a sink — the
engine materializes the query: walks back through the query chain to the base
string(s), runs the operations, and produces the result. Until then, no characters
have been computed.

## Why This Would Be Powerful

The coarse model of one role-tag per value (see [roles.md](../../charlie/roles.md)) collapses
construction history down to a single owning role per string. That's enough for
"should this sink refuse to act on this string," but it loses information that
could be useful in several places:

- **Forensics.** When a security exception fires because an untrusted string reached
  a dangerous sink, the developer can trace exactly which character positions came
  from where. "The query terminator at column 47 came from `$request['filter']`,
  which originated from a network request at request_id=abc123."
- **Per-segment authorization.** A sink that operates on portions of a string can
  selectively permit operations on the trusted portions and refuse on the untrusted
  ones. (E.g., a templating system that allows trusted template literals to drive
  formatting decisions but not user-provided content.)
- **Debugging.** Developers can see exactly how a string was built without
  instrumenting their code. "Where did this come from?" becomes a built-in query.
- **Auditing.** Reconstructing data flow from an artifact back to original inputs
  is mechanical, not detective work.

## Why It's Deferred

The cost is significant, and most code doesn't need the richness:

- **Memory pressure on base strings.** Once a query string references a base, the
  base must stay alive even if the original variable holding it has gone out of
  scope. A program that builds query chains over time accumulates base strings that
  cannot be freed. This is the hardest cost to live with.
- **Performance.** Every string-producing operation allocates a query node.
  Materialization is on demand, but most strings get materialized at some point,
  paying the cost twice (once for the query, once for the result).
- **Implementation complexity.** In Lua, strings are interned and immutable; query
  strings would have to live in a parallel wrapper layer. Every string-returning
  method in the runtime would need to produce a query node instead of a string,
  and every sink that needs a real string would need to materialize. The
  developer-facing API stays uniform, but the runtime grows substantially.
- **Most operations don't need it**. The coarse trust tag handles the common case
  ("is this safe at this sink?"). Provenance richness only pays off in forensics,
  per-segment policy decisions, and debugging — none of which are hot-path
  concerns.

### File caching as a partial mitigation

The memory pressure on base strings could be mitigated by spilling cold base
strings to disk. Query strings still reference them, but the materialization step
might pay an I/O cost to read the base back. This is **clunky**: it adds file
management, I/O latency, and complexity to what is supposed to be a
language-level feature. It would help, but it would not be elegant.

Other possible mitigations exist (eager materialization when a base would
otherwise be freed; weak references with snapshot fallback; etc.), but each
trades away some of the provenance benefit. The fundamental tension is real:
keeping full provenance means keeping the inputs, and inputs accumulate.

## Things to Think About When Revisiting

- **Non-concatenative operations.** Substring, slice, replace, regex match — these
  produce strings whose characters trace back to specific positions in a base.
  Query strings naturally express this (a substring query records the byte range
  it cares about), which is one of the reasons the query model fits the problem
  better than a bare operation tree.
- **Provenance garbage collection.** When can the engine prune a query chain?
  Materializing a query and snapshotting the result would let the chain be freed,
  but at the cost of losing provenance. Some operations (say, hashing) could
  materialize without ever needing provenance after; others (forensic queries on
  the resulting string) need it preserved.
- **Serialization.** Provenance probably can't survive serialization (storage
  breaks the trust chain anyway, per the existing trust model). What's the
  round-trip behavior — does serializing a query string materialize it first and
  lose its history, or is provenance preserved as a side-channel?
- **Forensic API.** What does the query interface look like? `$str.provenance`
  returning a tree? `$str.source_at(position)` returning the base that contributed
  byte N? `$str.contains_taint_from(:network)` for predicate checks? Whatever the
  shape, it should be cheap to ask common questions (since the runtime already has
  the data in front of it).
- **Scope.** Does provenance apply only to strings, or also to numbers, hashes,
  arrays? Numbers seem less interesting — a number is usually one value from one
  source. Containers have their own per-element concerns
  (see the container-vs-contents principle in [roles.md](../../charlie/roles.md)).
- **Opt-in mode.** A reasonable design: provenance tracking enabled only when the
  engine is configured for it (debug mode, audit mode, security responder mode).
  Production engines stick with coarse tags for performance; engines that need
  the richness opt in. The Charlie program doesn't notice the difference because
  the API is the same — provenance queries just return less detail (or nothing,
  or a single coarse tag) in the non-provenance case.

## Relation to the Current Trust Model

The coarse tracking (one trust tag per value) is the practical floor. Full
provenance is a strict superset: if you have the query chain back to base strings,
you can derive the coarse tag at any time (intersection of all base trust levels).
When the coarse tag is sufficient, provenance richness is overkill.

For an eventual implementation, the cleanest separation is probably:

- **Coarse mode** (default): strings are real strings; trust is a single tag per
  value, propagated through operations as already designed.
- **Provenance mode** (opt-in): strings are query strings; bases are tracked
  explicitly; the same API works but the underlying representation is richer.

The developer-facing surface stays the same in both modes. The engine config is
what determines which representation is used at runtime.
