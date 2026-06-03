# `%engine.require`

~~~json
{"vibecode": {
	"doc": "engine_require",
	"role": "spec for the %engine.require method — a declarative way for user code to say 'this program uses this library', which primes the library cache (when caching is allowed) and adds the library to the manifest. Does NOT change how libraries are accessed; access stays via %[uns].",
	"audience": "Caspian programmers writing user-role code that wants explicit, manifest-visible library dependencies and cache priming",
	"key_concepts": ["declarative_library_use", "cache_priming", "manifest_visibility",
		"access_unchanged_use_remains_via_puck_lookup", "calling_it_is_optional"]
}}
~~~

`%engine.require 'uns'` declares that the program uses a library identified by its [UNS](../uns.md). It is a [standard slot method on `%engine`](index.md#standard-slots), and like every engine surface, [user-role-only](index.md#user-only).

```
%engine.require 'foo.com/bar'
```

## What it does — and what it doesn't

`%engine.require` does exactly **two things**:

1. **Ensures the library is cached.** If [caching is allowed](#caching) for this library, the cache is primed — fetched if not already present — so first use doesn't take a remote round-trip. If caching is denied, this step is silently skipped (the call doesn't fail; the manifest declaration below still happens).
2. **Adds the library to [`%engine.manifest`](manifest.md).** The library appears under `caspian.libs` keyed by its UNS, with the standard per-entry fields (`version`, `timestamp`, etc.). This makes the program's declared dependencies discoverable from manifest output.

That's it. **`%engine.require` is not how libraries get used.** Access to remote objects is always via the [puck-lookup shortform](../../mikobase/puck-lookup.md):

```
$result = %['foo.com/bar'].some_method(...)
```

You can call `%['foo.com/bar']` whether or not you ever `require`'d it. Requiring doesn't unlock anything; not requiring doesn't block anything. Calling `%engine.require` is **optional**.

## Why call it

Two reasons, matching the two effects:

- **Cache priming.** You know up front the program will use `foo.com/bar`; warming the cache at startup means the first real call doesn't pay the fetch latency. Useful for interactive code, latency-sensitive paths, or programs that want predictable startup behavior.
- **Manifest visibility.** Required libraries appear in [`%engine.manifest`](manifest.md), giving operations, audits, and downstream tooling a clean view of what the program declared as its dependencies. Without `%engine.require`, libraries only show up in the manifest after first actual use — manifest output then reflects what was used by the time of the call rather than what the program intends to use.

If neither of those matters for your program, don't bother calling `%engine.require`. The puck-lookup pattern works equally well without it.

<a id="caching"></a>
## Caching is allow-or-deny per library

Whether the cache step actually runs is governed by the **engine's library cache policy** plus per-library configuration. Some libraries are inherently uncacheable (live data sources, randomness providers, anything with side effects on every fetch); some hosts run with caching disabled entirely; some libraries opt out via their own metadata.

`%engine.require` respects whatever the cache policy says. When caching is denied for a library, the require call still succeeds — it just skips the cache step and proceeds to the manifest registration. The library is still usable; first call just goes remote as it would have anyway.

The cache-policy mechanism itself lives elsewhere (libraries are cached, not installed — see the [overview](../../overview.md) on the caching model). `%engine.require` doesn't add policy; it consults whatever policy already applies.

## See also

- [`%engine`](index.md) — the parent surface and the role/security rules.
- [`%engine.manifest`](manifest.md) — where required libraries become visible. The `caspian.libs` section is the relevant slice.
- [Puck-lookup shortform `%[uns]`](../../mikobase/puck-lookup.md) — the actual way library functionality gets used.
