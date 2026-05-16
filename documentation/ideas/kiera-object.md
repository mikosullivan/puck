# Kiera Objects (brainstorm — folded into official doc)

> **Status: this brainstorm has been folded into the official
> [documentation/kiera.md](../kiera/kiera.md).** The kiera-object model is
> now part of the canonical Kiera documentation. This file is preserved
> as a historical record of how the design developed.
>
> For the current spec, read [documentation/kiera.md](../kiera/kiera.md)
> (specifically the "The Kiera Object" section and below).

---

**(Original status:)** brainstorming. Captures notes from the role-model
discussion about what a kiera *is* as an object, distinct from the
`%kiera` system method that returns one. Once the model stabilizes,
material here may be folded into [kiera.md](../kiera/kiera.md).

---

## Kiera Object vs. `%kiera` (Three of Nine)

A **kiera** (lowercase, the object) is distinct from **`%kiera`** (the
system method). A kiera is a kind of object that knows how to resolve
UNS addresses to their registered objects. `%kiera` is the
system-method handle through which user code gets a kiera object back.

**`%kiera` is scoped via `%chain`.** What it returns depends on
context. The current kiera lives in `%chain` — `%kiera` reads from
there. Because `%chain` is wiped at role boundaries (see
[roles.md](../kscript/roles.md)), the current kiera does not propagate across
boundaries; each role gets its own world.

- Outside any `restrict` block, in the outer role, `%kiera` returns
  whatever the engine placed in the chain at program start
  (typically the engine-provided default kiera).
- Inside a `restrict do ... end` block, `%kiera` returns the derived
  (narrower) kiera that `restrict` installed in the chain for the
  block's duration.
- After the block returns, the prior chain value is restored.
- **When there is no kiera in the chain, `%kiera` returns plain
  null** — no flavor, no fallback, no error. The caller deals with
  it however they want.

This is why `%kiera` does not always return the same object.

**You can have any number of kieras.** When the docs say "the kiera,"
that's shorthand for whatever kiera `%kiera` returns at the moment —
usually the engine-provided one. The model supports any number, and
code that constructs alternate kieras for specific purposes
(different cutoffs, different getter sets, different policies) can
do so.

Different kieras can have different search paths, different
provenance-checking policies, different roles, and different version
windows. The engine decides what to hand in at startup; scoped
derivations (via `restrict do ... end`) can override that for a
block.

### `restrict do ... end`

`restrict` is the canonical way to scope `%kiera` to a narrower
window for a block of code:

```
%kiera                                  # outer kiera (no extra restriction)

%kiera.restrict(upper: 'may 3, 2023') do
    %kiera                              # narrower derived kiera, in effect inside the block
end

%kiera                                  # back to the outer kiera
```

`restrict` does two things at once:

1. **Derives** a narrower kiera from the current one (per the
   one-way ratchet — narrower or equal, never broader).
2. **Installs** the derived kiera as the active `%kiera` for the
   duration of the block.

Nested `restrict` calls compose — narrowing further from inside an
already-narrowed scope is fine, subject to the ratchet. When the
innermost block returns, the next-outer scope's kiera takes over;
when the outermost `restrict` returns, the engine's original kiera
is in effect again.

Same shape as the other scoped-block primitives in the framework
(`%chain.isolate do ... end`, `%chain.scope do ... end`, etc.).

## Version Window (Magnus Hansen)

Each kiera carries a **version window** — two timestamps that bound
which versions of an object are eligible to be returned. The window
lives on the kiera object itself; the engine sets it when the kiera
is created. (This replaces the earlier `%chain.cutoff` design.)

```
%kiera.lower = 'may 3, 2018'      # versions must be on or after
%kiera.upper = 'may 3, 2028'      # versions must be on or before
```

The two properties:

- **`upper`** — the latest acceptable timestamp. The kiera returns
  the latest version of an object that is on or before `upper`.
  Without `upper`, the kiera returns the latest existing version,
  full stop.
- **`lower`** — the earliest acceptable timestamp. Versions older
  than `lower` are not returned. Without `lower`, the floor is
  effectively negative infinity.

**Both properties are immutable once the kiera exists.** The engine
sets them at creation time, and no API can change them afterward.
This turns the timespan from a configuration knob into a structural
sandbox — if the engine confines user code to a specific window, the
window can't be widened from within the runtime.

### Deriving a Narrower Kiera

A kiera can produce a **derived kiera with a narrower window**, but
never a broader one. The one-way ratchet:

- The derived kiera's `upper` must be ≤ parent's `upper`.
- The derived kiera's `lower` must be ≥ parent's `lower`.
- Equivalently: the derived kiera's window is a subset of the
  parent's window.

