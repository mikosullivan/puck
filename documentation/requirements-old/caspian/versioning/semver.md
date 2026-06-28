# Semver

*Per-URL semver constraints via `%puck.config(url).semver`.*

~~~vibecode
{"vibecode": {
	"doc": "semver_per_url_constraints",
	"role": "canonical reference for Caspian's semver constraint surface — how user code narrows one specific library's version selection by semver via %puck.config(url).semver. Also the canonical home for the bound-operator system (.min/.max/.cmp) that timestamp narrowing reuses.",
	"audience": "Caspian programmers writing user-role code that needs semver-based library narrowing, plus authors of any constraint surface needing the canonical bound-operator reference",
	"key_concepts": ["per_url_semver_constraints", "puck_config_url_returns_live_handle",
		"dual_path_assign_or_tweak", "autovivified_bounds",
		"cmp_per_bound_for_inclusive_or_exclusive",
		"bare_partial_version_is_pin",
		"intersects_with_timestamp_surfaces"]
}}
~~~

`%puck.config(url).semver` constrains one specific library's version selection by [semver](../downloads/service/blockchain/index.md#authority-blocks-1). It composes with the timestamp surfaces ([`%puck.era`](timestamp.md), [per-URL timestamp narrowing](timestamp.md#per-url-timestamp), [per-call kwargs](../puck/lookup.md#per-call-narrowing)) by intersection: all active constraints must be satisfied at lookup time.

```
$config = %puck.config('foo.bar/gup')
$config.semver = '1.3'                  # pin
```

Per-URL semver narrowing is **opt-in**. A URL with no semver constraint in scope resolves under whatever timestamp narrowing is active, with semver ignored — same behavior as before this surface existed. Calling `%puck.config` doesn't change resolution by itself; only setting `.semver` properties on the returned config does.

A published library **may** declare a semver string like `2.1.45`. The field is optional on publish; libraries without it work fine and date-pinning resolves them on its own. The semver surface filters on libraries that do carry the field.

---

## The config object is a live handle, not a snapshot

`%puck.config(url)` returns a **handle to the live global config** for that URL. Setting a property on the returned object takes effect immediately on the underlying global state — there is no `.save()` or `.commit()` step. Two calls to `%puck.config('foo.bar/gup')` return handles into the same underlying state; mutations through either are visible through both.

The `$config` variable in the examples is purely a convenience — it saves you typing the URL again across several lines. You can keep the handle or throw it away; the state lives on the global config, not on the variable.

```
%puck.config('foo.bar/gup').semver.max = '2.8'    # one-liner: no variable needed
```

```
$config = %puck.config('foo.bar/gup')             # convenience handle
$config.semver = '1.3'                            # both lines mutate the same
$config.semver.max = '2.8'                        # global state for foo.bar/gup
```

There is no "reset to defaults" implied by calling `%puck.config` — you get the current state of the library's config, whatever it is. Resetting properties is its own operation (TBD: shape of "unset" / "clear" surface).

