# Idea: Trusted-Database Input Filtering

Not implemented. Worth recording so future decisions can build on it.

## The Idea

Under the role model ([roles.md](../../kscript/roles.md)), a database faucet has its
own role, and values pulled through it are owned by that role. If that
role is trusted by the caller's role, the values can flow freely.

This opens a laundering attack vector: if untrusted data is *written* into
a trusted database, later reads pull the same data back out as a trusted
object. The trust check at the read sink is satisfied, but the content
came from an untrusted source.

To close this gap, the engine should provide **tools for filtering what
goes into a trusted database** — blocking untrusted strings (and other
untrusted values) from being written. A trusted database remains trusted
because nothing untrusted ever lands in it.

## Likely Shape

- A trusted database connection refuses writes of untrusted values by
  default. Attempting to insert/update with an untrusted string raises a
  trust error at the write sink.
- The developer can opt in to allowing specific untrusted values via
  `%chain.trust` (the existing override), bounded by the developer's own
  trust level.
- Per-column policies (TBD): some columns might be allowed to hold
  untrusted data even in a trusted database; reads of those columns
  return untrusted values, while reads of other columns return trusted
  values. The schema would carry per-column trust policy.

## Relationship to Database Firewalls

The existing [firewall](firewall.md) rule mechanism — already part of
every engine's base spec — is a natural place to enforce these checks.
A firewall rule attached to a trusted database engine can inspect writes
and reject any carrying untrusted values, without requiring database-
specific machinery. Defense in depth: the rule applies at any point in
the chain.

Two specific filter shapes worth noting for future design (not designed
yet, just placeholders):

- **Hard block.** "Don't allow anything untrusted." Any write of an
  untrusted value is rejected outright. Simple and absolute.
- **Negotiable roadblock.** Writes of untrusted values are rejected
  *unless* the caller has explicitly validated them — some form of
  positive declaration at the call site (analogous to `use_path`'s
  "I've considered this; let it through") that allows the write to
  proceed while keeping the elevation visible.

Both are forward-looking ideas; neither is designed.

## Why It's Deferred

- Doesn't yet have a concrete use case driving it. The trust model works
  without it for the current set of databases.
- Per-column trust policy is potentially a lot of schema metadata to
  spec; needs more thought before designing.
- The laundering vector is real but theoretical for now — no existing
  Kiera component marks a database as trusted.

## When to Revisit

- The first time we want to mark a database as trusted.
- If a real-world laundering exploit is identified in a Kiera-based
  application.
- When the schema metadata story (currently TBD across the project) is
  ready to absorb per-column trust policy.
