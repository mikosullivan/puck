# Timestamp versioning

*The date-pinning model and the `%puck.era` surface that sets cutoffs in user code.*

~~~json
{"vibecode": {
	"doc": "timestamp_versioning",
	"role": "canonical reference for Caspian's date-pinned versioning — the rationale (one date governs the whole library tree, reproducibility comes free), the %puck.era surface (block form, era handle, confine), the lookup resolution rules, the out-of-range alarm, the relationship to the blockchain, and what this model replaces",
	"audience": "Caspian programmers writing user-role code that needs to constrain library version selection by date, plus implementers needing to understand the resolution machinery and alarm semantics",
	"key_concepts": ["date_pinning_primary_versioning_axis",
		"puck_era_surface_block_or_handle", "confine_installs_era_as_active_puck",
		"resolution_walks_fetchers_returns_latest_in_range",
		"out_of_range_is_security_alarm_not_dependency_error",
		"blockchain_anchors_dates_when_present",
		"replaces_manifests_lockfiles_constraint_solvers"]
}}
~~~

`%puck.era` constrains library lookups to artifacts within a specified timestamp range. Where [per-UNS timestamp narrowing](#per-uns-timestamp) (also on this page) narrows one specific library by date, and the [per-call kwargs](../puck-lookup.md#per-call-narrowing) narrow one call, an **era** narrows the whole library tree.

This page covers the era surface plus the surrounding date-pinning model: why date-based versioning is the primary axis, how the resolver picks a version given an active range, what happens when no candidate fits, and how the blockchain anchors dates when it's in play.

---

<a id="why-date-pinning"></a>
## Why date-pinning

The model is built around a simple observation: **if your tests passed on 3 May, the library tree as it existed on 3 May is the tree your code is known to work with.** Pinning to that date in production is the most direct expression of that fact.

Three concrete benefits:

1. **One number replaces a tree.** Instead of declaring versions for every direct dependency and hoping the transitive closure resolves consistently, a single date governs the whole graph. No constraint solver, no resolution algorithm, no "transitive version conflict" diagnostics. The cutoff propagates through the call stack, so a library twenty calls deep gets the same date as the top-level program.

2. **Reproducibility comes free.** The cutoff is the lockfile. As long as the date is recorded with the deployment, the library tree can be reproduced exactly.

3. **Testing simplifies.** Run tests on date X. Set the production cutoff to X. Ship. Anything published after X is not in your runtime tree, by construction.

---

<a id="the-puck-era-surface"></a>
## The `%puck.era` surface

Three forms, same underlying mechanism: a block form for inline narrowing, an era object you can hold and reuse, and a `confine` block that installs an era as the active `%puck` for transparent narrowing.

<a id="block-form"></a>
### Block form — inline narrowing

The simplest case: narrow every `%puck` lookup inside a block.

```
%puck.era(min: '2023-08-12', max: '2023-09-01') do
    $gup    = %puck['foo.bar/gup']      # narrowed to the era
    $other  = %puck['baz.io/widget']    # also narrowed
end
```

Inside the block, every lookup through `%puck` is filtered to artifacts whose [`effective_date`](../downloads/service/blockchain/index.md#effective-date) (falling back to `posted`) falls within `[min, max]`. After the block exits, the previous era state is restored.

Both `min` and `max` are accepted; either or both can be omitted, leaving that end unbounded:

```
%puck.era(min: '2023-08-12') do ... end                       # only lower bound
%puck.era(max: '2023-09-01') do ... end                       # only upper bound
%puck.era(min: '2023-08-12', max: '2023-09-01') do ... end    # both
```

<a id="the-cutoff-in-chain"></a>
**Inner blocks can only narrow.** A nested era must lie within the enclosing window — widening is rejected with `puck.uno/error/era/widen`.

Block-scoped means the era **does not cross role boundaries** — see [roles.md](../roles.md). Each role starts with whatever era the engine installed at the boundary (typically none, or a deployment-wide upper).

<a id="era-object"></a>
### Era object — explicit handle

Get an era object, configure it, use it directly for lookups:

```
$era = %puck.era                        # new era handle, both ends unbounded
$era.min = '2023-08-12'
$era.max = '2023-09-01'

$gup = $era['foo.bar/gup']              # lookup through the era — narrowed
```

`$era` behaves like a [derived `%puck`](../../puck/index.md): you can call `$era[uns]` exactly like `%puck[uns]`, but every lookup carries the era's bounds.

Like all the config surfaces in this directory, the era handle uses the [dual-path pattern](semver.md#two-paths): assign-the-whole-thing or tweak-a-property.

```
$era = %puck.era                                              # construct
$era = %puck.era(min: '2023-08-12', max: '2023-09-01')        # construct + set both
$era.min = '2023-08-12'                                       # tweak one bound
$era.max.cmp = '<'                                            # exclusive upper
```

`.min` / `.max` are autovivified the same way as elsewhere; default state is unbounded; `.cmp` defaults are inclusive (`>=` for `.min`, `<=` for `.max`); validity rules per bound match the [canonical bound-operator reference](semver.md#bound-operators-cmp).

Holding an era as a variable is useful when you want to thread the same constraint through many lookups, or pass it as a parameter to a function that does its own lookups.

<a id="confine"></a>
### `confine` — install the era as the active `%puck`

When you have an era and want code inside a block to use `%puck` *as if* it were that era — without rewriting every call site — use `confine`:

```
$era = %puck.era
$era.min = '2023-08-12'
$era.max = '2023-09-01'

$era.confine do
    $gup = %puck['foo.bar/gup']     # %puck behaves as $era inside this block
    do_more_work()                  # any %puck lookup inside also narrowed
end
# After the block: %puck is back to whatever it was before.
```

`confine` is the bridge between the era-object model and the block-scoped model: build the era however you want (one place), then any code that takes `%puck` for granted picks up the constraints transparently inside the block. Useful for narrowing third-party code paths without modifying them.

---

<a id="per-uns-timestamp"></a>
## Per-UNS timestamp narrowing — `%puck.config(uns).timestamp`

Where `%puck.era` narrows every lookup, `%puck.config(uns).timestamp` narrows **just one specific library** by date. Useful when you want to pin one library to a specific window without affecting anything else — testing a deployment with one library held back, isolating a known-good revision of one specific dependency, etc.

```
$config = %puck.config('foo.bar/gup')
$config.timestamp = '2023-08-12'                                  # pin to one calendar day
$config.timestamp = {min: '2023-08-12', max: '2023-09-01'}        # range
$config.timestamp.max = '2023-09-01'                              # only upper bound; min unbounded
$config.timestamp.min.cmp = '>'                                   # strictly after
```

The `%puck.config(uns)` handle is **live global state** for that UNS: setting a property takes effect immediately, two handles into the same UNS share state, and the `$config` variable is purely convenience. Full semantics of the handle live in [semver.md § The config object is a live handle, not a snapshot](semver.md#live-global-state) — same handle, same lifecycle, just configuring a different axis.

`.min` / `.max` autovivify; bound operators use the same `.cmp` system as everywhere else in the area. The **canonical reference for the bound-operator system** lives in [semver.md § Bound operators (`cmp`)](semver.md#bound-operators-cmp); the per-UNS timestamp axis reuses it without re-spec'ing it. Defaults are inclusive (`>=` for `.min`, `<=` for `.max`); the same validity rules per bound apply.

A bare timestamp value (e.g. `'2023-08-12'`) is interpreted as a **pin** — `min = max = '2023-08-12'`, both inclusive. To express a window, use the range form (hash or property tweaks).

---

<a id="resolution-rules"></a>
## Resolution rules

For a lookup `%puck['foo.com/bar']` under an active timespan `[L, U]`:

1. The puck walks its fetchers (per [puck.md § Lookup Mechanism](../../puck/index.md)), each consulting its faucets (cache first, then remote source typically). Each fetcher reports the **latest version of `foo.com/bar` within `[L, U]`** that it has.
2. The puck returns the latest result across all fetchers' responses. Finding the latest requires consulting all fetchers, not short-circuiting on first hit.
3. In a future release, the puck will check the signature of the library against a key library. That feature is not in initial development.
4. If no fetcher returns a match, the [out-of-range alarm](#out-of-range-alarm) is raised.

Each `(UNS, version, date)` triple is its own cached artifact. Different programs running through the same engine under different cutoffs will each get the appropriate version for their cutoff; no program's lookup affects any other's.

The "canonical date" of a library is whatever the provider has authoritatively recorded. For a [blockchain](../downloads/service/blockchain/)-backed provider, this is the `posted` timestamp on the chain (or the `effective_date`, if explicitly set; see [Relationship to the blockchain](#relationship-to-the-blockchain) below). For a plain HTTPS provider, this is whatever the provider asserts — the date is no stronger than the trust placed in the provider.

The same machinery applies when other constraint surfaces are active: [`%puck.config(uns)`](semver.md) constraints intersect with the era; per-call kwargs intersect further. In all cases the resolver picks the latest candidate satisfying every active constraint.

---

<a id="out-of-range-alarm"></a>
## Out-of-range alarm

When a library lookup returns nothing dated within the active `[L, U]` timespan, the engine raises `puck.uno/error/out_of_range`. This is an **alarm** under the role model (see [roles.md — Exceptions and Alarms](../roles.md)): always fatal, no unwinding, no `finally` blocks, no catch handlers from Caspian code. The engine takes over directly.

**This is not a "missing dependency" error.** If the program was tested under cutoff X and is now running under the same cutoff, every library it calls should resolve. An out-of-range exception means one of the following has happened:

- A code path is calling a library that wasn't reached during testing — it was injected, smuggled in, or exists in code that is somehow new since the test run.
- The cache or provider chain has been tampered with — a library has been backdated, removed, or replaced.
- The versioning system itself has a flaw — a bug in the resolver, cache corruption, the active timespan not being applied correctly.

In each case, the integrity of the deployment is in question. The exception is therefore treated with the same severity as any other security exception, not as ordinary control flow.

The same alarm fires when [per-UNS timestamp narrowing](#per-uns-timestamp) or [per-UNS semver constraints](semver.md) intersect with the era to produce an empty candidate set, and when [per-call kwargs](../puck-lookup.md#per-call-narrowing) rule out every candidate the broader surfaces would have allowed. The integrity argument applies identically in those cases.

<a id="forensic-payload"></a>
### Forensic payload

The alarm carries a structured payload describing exactly what happened:

- The UNS that was looked up.
- The cutoff (and any per-UNS / per-call constraints) that were in effect.
- The latest available date for that UNS (so the gap is visible).
- The full call stack from the program entry point to the offending lookup.
- The signer / authority that posted the closest available version (when known).

This is the information a security responder or audit log needs to investigate.

---

<a id="what-this-replaces"></a>
## What this replaces

The model intentionally starts without:

- **Manifest / package.json / Cargo.toml** — there is no per-program file declaring dependencies or version ranges. Dependencies are whatever the source code references via `%puck[...]`.
- **Lockfile** — the cutoff timestamp is the lockfile.
- **Semver constraint solver** — not present. Semver values are filterable (per call, per UNS), but resolution is still a flat query: pick the latest candidate whose date and semver satisfy whatever constraints are in scope. No SAT solver, no transitive semver propagation, no ranges-against-ranges intersection across the graph. Adding solver behaviour later is possible; the bar should be high.
- **Transitive version conflicts** — a library deep in the call stack cannot pin a different version than the rest of the tree, because every lookup uses the same active timespan.

The design starts from a position of not needing these mechanisms. Adding any of them later is possible — but each one increases the burden on every script (versions to track, manifests to maintain, conflicts to resolve), so the bar for introducing them should be high.

---

<a id="relationship-to-the-blockchain"></a>
## Relationship to the blockchain

The Puck [blockchain](../downloads/service/blockchain/) provides a cryptographically anchored `posted` timestamp for every library version. When a chain is available, the cutoff is genuinely tamper-evident — a library's date cannot be forged.

When the cutoff is enforced against non-chain providers, dates are only as trustworthy as the providers themselves. The model still works — the engine still picks the latest version on or before the cutoff — but the integrity guarantee is weaker.

The date-pinning model itself does not require a [blockchain](../downloads/service/blockchain/). It is the simpler primitive; the chain is one implementation of trustworthy dates.

---

<a id="composition"></a>
## Composition with other narrowing surfaces

`%puck.era` is one of several constraint surfaces. At any lookup, all active constraints **intersect**:

| Surface | Axis | Scope | Set via |
|---|---|---|---|
| `%puck.era` (this page) | timestamp | Puck-wide, block-scoped or handle | `%puck.era(min:, max:) do ... end` / `%puck.era` handle |
| [Per-UNS timestamp](#per-uns-timestamp) (this page) | timestamp | One UNS, live-global | `%puck.config(uns).timestamp = ...` |
| [Per-UNS semver](semver.md) | semver | One UNS, live-global | `%puck.config(uns).semver = ...` |
| [Per-call kwargs](../puck-lookup.md#per-call-narrowing) | both | One call | `%puck['uns', ts_min: '...', semver_min: '...']` |

At lookup time the resolver checks every active constraint. If their intersection is empty for a given UNS, the lookup raises [`puck.uno/error/out_of_range`](#out-of-range-alarm). Each narrowing surface can only constrain further; none can expand what an outer surface already permits.

Bounds use the same operator system everywhere — `.cmp` per bound with `>=`/`>` / `<=`/`<` validity rules (call-site kwargs always inclusive) — so intersecting them is purely a numeric exercise on the resolver side.

---

<a id="see-also"></a>
## See also

- [Versioning index](index.md) — slim hub with cross-references.
- [Semver](semver.md) — per-UNS semver narrowing, and the canonical reference for the bound-operator system (`.min` / `.max` / `.cmp`) reused on this page.
- [Puck-lookup per-call narrowing](../puck-lookup.md#per-call-narrowing) — `ts_min` / `ts_max` kwargs on the lookup itself; the most local of the three constraint surfaces.
- [Blockchain registry](../downloads/service/blockchain/) — where `effective_date` and `posted` are defined.

---

<a id="open-questions"></a>
## Open questions

- **Era + semver?**: this surface only narrows by timestamp. Is there a parallel `%puck`-wide *semver* narrowing surface, or is semver constraint strictly per-UNS? If global semver narrowing is wanted, `%puck.era` may not be the right name (it implies time only).
- **`confine` across role boundaries**: block-scoped eras don't cross role boundaries. Does `confine` follow the same rule, or behave differently because it installs the era as the active `%puck`?
- **Era equality and reuse**: are two `%puck.era` calls with the same bounds the same era, or distinct handles? Affects whether eras can be cached, shared, compared.