So given a parent with `[2018, 2028]`, valid derivations include
`[2020, 2025]`, `[2018, 2025]`, `[2020, 2028]`, and the same
`[2018, 2028]`. Invalid: `[2015, 2025]` (widens lower), `[2018,
2030]` (widens upper), or any combination that extends past the
parent.

This follows the broader "derived capabilities can only be more
restricted" pattern in the framework (file permissions ratchet,
subdirjail permissions ratchet, etc.). The deriver is producing a
new kiera, which they own; the new kiera's window is bounded by
what the parent allowed.

### What the Narrowing Rule Does NOT Prevent

**Code with access to a network faucet (or any other faucet) can
construct its own kiera from scratch.** That fresh kiera isn't
derived from the engine's kiera — it's built directly on the
faucet — and its timespan can be whatever the constructor chooses.

This is intentional. The kiera-derivation rule constrains how an
*existing* kiera can be narrowed; it doesn't and cannot prevent
code that already holds raw faucets from building a separate kiera
around them.

The framework's stance: **the nanny stays out of this.** Don't pass
a network faucet (or any other faucet) to code you don't trust to
use it however it wants. The authority is in the faucet, not in the
kiera. If you want a callee to be unable to make HTTPS calls, don't
give them a network faucet in the first place. Use jails to
restrict what passes across role boundaries.

Consistent with the broader "developer decides what to expose by
what they pass" principle (see [roles.md](../kscript/roles.md) — boundary
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

### Implication for getter walking

The version window changes the lookup mechanic. **The kiera may need
to consult all its getters to find the latest version within bounds**,
rather than short-circuiting on first hit. Each getter reports its
latest-within-window for the UNS; the kiera returns the latest of
those responses.

This is materially different from "first hit wins" — a later-in-order
getter that holds a newer version overrides an earlier getter that
holds an older one. Order of getters in the kiera matters less for
priority; the window decides what's returned.

**Tie-breaking** when two getters return versions with the same
timestamp: pick the first. Same UNS at the same timestamp means
the same object — if two getters returned different content at
the same timestamp, something is broken (corruption,
misconfiguration), but the normal case is that they agree, so
order-based first-wins is fine.

---

## What a Kiera Does (Erin Hansen)

A kiera **holds one or more getters**, each representing a logical
source for objects (e.g., the `foo.com/*` namespace, a corporate
internal registry, a local-only namespace, etc.). The kiera is the
lookup orchestrator; the getters are the per-source units.

Each getter may internally use one or more **faucets** to do the
actual fetching:

- A typical remote-namespace getter has a **download faucet** (HTTPS
  to the source) plus a **cache faucet** (local cache directory).
  First-time lookups go through download (and populate the cache);
  subsequent lookups hit the cache.
- A getter that talks to a local resource (an internal network
  service, a database, a local file tree) might have just one
  faucet.

### Lookup

