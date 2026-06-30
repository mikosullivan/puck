# `%engine.require`
<!--index: 9 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_require",
	"role": "spec for %engine.require — declarative library-dependency statement. Primes the library cache and adds the library to %engine.manifest; does NOT change how libraries are used (access stays via %[url])",
	"calling_optional": true
}}
~~~

`%engine.require 'url'` says: this program uses the library at `url`. It's a **declarative** statement — the program is telling the engine "I depend on this," not actually loading the library through `require`. Calling `%engine.require` is optional; libraries can also be loaded purely on demand the first time they're referenced via `%[url]`.

When called, `%engine.require` does two things:

1. **Primes the library cache** (when caching is allowed for that URL). The engine resolves the URL and fetches the library now, instead of waiting for the first `%[url]` reference. Subsequent uses hit the cache.

2. **Adds the library to [`%engine.manifest`](manifest).** The library appears under `caspian.libs` keyed by its URL, with the standard per-entry fields (`version`, `timestamp`, etc.). This makes the program's declared dependencies discoverable from manifest output — useful for audits, supply-chain tooling, and operations.

Access to the loaded library still happens through `%[url]`, the same as if the program had never called `%engine.require`. The declarative form is purely about pre-fetch + manifest registration.

## When to call it

Call `%engine.require` near the top of a program for any library the program intends to use. Calling it produces clean manifest output and avoids first-use latency for the library. Skipping the call works too — the library loads on first reference, and shows up in the manifest once it has been used.

## Version constraints

`%engine.require` may grow keyword arguments for version pinning, timestamp constraints, and similar controls. That part of the spec is still settling.
