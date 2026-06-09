# Puck Objects (brainstorm — folded into official doc)

~~~vibecode
{"vibecode": {
	"doc": "puck-object",
	"role": "historical brainstorm that worked out the puck-object-vs-%puck distinction; superseded by the canonical puck.md but kept as a record of how the design developed",
	"key_concepts": ["puck_object_vs_system_method", "chain_scoped_puck",
		"historical_record"],
	"status": "folded_into_canonical",
	"note": "version-window-on-puck design has since moved off the puck to %puck.era; see versioning.md"
}}
~~~

> **Status: this brainstorm has been folded into the official
> [documentation/puck.md](../requirements/puck/index.md).** The puck-object model is
> now part of the canonical Puck documentation. This file is preserved
> as a historical record of how the design developed.
>
> For the current spec, read [documentation/puck.md](../requirements/puck/index.md)
> (specifically the "The Puck Object" section and below).
>
> **Update — the version window has since moved off the puck object.**
> The current design puts the cutoff on `%chain` via a block-scoped
> `%puck.era(upper:, lower:) do ... end` form (see
> [caspian/versioning.md § The Cutoff in %chain](../requirements/caspian/versioning/timestamp.md#the-cutoff-in-chain)).
> The "Version Window" and "restrict do ... end" sections below are
> preserved as the earlier design.

---

**(Original status:)** brainstorming. Captures notes from the role-model
discussion about what a puck *is* as an object, distinct from the
`%puck` system method that returns one. Once the model stabilizes,
material here may be folded into [puck.md](../requirements/puck/index.md).

---

<a id="puck-object-vs-puck"></a>
## Puck Object vs. `%puck`

A **puck** (lowercase, the object) is distinct from **`%puck`** (the
system method). A puck is a kind of object that knows how to resolve
UNS addresses to their registered objects. `%puck` is the
system-method handle through which user code gets a puck object back.

**`%puck` is scoped via `%chain`.** What it returns depends on
context. The current puck lives in `%chain` — `%puck` reads from
there. Because `%chain` is wiped at role boundaries (see
[roles.md](../requirements/caspian/roles.md)), the current puck does not propagate across
boundaries; each role gets its own world.

- Outside any `restrict` block, in the outer role, `%puck` returns
  whatever the engine placed in the chain at program start
  (typically the engine-provided default puck).
- Inside a `restrict do ... end` block, `%puck` returns the derived
  (narrower) puck that `restrict` installed in the chain for the
  block's duration.
- After the block returns, the prior chain value is restored.
- **When there is no puck in the chain, `%puck` returns plain
  null** — no flavor, no fallback, no error. The caller deals with
  it however they want.

This is why `%puck` does not always return the same object.

**You can have any number of pucks.** When the docs say "the puck,"
that's shorthand for whatever puck `%puck` returns at the moment —
usually the engine-provided one. The model supports any number, and
code that constructs alternate pucks for specific purposes
(different cutoffs, different fetcher sets, different policies) can
do so.

Different pucks can have different search paths, different
provenance-checking policies, different roles, and different version
windows. The engine decides what to hand in at startup; scoped
derivations (via `restrict do ... end`) can override that for a
block.

<a id="restrict-do-end"></a>
### `restrict do ... end`

> **Superseded.** Replaced by `%puck.era(upper:, lower:)
> do ... end` — see
> [caspian/versioning.md § The Cutoff in %chain](../requirements/caspian/versioning/timestamp.md#the-cutoff-in-chain).
> The block-scoped narrowing pattern survives; the verb and the
> property location moved from the puck object to `%chain`.

`restrict` is the canonical way to scope `%puck` to a narrower
window for a block of code:

```
%puck                                  # outer puck (no extra restriction)

%puck.restrict(upper: 'may 3, 2023') do
    %puck                              # narrower derived puck, in effect inside the block
end

%puck                                  # back to the outer puck
```

`restrict` does two things at once:

1. **Derives** a narrower puck from the current one (per the
   one-way ratchet — narrower or equal, never broader).
2. **Installs** the derived puck as the active `%puck` for the
   duration of the block.

Nested `restrict` calls compose — narrowing further from inside an
already-narrowed scope is fine, subject to the ratchet. When the
innermost block returns, the next-outer scope's puck takes over;
when the outermost `restrict` returns, the engine's original puck
is in effect again.

Same shape as the other scoped-block primitives in the framework
(`%chain.isolate do ... end`, `%chain.scope do ... end`, etc.).

<a id="version-window"></a>
## Version Window

> **Superseded.** The version window no longer lives on the puck
> object. Current design puts the cutoff on `%chain` as a
> block-scoped `%puck.era(upper:, lower:) do ... end`
> form — see
> [caspian/versioning.md § The Cutoff in %chain](../requirements/caspian/versioning/timestamp.md#the-cutoff-in-chain).
> The technical observations about lookup mechanics (multi-fetcher
> walking under bounds, tie-breaking, etc.) still apply; only the
> property location and verbs have changed.

Each puck carries a **version window** — two timestamps that bound
which versions of an object are eligible to be returned. The window
lives on the puck object itself; the engine sets it when the puck
is created. (This replaces the earlier `%chain.cutoff` design.)

```
%puck.lower = 'may 3, 2018'      # versions must be on or after
%puck.upper = 'may 3, 2028'      # versions must be on or before
```

The two properties:

- **`upper`** — the latest acceptable timestamp. The puck returns
  the latest version of an object that is on or before `upper`.
  Without `upper`, the puck returns the latest existing version,
  full stop.
- **`lower`** — the earliest acceptable timestamp. Versions older
  than `lower` are not returned. Without `lower`, the floor is
  effectively negative infinity.

**Both properties are immutable once the puck exists.** The engine
sets them at creation time, and no API can change them afterward.
This turns the timespan from a configuration knob into a structural
sandbox — if the engine confines user code to a specific window, the
window can't be widened from within the runtime.

<a id="deriving-a-narrower-puck"></a>
### Deriving a Narrower Puck

A puck can produce a **derived puck with a narrower window**, but
never a broader one. The one-way ratchet:

- The derived puck's `upper` must be ≤ parent's `upper`.
- The derived puck's `lower` must be ≥ parent's `lower`.
- Equivalently: the derived puck's window is a subset of the
  parent's window.

So given a parent with `[2018, 2028]`, valid derivations include
`[2020, 2025]`, `[2018, 2025]`, `[2020, 2028]`, and the same
`[2018, 2028]`. Invalid: `[2015, 2025]` (widens lower), `[2018,
2030]` (widens upper), or any combination that extends past the
parent.

This follows the broader "derived capabilities can only be more
restricted" pattern in the framework (file permissions ratchet,
subdirjail permissions ratchet, etc.). The deriver is producing a
new puck, which they own; the new puck's window is bounded by
what the parent allowed.

<a id="what-the-narrowing-rule-does-not-prevent"></a>
### What the Narrowing Rule Does NOT Prevent

**Code with access to a network faucet (or any other faucet) can
construct its own puck from scratch.** That fresh puck isn't
derived from the engine's puck — it's built directly on the
faucet — and its timespan can be whatever the constructor chooses.

This is intentional. The puck-derivation rule constrains how an
*existing* puck can be narrowed; it doesn't and cannot prevent
code that already holds raw faucets from building a separate puck
around them.

The framework's stance: **[the nanny](https://puck.uno/documentation/overview#no-nanny-code) stays out of this.** Don't pass
a network faucet (or any other faucet) to code you don't trust to
use it however it wants. The authority is in the faucet, not in the
puck. If you want a callee to be unable to make HTTPS calls, don't
give them a network faucet in the first place. Use jails to
restrict what passes across role boundaries.

Consistent with the broader "developer decides what to expose by
what they pass" principle (see [roles.md](../requirements/caspian/roles.md) — boundary
crossings do not gate method access; jails are the explicit
narrowing mechanism).

Lookup semantics:

- Default (no bounds set) — return the latest version that exists.
- `upper` only — return the latest version on or before `upper`.
- `lower` only — return the latest version that is on or after
  `lower`.
- Both set — return the latest version in `[lower, upper]`.
- If no version exists in the allowed span, lookup behaves as if
  the UNS isn't there (returns null-flavored `not_found`).

<a id="implication-for-fetcher-walking"></a>
### Implication for fetcher walking

The version window changes the lookup mechanic. **The puck may need
to consult all its fetchers to find the latest version within bounds**,
rather than short-circuiting on first hit. Each fetcher reports its
latest-within-window for the UNS; the puck returns the latest of
those responses.

This is materially different from "first hit wins" — a later-in-order
fetcher that holds a newer version overrides an earlier fetcher that
holds an older one. Order of fetchers in the puck matters less for
priority; the window decides what's returned.

**Tie-breaking** when two fetchers return versions with the same
timestamp: pick the first. Same UNS at the same timestamp means
the same object — if two fetchers returned different content at
the same timestamp, something is broken (corruption,
misconfiguration), but the normal case is that they agree, so
order-based first-wins is fine.

---

<a id="what-a-puck-does"></a>
## What a Puck Does

A puck **holds one or more fetchers**, each representing a logical
source for objects (e.g., the `foo.com/*` namespace, a corporate
internal registry, a local-only namespace, etc.). The puck is the
lookup orchestrator; the fetchers are the per-source units.

Each fetcher may internally use one or more **faucets** to do the
actual fetching:

- A typical remote-namespace fetcher has a **download faucet** (HTTPS
  to the source) plus a **cache faucet** (local cache directory).
  First-time lookups go through download (and populate the cache);
  subsequent lookups hit the cache.
- A fetcher that talks to a local resource (an internal network
  service, a database, a local file tree) might have just one
  faucet.

<a id="lookup"></a>
### Lookup

A puck exposes a **lookup method** as its public API. (Working name
TBD — likely `.lookup($uns)` or similar; the actual name will be
settled when the class is spec'd in detail.)

**Base implementation:** the puck walks its fetchers, asking each
one for the latest version of the UNS that falls within the puck's
[lower, upper] window. The puck then returns the latest result
across all fetchers' responses. If no fetcher has any version of the
UNS within the window, lookup returns a null with the flavor
`puck.uno/null/flavor/not_found` (per the HTTP-style null-flavor
scheme in [nulls.md](../requirements/caspian/built-in-classes/nulls.md)). Callers
can inspect `flavor.code` to tell the difference between "lookup
didn't match" and "the registered value is intentionally null."

(See the **Version Window** section above for window semantics. Note
that the puck may consult all fetchers rather than short-circuiting
on first hit — finding the latest requires checking each.)

<a id="the-explicit-null-rule-for-sources"></a>
#### The `explicit`-null rule for sources

If a puck faucet reaches a UNS where the registered value is
intentionally null, **the source must mark that null as
`puck.uno/null/flavor/explicit`** (code 200). Otherwise the puck
treats an unflavored null as "lookup didn't find this UNS" and
falls through to the next fetcher.

In other words: at the puck-lookup layer, **unflavored null means
"no result"**, and `explicit` is how a source positively affirms
"yes, this UNS exists; the registered value is null." Same pattern
as HTTP 200 with an empty body vs. HTTP 404.

The obligation lands on the source. Puck-native sources serialize
null flavors through naturally; non-native sources (generic HTTPS,
third-party protocols) need their faucet implementation to
translate appropriately.

**Subclassable for fancier dispatch.** The base implementation is
intentionally simple. Engines or developers needing UNS-prefix
matching, regex routing, dispatch tables, or fallback policies can
subclass puck and override the lookup method.

<a id="roles-per-fetcher-not-per-faucet"></a>
### Roles: per-fetcher, not per-faucet

**Each fetcher has its own role.** Objects served through a fetcher
get that fetcher's role. Different fetchers in the same puck produce
differently-tagged objects, because they're genuinely different
logical sources.

**Faucets inside a fetcher share the fetcher's role.** This is the key
property that resolves the download-vs-cache problem. Caspian caches
remote objects on demand — first-time fetches go through download,
subsequent fetches through cache. Both are faucets inside the same
fetcher, both produce objects with the fetcher's role. The same UNS
hands back identically-tagged objects regardless of cache state.

```
Puck
├─ Getter for foo.com/*       (role: foo-com-fetcher)
│  ├─ HTTPS download faucet
│  └─ Cache faucet
├─ Getter for bar.com/*       (role: bar-com-fetcher)
│  ├─ HTTPS download faucet
│  └─ Cache faucet
└─ Getter for internal/*      (role: internal-fetcher)
   └─ Internal-network faucet
```

The engine sets up the puck with its fetchers. Each fetcher gets its
own role assigned by the engine at creation time. Objects flow
through fetchers and inherit the fetcher's role; cache state never
affects role assignment.

---

<a id="provenance-checking"></a>
## Provenance Checking

Provenance is **per-faucet**, not per-puck. Each faucet has its own
policy about how to sign off on provenance for the objects it serves.
A puck may hold one strict-policy faucet (verifies signatures
against a blockchain attestation) alongside a permissive-policy
faucet (trusts the cache directory's self-asserted contents) — same
puck, different per-faucet rules.

A faucet's responsibility is **provenance** — verifying that an
object it returns for a UNS actually came from the namespace
authority that UNS claims. *Whether the code itself is safe to run*
is a separate concern handled by the role model and capability-
passing mechanics; the faucet's job is just "is this really from
where it says it's from?"

<a id="case-1-actual-fetch-from-the-url"></a>
### Case 1: Actual fetch from the URL

An **HTTPS faucet** that fetches from the URL claimed by the UNS.
TLS handles the certificate verification at the network layer; the
response by construction came from the verified server. No
additional check needed at this faucet's layer.

<a id="case-2-cache"></a>
### Case 2: Cache

A **cache faucet** that looks up the object in a local cache
directory rather than re-fetching every time.

**Default trust:** the cache holds objects placed there by an earlier
download step (which had its own provenance verification at install
time). The runtime trusts the cache implicitly — "I put this here, so
it came from where I downloaded it from." Simple, matches how
npm/pip/gem/Cargo work.

**Objects pulled from the cache get the fetcher's role** (per the
per-fetcher rule). Cache hits and cache misses within the same fetcher
produce identically-tagged objects.

**Limitation:** the cache is a single trust anchor. An attacker with
filesystem write access to the cache can plant malicious code that
inherits cache-level authority. Case 3 addresses this.

<a id="case-3-cache-plus-signature-verification"></a>
### Case 3: Cache plus signature verification

A **cache faucet with a stricter provenance policy** — same source as
case 2 (the cache directory), but the faucet additionally verifies
cryptographic signatures on objects before serving them. Faucets can
layer their own checks; this is one such layering.

Examples:

- **Puck blockchain** ([blockchain.md](../requirements/caspian/blockchain/index.md)) holds
  signed attestations from UNS authorities. Cached objects are
  verified against blockchain entries before being trusted.
- Traditional public-key signing infrastructures (the source signs
  releases; the puck holds the public key and verifies).
- Third-party signature registries.

This is the "two distant objects" pattern: the local cache holds the
artifact, the distant verification mechanism holds proof. To attack,
both must be compromised.

The simple-case puck doesn't include this. Strict-case pucks layer
it on.

---

<a id="the-engine-decides-the-policy"></a>
## The Engine Decides the Policy

**The engine controls which puck `%puck` returns**, and that puck's
configuration determines everything about provenance policy:

- Which sources the puck consults.
- What provenance checks are required.
- How strict the checks are.
- Whether failed checks are warnings or hard rejections.

Different engines hand in different pucks. A strict, security-
sensitive deployment hands user code a puck that requires signatures
and blockchain attestations. A relaxed developer playground hands
user code a puck that just trusts the cache. The Caspian code is the
same; the puck differs.

User code typically doesn't reason about which puck it got. It calls
`%puck['https://some.com/uns']`, and whatever the engine set up determines
the result and the checks.

---

<a id="open-questions"></a>
## Open Questions

- **Does `%puck` always return the same puck object across calls?**
  Resolved: no. `%puck` is scoped. By default it returns the
  engine-provided puck; inside a `restrict do ... end` block, it
  returns the derived (narrower) puck. See the `restrict` section
  above.
- **Cache role's default capabilities** — what can code running as
  `cache` actually do? (Cross-references the open question in
  [roles.md](../requirements/caspian/roles.md).)
- **Where the version cutoff lives.** Resolved three times: first onto
  the puck object (see "Version Window" section above), then off it
  onto `%chain` as a block-scoped `version_timespan`, then back onto
  `%puck` as `%puck.era` — see
  [caspian/versioning § Setting the cutoff with %puck.era](../requirements/caspian/versioning/timestamp.md#the-cutoff-in-chain).
- **Granularity of puck-source roles** — one role per **fetcher**
  inside the puck. Faucets *inside* a fetcher (download + cache)
  share the fetcher's role to keep cache state from changing the
  tag. Aligns with the broader granularity question in
  [roles.md](../requirements/caspian/roles.md).
