# `%puck[url]` — puck lookup

*Fetching a remote object by URL, with per-call version constraints.*

~~~vibecode
{"vibecode": {
	"doc": "puck_lookup",
	"role": "spec for the %puck[url] syntax — how user code fetches a remote object by URL (with bare 'foo.bar/path' as shorthand for 'https://foo.bar/path'), and how per-call kwargs narrow which version is selected for this one call",
	"audience": "Caspian programmers using remote objects",
	"key_concepts": ["puck_lookup", "url_as_primary_address",
		"bare_form_is_url_protocol_shorthand", "per_call_version_narrowing",
		"flat_kwargs_for_call_site", "intersects_with_era_and_library_config"]
}}
~~~

`%puck['https://foo.bar/gup']` fetches the remote object at the URL `foo.bar/gup`. The bare form (`foo.bar/gup`) is shorthand for `https://foo.bar/gup` — the protocol is elided for readability. The result is the resolved object — usually a class you then instantiate, or a value you read or call directly. Version selection follows whatever constraints are in scope.

```
$instance = %puck['https://foo.bar/gup'].new(...)
```

This is the **canonical call site** for resolving any URL-addressed library. Most Caspian programs do nothing else — global constraint surfaces fill in version selection, and the call site just asks for the library by URL.

<a id="per-call-narrowing"></a>
## Per-call version narrowing

When you want to constrain version selection for **one specific call** — without affecting other lookups in scope — pass version constraints as keyword arguments to the lookup:

```
%puck['https://foo.bar/gup', ts_max: '2023-08-12']                          # only versions on or before this date
%puck['https://foo.bar/gup', ts_min: '2023-08-12', ts_max: '2023-09-01']    # date range
%puck['https://foo.bar/gup', semver_min: '1.3']                             # 1.3 or higher
%puck['https://foo.bar/gup', semver_min: '1.3', semver_max: '2.0']          # semver range
%puck['https://foo.bar/gup', semver_min: '1.3', ts_max: '2023-08-12']       # both axes
```

This is the **most local** of the constraint surfaces — it narrows exactly one call, and goes away the moment that call returns. The broader surfaces — [`%puck.era`](../versioning/timestamp.md) (global timestamp), [`%puck.config(uns).timestamp`](../versioning/timestamp.md#per-url-timestamp) (per-UNS timestamp), and [`%puck.config(uns).semver`](../versioning/semver.md) (per-UNS semver) — apply more broadly (block-scoped or live-global respectively). All intersect at lookup time; per-call kwargs narrow further within whatever the broader surfaces already permit.

### Recognised kwargs

| Kwarg | Constrains | Example |
|---|---|---|
| `ts_min` | Lower bound on `effective_date` (falls back to `posted`). Inclusive. | `ts_min: '2023-08-12'` |
| `ts_max` | Upper bound on `effective_date`. Inclusive. | `ts_max: '2023-09-01'` |
| `semver_min` | Lower bound on the artifact's `semver` field. Inclusive. | `semver_min: '1.3'` |
| `semver_max` | Upper bound on the artifact's `semver` field. Inclusive. | `semver_max: '2.0'` |

Set any subset — give just `ts_max` for a date cap, both `semver_min`/`semver_max` for a semver range, or combine semver and timestamp on the same call. Bounds you don't set stay unbounded (or fall through to whatever the broader era / per-UNS surfaces already established).

### Inclusivity

Call-site bounds are **always inclusive** (`>=` for `_min`, `<=` for `_max`). The exclusive-bound machinery from the per-UNS config (`.cmp`) doesn't surface here — the call site is meant to be terse. If you need an exclusive bound for one specific call, either:

- Bump the bound value to the next valid value yourself (`semver_max: '2.0'` instead of `< '2.1'`); or
- Set the constraint on `%puck.config(uns)` where the full `.cmp` surface is available.

### Why flat kwargs (and not a nested shape)?

The per-UNS config and era surfaces use a nested polymorphic shape (`.semver = '1.3'` for pin, `.semver = {min, max}` for range). The call site uses flat kwargs (`semver_min:`, `semver_max:`) instead.

The divergence is deliberate: at a call site, kwargs are flat by language convention (you write `kw: value, kw2: value2`, not `nested: {kw: value}`). Flattening the constraint axes matches that grain. The cost — slightly more typing for ranges, and a per-surface naming difference for the same concept — is judged worth it for call-site readability.

## Composition with the broader surfaces

All constraint surfaces intersect at lookup time:

| Surface | Axis | Scope | Where documented |
|---|---|---|---|
| Per-call kwargs (this page) | both | One call | This page |
| [`%puck.config(url).semver`](../versioning/semver.md) | semver | One URL, live-global | versioning/semver.md |
| [`%puck.config(url).timestamp`](../versioning/timestamp.md#per-url-timestamp) | timestamp | One URL, live-global | versioning/timestamp.md |
| [`%puck.era`](../versioning/timestamp.md) | timestamp | Block-scoped or handle, all URLs | versioning/timestamp.md |

A lookup succeeds if there exists a candidate satisfying every active constraint from every surface. If the intersection is empty for a given URL, the lookup raises `puck.uno/error/out_of_range`.

Per-call kwargs **never expand** what the broader surfaces permit — they can only narrow further.

## See also

- [Versioning index](../versioning/index.md) — overview of the date-pinning model and all constraint surfaces.
- [`%puck.era`](../versioning/timestamp.md) — block-scoped or handle-based global timestamp narrowing.
- [`%puck.config(uns).semver`](../versioning/semver.md) — live-global per-UNS semver narrowing; canonical reference for the `.min` / `.max` / `.cmp` bound-operator system.
- [`%puck.config(uns).timestamp`](../versioning/timestamp.md#per-url-timestamp) — live-global per-UNS timestamp narrowing.
- [Blockchain registry](../downloads/blockchain/) — defines `posted`, `effective_date`, and `semver` on each published artifact.
