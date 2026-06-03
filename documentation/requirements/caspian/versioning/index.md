# Versioning

~~~json
{"vibecode": {
	"doc": "versioning_hub",
	"role": "slim hub for Caspian's library versioning model — points readers at the three constraint surfaces (per-call, per-UNS, era) and at the deep dives that cover the date-pinning model, semver, blockchain anchoring, and the lookup/alarm machinery",
	"audience": "Caspian programmers landing on the versioning area for the first time",
	"key_concepts": ["date_pinned_primary", "semver_also_selectable",
		"three_constraint_surfaces_per_call_per_uns_era",
		"deep_dives_live_in_topic_pages"]
}}
~~~

In Puck, libraries are primarily versioned **by date** — a single timestamp can govern the entire library tree, set once at the top of the call chain. Every library lookup down the stack inherits it. This eliminates per-library version manifests, lockfiles, and constraint-resolver complexity. The same date plus the same source code produces the same library tree, every time.

Semantic versions (`1.2.45`, `2.0.0`, etc.) are also selectable: they live on every published artifact (see [blockchain.md](../downloads/service/blockchain/index.md)) and any of the version-constraint surfaces can filter by them.

---

<a id="quick-example"></a>
## A quick example

The most direct way to constrain a library version is at the **call site itself**, passing kwargs to the [puck-lookup shortform](../../mikobase/puck-lookup.md#per-call-narrowing):

```caspian
$gup = %puck['foo.bar/gup', ts_max: '2023-08-12']                   # only versions on or before that date
$gup = %puck['foo.bar/gup', semver_min: '1.3']                      # 1.3 or higher
$gup = %puck['foo.bar/gup', semver_min: '1.3', semver_max: '2.0']   # semver range
$gup = %puck['foo.bar/gup', semver_min: '1.3', ts_max: '2023-08-12'] # both axes
```

This is the most local form — narrows exactly one call. For broader narrowing, several surfaces are available: block-scoped or handle-based via [`%puck.era`](timestamp.md), live-global per-UNS via [`%puck.config(uns).timestamp`](timestamp.md#per-uns-timestamp) and [`%puck.config(uns).semver`](semver.md). They all intersect at lookup time; the call-site kwargs narrow further within whatever the broader surfaces already allow.

---

<a id="where-the-details-live"></a>
## Where the details live

| Page | Covers |
|---|---|
| [Timestamp versioning](timestamp.md) | The `%puck.era` global surface (block form, era handle, `confine`), per-UNS timestamp narrowing via `%puck.config(uns).timestamp`, the date-pinning rationale, the resolution rules, the out-of-range alarm, the relationship to the blockchain, what this model replaces. The canonical reference for date-based versioning. |
| [Puck-lookup shortform](../../mikobase/puck-lookup.md) | The `%puck[uns]` call site itself, including the flat-kwarg per-call narrowing (`ts_min`, `ts_max`, `semver_min`, `semver_max`). |
| [Semver](semver.md) | The per-UNS semver constraint surface (`%puck.config(uns).semver`). Also the canonical home for the bound-operator system (`.min`, `.max`, `.cmp`) that timestamp narrowing reuses. |

The three pages are peer surfaces; each defines its own scope (one call, one UNS, every lookup in a block) but they share the same underlying model. All surfaces intersect at lookup time, and out-of-range failure fires the same alarm in every case.