The same live-handle semantics apply on the timestamp axis ([per-URL timestamp narrowing](timestamp.md#per-url-timestamp)) — same config object, different axis.

---

## Two paths for setting constraints

The same dual-path applies at every level: **assign-the-whole-thing** for the common case, **tweak-a-property** for fine-grained control. Both surfaces produce identical state; pick whichever reads best at the call site.

```
# Pin (assign-the-whole-thing)
$config.semver = '1.3'                          # min = max = '1.3', both inclusive

# Range, common case (assign a hash)
$config.semver = {min: '1.3', max: '2.8'}       # both inclusive

# Tweak individual bounds (no init required)
$config.semver.max = '2.8'                      # max value set; min stays unbounded
$config.semver.min = '1.3'                      # min set; max stays at whatever it was

# Tweak the operator on a bound
$config.semver.max.cmp = '<'                    # exclusive upper: strictly less than
$config.semver.min.cmp = '>'                    # exclusive lower: strictly greater than
```

`.min` and `.max` are **autovivified** — reaching into either is enough; you don't have to assign the parent first. Default state for both bounds is *unbounded*.

---

## Bound operators (`cmp`)

Each bound carries both a value and a `cmp` operator that controls inclusivity. Defaults are inclusive; valid operators depend on which bound:

| Property | Default | Valid values |
|---|---|---|
| `.max.cmp` | `'<='` | `'<'`, `'<='` |
| `.min.cmp` | `'>='` | `'>'`, `'>='` |

Setting an operator outside the valid set for its bound (e.g. `.max.cmp = '>'`) raises immediately.

This bound-operator system is **shared with timestamp narrowing** — `%puck.era`, per-URL timestamp constraints, and per-call kwargs (except call-site kwargs are always inclusive). [Timestamp versioning](timestamp.md) cross-references this section as the canonical reference rather than re-spec'ing it.

---

## Bare partial versions

A bare semver value like `'1.3'` (without a third component) is interpreted as **exact pin**: `min = max = '1.3'`, both inclusive. This is the simplest reading and avoids importing ecosystem-specific defaults (npm's "next-minor", Cargo's "caret-equivalent", etc.). To express a family-match, use an explicit range:

```
$config.semver = {min: '1.3', max: '1.3'}       # exactly 1.3 — same as pin
$config.semver = {min: '1.3', max: '2.0'}       # 1.3 through 2.0
$config.semver.min = '1.3'                      # 1.3 and up, no upper limit
```

---

## Resolution and tie-break

When a semver constraint is active, the resolver picks the **highest semver satisfying every active constraint** from the candidate set that also satisfies any active timestamp constraints. If two artifacts share a URL and date but differ in semver, the highest-satisfying semver wins.

Only publications that **carry a semver** are eligible when any semver constraint is set — publications without the `semver` field are excluded from the candidate set in that case. With no semver constraint in scope, semver is ignored entirely and date-pinning alone selects the version.

---

## Composition with timestamp surfaces

Semver narrowing **intersects** with whatever timestamp narrowing is active. The resolver must find a candidate that satisfies every constraint from every surface:

| Surface | Scope |
|---|---|
| `%puck.config(url).semver` (this page) | One URL, live-global |
| [`%puck.era`](timestamp.md) | Block-scoped or handle, every lookup |
| [`%puck.config(url).timestamp`](timestamp.md#per-url-timestamp) | One URL, live-global |
| [Per-call kwargs](../puck/lookup.md#per-call-narrowing) | One call |

If the intersection is empty for a given URL — no published version satisfies every active constraint — the lookup raises [`puck.uno/error/out_of_range`](timestamp.md#out-of-range-alarm), the same alarm timestamp narrowing raises on its own. The forensic payload identifies which constraint(s) ruled out which candidates.

**There is no `%puck`-wide semver narrowing surface.** `%puck.era` narrows by date only; semver narrowing across many URLs is set per-URL or per-call. If global semver narrowing is ever wanted, it would need a new surface (see [Open questions](#open-questions)).

**The date is still the lockfile by default.** When no semver constraint is in scope, date-pinning fully determines the version selected. Semver constraints **narrow further** within whatever the date window already permits — they don't replace it. Compatibility communication lives mostly in the publisher's discipline — a library author signalling a breaking change publishes documentation and a clear semver bump. The runtime lets consumers pin or range-bound to that semver if they want; it does not require them to.

---

## See also

- [Versioning index](index.md) — slim hub with cross-references.
- [Timestamp versioning](timestamp.md) — `%puck.era` (global), per-URL timestamp narrowing, date-pinning rationale, out-of-range alarm, resolution rules.
- [Puck-lookup shortform `%[url]`](../puck/lookup.md) — the actual call site where these constraints take effect, plus the flat-kwarg per-call narrowing surface.
- [Blockchain registry](../downloads/service/blockchain/) — where the on-chain `semver`, `effective_date`, and `posted` fields are defined.

---

## Open questions

- **Divergence from `%puck.era`'s scoping**: both surfaces live on `%puck`, but they scope differently. `%puck.config` is imperative and writes to live global state for the URL; `%puck.era` is block-scoped and doesn't cross role boundaries. The divergence is intentional (per-URL config is "set once for this program," era is "narrow only this region"), but the asymmetry should be documented prominently somewhere — and the question of how per-URL config behaves across role boundaries needs answering before V1 ships.
- **"Unset" / "clear" surface**: how does user code reset a property — `$config.semver = nil`, `$config.semver.clear()`, `%puck.config.reset('url')`? Not yet decided.
- **Validation timing**: bound-operator validation (`.max.cmp = '>'`) raises immediately; should value-shape validation (semver parse error) be immediate too, or deferred to lookup?
- **A global semver narrowing surface?**: currently semver narrowing is per-URL or per-call only. Whether `%puck`-wide semver narrowing is wanted at all (and what it would be called, since `%puck.era` is timestamp-only) is open.
