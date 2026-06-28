# `require`

> ⚠ **Tentative spec — review required before implementation.** The version-constraint kwargs ([semver:](#version-constraints), [timestamp:](#version-constraints), etc.), the [inheritance/role-scope model](#version-constraints) for how nested libraries' constraints flow, and the [`%engine.remote_downloads = false`](#disabling-remote-downloads) closed-world mechanism are all design proposals from this session — exact syntax, exception class names, and per-scope vs per-program version selection are open. The cache-priming and manifest-visibility behaviors are settled; everything around version control and remote-download lockdown needs further design review before deployment.

~~~vibecode
{"vibecode": {
	"doc": "require",
	"role": "spec for the require statement — declares that the program uses a library at a URL, with optional version constraints. Primes the library cache, adds the library to the manifest, and binds the version range that all uses (including transitive uses by nested libraries) must respect.",
	"status": "TENTATIVE — version-constraint kwargs, inheritance model, and disable-remote-downloads mechanism need further design review; cache-priming and manifest-visibility behaviors are settled",
	"audience": "Caspian programmers writing user-role code that wants explicit, manifest-visible library dependencies, cache priming, and per-library version control",
	"key_concepts": ["declarative_library_use_by_url",
		"optional_version_constraint_kwargs",
		"semver_and_timestamp_constraints",
		"nested_library_violations_raise",
		"cache_priming_and_manifest_visibility",
		"access_unchanged_use_remains_via_puck_lookup"]
}}
~~~

**Most programs don't need per-library version control.** A single program-wide timestamp pin handles almost every "I want reproducible behavior" case:

```
%puck.timestamp_min = '2027-01-01T00:00:00Z'   # only libraries published on or after this date
%puck.timestamp_max = '2027-06-30T23:59:59Z'   # only libraries published on or before this date
%puck.timestamp     = '2027-06-30T23:59:59Z'   # shorthand for timestamp_max (the common case)
```

Setting `%puck.timestamp` once at the top of a script pins every library reference — direct and transitive — to versions that existed at that point in time. No per-library `require` constraints needed; the whole library tree freezes to a coherent moment.

**Use per-library `require` constraints only when the program-wide timestamp pin isn't enough** — typically when you need to mix old and new libraries (one pinned to a specific semver, others free to track the timestamp), or when you need to lock to a semver-named release independent of when it was published. For the common reproducibility case, just set `%puck.timestamp` and skip everything below.

---

`require 'url'` declares that the calling code uses a library located at the given URL. The bare form `'foo.com/bar'` is shorthand for `'https://foo.com/bar'` per the URL-as-address convention.

`require` is a **top-level language construct**, not a method on any system surface. **Any role can use it** — user code, nested libraries the program depends on, agent code invoked through `$agent.yield`, anything. Each role's `require` statements participate in the same constraint graph (per [Version constraints](#version-constraints) below); a nested library's `require` is just as real as the top-level program's, subject to the rules about narrowing vs relaxing constraints.

```
require 'foo.com/bar'
```

**`require` is NOT required to load libraries.** By default, Caspian downloads libraries dynamically as the program references them — `%['foo.com/bar']` works even if no `require` for that URL was ever called. A program with zero `require` statements still resolves library references on demand. Calling `require` is an opt-in for the three behaviors listed below ([cache priming, manifest visibility, version control](#what-it-does)); if none of those matter, skip it. See [Disabling remote downloads](#disabling-remote-downloads) below for how to flip the default off when you want a closed-world program.

---

## What it does

`require` does **three things**:

1. **Ensures the library is cached.** If [caching is allowed](#caching) for this library, the cache is primed — fetched if not already present — so first use doesn't take a remote round-trip. If caching is denied, this step is silently skipped.
2. **Adds the library to [`%engine.manifest`](manifest.md).** The library appears under `caspian.libs` keyed by its URL, with the standard per-entry fields (`version`, `timestamp`, etc.). Makes the program's declared dependencies discoverable from manifest output.
3. **Records any version constraints** the call supplied. Constraints apply to every use of the library — direct uses and transitive uses by libraries the program depends on. See [Version constraints](#version-constraints) below.

**`require` is not how libraries get used.** Access to remote objects is always via the [puck-lookup form](../puck/lookup.md):

```
$result = %['foo.com/bar'].some_method(...)
```

You can call `%['foo.com/bar']` whether or not you ever `require`'d it. Requiring doesn't unlock anything; not requiring doesn't block anything. **Calling `require` is optional** — unless you want to bind a version constraint, in which case it's the only way to express that.

---

## Version constraints

`require` accepts kwargs that constrain which version of the library may be used. When set, the constraint applies to every use of the library in the running program — including uses by libraries this program transitively depends on.

```
require 'foo.com/bar'                                 # no constraint, any version
require 'foo.com/bar', semver: '3.5.2'                # exact semver
require 'foo.com/bar', semver_min: '3.5.2'            # lower bound
require 'foo.com/bar', semver_max: '3.5.2'            # upper bound
require 'foo.com/bar', timestamp: '2027-08-10T12:00:00Z'      # exact timestamp
require 'foo.com/bar', timestamp_min: '2027-08-10T12:00:00Z'  # earliest
require 'foo.com/bar', timestamp_max: '2027-08-10T12:00:00Z'  # latest
```

**The kwargs:**

| Kwarg | Constraint |
|---|---|
| `semver:` | Exact semver match. Library version must equal this. |
| `semver_min:` | Library version must be ≥ this. |
| `semver_max:` | Library version must be ≤ this. |
| `timestamp:` | Library's published timestamp must equal this. |
| `timestamp_min:` | Library's published timestamp must be ≥ this. |
| `timestamp_max:` | Library's published timestamp must be ≤ this. |

Constraints compose by intersection. `require 'foo.com/bar', semver_min: '3.0', semver_max: '4.0'` accepts any version in the range `3.0 ≤ v ≤ 4.0`. `require 'foo.com/bar', semver_min: '3.5', timestamp_max: '2027-12-31T23:59:59Z'` requires version ≥ 3.5 AND published on or before 2027-12-31.

**Out-of-range versions raise.** If, during resolution, the engine encounters a version that violates an active constraint — either because user code called `%['foo.com/bar']` and the resolver finds nothing in range, or because a nested library declares its OWN `require 'foo.com/bar'` for a version outside this program's constraint — the engine raises an exception:

```
puck.uno/error/require/version_constraint
```

The exception's message names the URL, the active constraint, and the offending version. Stack-trace context shows which `require` set the constraint and which library's resolution triggered the violation.

**Nested-library handling.** When a library this program depends on has its own `require` statements, those operate within the parent's constraints. A nested library can NARROW the constraint (further restrict the version it'll accept), but it cannot relax it — its requirements intersect with the parent's, not replace them. If the intersection is empty, the nested library can't load and the engine raises.

**Constraint resolution order.** Per-program `require` constraints intersect with broader scoping mechanisms — [`%puck.era`](../versioning/timestamp.md) (tree-wide timestamp pinning) and the [per-call kwargs on the puck-lookup form](../puck/lookup.md#per-call-narrowing). The most restrictive wins for any given lookup. If the union of constraints produces an empty range, resolution raises `puck.uno/error/require/version_constraint`.

## Disabling remote downloads

By default, Caspian fetches libraries from the network when the program references a URL that isn't in the local cache. For programs that want a **closed-world model** — only libraries already cached at startup may be used, no surprise network reaches mid-execution — there's a convenience shortcut for removing network-bound fetchers from the [puck fetcher chain](../downloads/).

**Syntax is not yet settled.** A working sketch:

```
%engine.remote_downloads = false
```

**Under the hood, this is just a shortcut.** Caspian resolves library URLs by walking the puck fetcher chain — each fetcher tries to resolve the URL; the first one that succeeds returns the library. Some fetchers are local (read from the on-disk cache, the local filesystem, etc.); others are remote (download via HTTPS, fetch from a Git repo, etc.). Setting `%engine.remote_downloads = false` **removes (or disables) every fetcher in the chain that would require a network download**. After the shortcut runs, only local fetchers remain in the chain.

The same effect can be achieved by manipulating the fetcher chain directly:

```
# (sketched — fetcher-chain API still settling)
%puck.fetchers.remove_remote
```

Either form lands the program in the same closed-world state.

**Resolution behavior after the shortcut.** A library reference proceeds through the chain as it always does. If a local fetcher resolves it (the library is cached, or the local-filesystem fetcher finds it), the program uses it. If no local fetcher can resolve it, the chain is exhausted and the engine raises the **standard library-not-found error** — there's no special "remote downloads disabled" exception class to introduce; the absence of any network-bound fetcher in the chain produces a natural "library not found" failure with whatever exception the puck-lookup path normally raises.

**Use cases:**

- Production hardening: lock the library set to exactly what was reviewed; surface attempts to reach new code as the same not-found error the user gets for any other unresolvable URL.
- Reproducibility: when combined with `require` constraints (or a `%puck.timestamp` pin), the closed-world setting forces the program to run on the exact library set the developer expected, with no drift from upstream changes after the cache snapshot.
- Air-gapped or restricted environments: programs that must run without network access. Closes the door directly rather than relying on a host-level firewall.

**Interaction with `require`.** A `require` call made after the shortcut behaves the same as any other library reference — it succeeds if a local fetcher can resolve it, and raises (with the standard not-found error) if not. The shortcut doesn't change `require`'s semantics; it just changes what fetchers are in the chain.

**Implicit-but-cached uses still work.** The closed-world setting removes only the network-bound fetchers; libraries reachable via local fetchers (already-cached entries, local filesystem references, anything else local) remain usable. The local fetchers don't change behavior; they just become the ONLY fetchers available.

**Irreversible.** Once the shortcut runs, the network-bound fetchers are gone for the rest of the program's lifetime — there's no language-level API to put them back. Even though the underlying mechanism (fetcher-chain manipulation) is technically reversible, exposing the reverse would defeat the security posture: an attacker who reached `%engine.remote_downloads` could re-enable downloads after the program thought it had locked them out. Treating the shortcut as one-way makes the security property easy to reason about — "if this line ran, downloads are off for the rest of the run."

**Open design points** (to settle when the syntax lands):

- Exact syntactic form (property assignment vs method call vs fetcher-chain manipulation).
- Whether to expose a development-mode "warn but allow" variant.
- Whether `%engine.remote_downloads = false` is settable at startup-time only (a flag on the launcher) AND/OR mid-run.

---

## Why call it

Three reasons, matching the three effects:

- **Cache priming.** You know up front the program will use `foo.com/bar`; warming the cache at startup means the first real call doesn't pay the fetch latency. Useful for interactive code, latency-sensitive paths, or programs that want predictable startup behavior.
- **Manifest visibility.** Required libraries appear in [`%engine.manifest`](manifest.md), giving operations, audits, and downstream tooling a clean view of what the program declared as its dependencies. Without `require`, libraries only show up in the manifest after first actual use — manifest output then reflects what was used by the time of the call rather than what the program intends to use.
- **Version control.** Without `require`, library resolution accepts whatever version the resolver picks (subject to broader scoping like `%puck.era`). A `require` call with `semver:`/`timestamp:`/etc. kwargs locks the library to a specific version or range, including for transitive uses by nested libraries. The only way to express per-library version constraints is via `require`.

If none of these matter for your program, don't call `require`. The puck-lookup pattern works equally well without it.

## Caching is allow-or-deny per library

Whether the cache step actually runs is governed by the **engine's library cache policy** plus per-library configuration. Some libraries are inherently uncacheable (live data sources, randomness providers, anything with side effects on every fetch); some hosts run with caching disabled entirely; some libraries opt out via their own metadata.

`require` respects whatever the cache policy says. When caching is denied for a library, the require call still succeeds — it just skips the cache step and proceeds to the manifest registration and constraint recording. The library is still usable; first call just goes remote as it would have anyway.

The cache-policy mechanism itself lives elsewhere (libraries are cached, not installed — see the [overview](../../overview.md) on the caching model). `require` doesn't add policy; it consults whatever policy already applies.

## See also

- [`%engine`](index.md) — the parent surface and the role/security rules.
- [`%engine.manifest`](manifest.md) — where required libraries become visible. The `caspian.libs` section is the relevant slice.
- [Puck-lookup form `%[url]`](../puck/lookup.md) — the actual way library functionality gets used; also supports per-call version-narrowing kwargs.
- [`%puck.timestamp`, `%puck.timestamp_min`, `%puck.timestamp_max`](../versioning/timestamp.md) — program-wide timestamp pinning. The simpler lever; covers most reproducibility cases without needing per-library `require` constraints. Composes with `require`'s per-library constraints.
- [CLI `--update-cache` / `--clear-cache`](../cli.md#flag-form) — admin actions on the cache that affect what's available when `require` runs.
- [Disabling remote downloads](#disabling-remote-downloads) — the engine-level setting (syntax TBD) that flips the default from "fetch on demand" to "cache-only" for closed-world execution.