A kiera exposes a **lookup method** as its public API. (Working name
TBD — likely `.lookup($uns)` or similar; the actual name will be
settled when the class is spec'd in detail.)

**Base implementation:** the kiera walks its getters, asking each
one for the latest version of the UNS that falls within the kiera's
[lower, upper] window. The kiera then returns the latest result
across all getters' responses. If no getter has any version of the
UNS within the window, lookup returns a null with the flavor
`kiera.uno/null/flavor/not_found` (per the HTTP-style null-flavor
scheme in [nulls.md](../kscript/built-in-classes/nulls.md)). Callers
can inspect `flavor.code` to tell the difference between "lookup
didn't match" and "the registered value is intentionally null."

(See the **Version Window** section above for window semantics. Note
that the kiera may consult all getters rather than short-circuiting
on first hit — finding the latest requires checking each.)

#### The `explicit`-null rule for sources

If a kiera faucet reaches a UNS where the registered value is
intentionally null, **the source must mark that null as
`kiera.uno/null/flavor/explicit`** (code 200). Otherwise the kiera
treats an unflavored null as "lookup didn't find this UNS" and
falls through to the next getter.

In other words: at the kiera-lookup layer, **unflavored null means
"no result"**, and `explicit` is how a source positively affirms
"yes, this UNS exists; the registered value is null." Same pattern
as HTTP 200 with an empty body vs. HTTP 404.

The obligation lands on the source. Kiera-native sources serialize
null flavors through naturally; non-native sources (generic HTTPS,
third-party protocols) need their faucet implementation to
translate appropriately.

**Subclassable for fancier dispatch.** The base implementation is
intentionally simple. Engines or developers needing UNS-prefix
matching, regex routing, dispatch tables, or fallback policies can
subclass kiera and override the lookup method.

### Roles: per-getter, not per-faucet

**Each getter has its own role.** Objects served through a getter
get that getter's role. Different getters in the same kiera produce
differently-tagged objects, because they're genuinely different
logical sources.

**Faucets inside a getter share the getter's role.** This is the key
property that resolves the download-vs-cache problem. KScript caches
remote objects on demand — first-time fetches go through download,
subsequent fetches through cache. Both are faucets inside the same
getter, both produce objects with the getter's role. The same UNS
hands back identically-tagged objects regardless of cache state.

```
Kiera
├── Getter for foo.com/*       (role: foo-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
├── Getter for bar.com/*       (role: bar-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
└── Getter for internal/*      (role: internal-getter)
    └── Internal-network faucet
```

The engine sets up the kiera with its getters. Each getter gets its
own role assigned by the engine at creation time. Objects flow
through getters and inherit the getter's role; cache state never
affects role assignment.

---

## Provenance Checking (Annika)

Provenance is **per-faucet**, not per-kiera. Each faucet has its own
policy about how to sign off on provenance for the objects it serves.
A kiera may hold one strict-policy faucet (verifies signatures
against a blockchain attestation) alongside a permissive-policy
faucet (trusts the cache directory's self-asserted contents) — same
kiera, different per-faucet rules.

A faucet's responsibility is **provenance** — verifying that an
object it returns for a UNS actually came from the namespace
authority that UNS claims. *Whether the code itself is safe to run*
is a separate concern handled by the role model and capability-
passing mechanics; the faucet's job is just "is this really from
where it says it's from?"

### Case 1: Actual fetch from the URL

An **HTTPS faucet** that fetches from the URL claimed by the UNS.
TLS handles the certificate verification at the network layer; the
response by construction came from the verified server. No
additional check needed at this faucet's layer.

### Case 2: Cache

A **cache faucet** that looks up the object in a local cache
directory rather than re-fetching every time.

**Default trust:** the cache holds objects placed there by an earlier
download step (which had its own provenance verification at install
time). The runtime trusts the cache implicitly — "I put this here, so
it came from where I downloaded it from." Simple, matches how
npm/pip/gem/Cargo work.

**Objects pulled from the cache get the getter's role** (per the
per-getter rule). Cache hits and cache misses within the same getter
produce identically-tagged objects.

**Limitation:** the cache is a single trust anchor. An attacker with
filesystem write access to the cache can plant malicious code that
inherits cache-level authority. Case 3 addresses this.

### Case 3: Cache plus signature verification

A **cache faucet with a stricter provenance policy** — same source as
case 2 (the cache directory), but the faucet additionally verifies
cryptographic signatures on objects before serving them. Faucets can
layer their own checks; this is one such layering.

Examples:

- **Kiera blockchain** ([blockchain.md](../kscript/blockchain/blockchain.md)) holds
  signed attestations from UNS authorities. Cached objects are
  verified against blockchain entries before being trusted.
- Traditional public-key signing infrastructures (the source signs
  releases; the kiera holds the public key and verifies).
- Third-party signature registries.

This is the "two distant objects" pattern: the local cache holds the
artifact, the distant verification mechanism holds proof. To attack,
both must be compromised.

The simple-case kiera doesn't include this. Strict-case kieras layer
it on.

---

## The Engine Decides the Policy (Felisa)

**The engine controls which kiera `%kiera` returns**, and that kiera's
configuration determines everything about provenance policy:

- Which sources the kiera consults.
- What provenance checks are required.
- How strict the checks are.
- Whether failed checks are warnings or hard rejections.

Different engines hand in different kieras. A strict, security-
sensitive deployment hands user code a kiera that requires signatures
and blockchain attestations. A relaxed developer playground hands
user code a kiera that just trusts the cache. The KScript code is the
same; the kiera differs.

User code typically doesn't reason about which kiera it got. It calls
`%kiera['some.com/uns']`, and whatever the engine set up determines
the result and the checks.

---

## Open Questions (Felisa Howard)

- **Does `%kiera` always return the same kiera object across calls?**
  Resolved: no. `%kiera` is scoped. By default it returns the
  engine-provided kiera; inside a `restrict do ... end` block, it
  returns the derived (narrower) kiera. See the `restrict` section
  above.
- **Cache role's default capabilities** — what can code running as
  `cache` actually do? (Cross-references the open question in
  [roles.md](../kscript/roles.md).)
- **Where the version cutoff lives.** Resolved: on the kiera object
  itself. See "Version Cutoff" section above.
- **Granularity of kiera-source roles** — one role per **getter**
  inside the kiera. Faucets *inside* a getter (download + cache)
  share the getter's role to keep cache state from changing the
  tag. Aligns with the broader granularity question in
  [roles.md](../kscript/roles.md).
