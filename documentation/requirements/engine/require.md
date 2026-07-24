# `%engine.require`
<!--index: 9 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_require",
	"role": "spec for %engine.require — declarative library-dependency statement. Primes the library cache and adds the library to %engine.manifest; does NOT change how libraries are used (access stays via %(url))",
	"calling_optional": true
}}
~~~

`%engine.require 'url'` says: this program uses the library at `url`. It's a **declarative** statement — the program is telling the engine "I depend on this," not actually loading the library through `require`. Calling `%engine.require` is optional; libraries can also be loaded purely on demand the first time they're referenced via `%(url)`.

When called, `%engine.require` does two things:

1. **Primes the library cache** (when caching is allowed for that URL). The engine resolves the URL and fetches the library now, instead of waiting for the first `%(url)` reference. Subsequent uses hit the cache.

2. **Adds the object to [`%engine.manifest`](manifest).** The object appears under `downloads` keyed by its URL, as an array of download entries with the standard per-entry fields (`version`, `fetched_at`, `bytes`, `sha256`, `via`) documented in [manifest § downloads](https://puck.uno/documentation/requirements/engine/manifest/#downloads). This makes the program's declared dependencies discoverable from manifest output — useful for audits, supply-chain tooling, and operations.

Access to the loaded library still happens through `%(url)`, the same as if the program had never called `%engine.require`. The declarative form is purely about pre-fetch + manifest registration.

## When to call it

Call `%engine.require` near the top of a program for any library the program intends to use. Calling it produces clean manifest output and avoids first-use latency for the library. Skipping the call works too — the library loads on first reference, and shows up in the manifest once it has been used.

## Version constraints

`%engine.require` may grow keyword arguments for version pinning, timestamp constraints, and similar controls. That part of the spec is still settling.

## Testing

- **`%engine.require 'url'` returns null** — the declarative form has no meaningful return value.
- **After `%engine.require 'url'`, the URL appears in `%engine.manifest.downloads`** — keyed by the URL, as an array with at least one entry.
- **`%engine.require` primes the cache when caching is allowed** — a subsequent `%(url)` reference does not trigger a second fetch.
- **`%engine.require` is optional** — a program that never calls it can still use `%(url)` and the object loads on first reference.
- **A library used only via `%(url)` still appears in `%engine.manifest.downloads` after first use** — manifest population happens on fetch, regardless of trigger path.
- **Multiple `%engine.require` calls for the same URL do not duplicate download entries** — the URL's array length stays at `1` after two calls.
- **`%engine.require` for an unresolvable URL raises at the call site** — failure surfaces at the require call, not deferred to first use.
- **`%engine.require` raises on a fetch that produces a 404** — surfaces the HTTP error at the require call.
- **`%engine.require` raises on network failure (DNS, connection refused, TLS mismatch)** — the underlying fetch error propagates.
- **Non-user role calling `%engine.require` raises** — the blanket `%engine` gate.
- **`%engine.require` at the top level is the intended call site** — nothing enforces this position in V1.
- **Downloaded libraries cannot call `%engine.require`** — non-user roles don't reach `%engine` at all.
- **Manifest entry from `%engine.require` includes `sha256`** — standard per-entry field.
- **Manifest entry from `%engine.require` includes `bytes`** — payload size.
- **Manifest entry from `%engine.require` includes `fetched_at`** — timestamp.
- **A previously-cached URL requires without a fresh network fetch** — cache hit; manifest still records the entry.
- **`%engine.require` with a cache-disallowed URL fetches but does not cache** — fetch is performed; cache priming is skipped.
- **Access to the required library is via `%(url)`** — `%engine.require` doesn't return the library itself.
- **`%engine.require` with an empty-string URL raises** — validation error.
- **`%engine.require` with a null URL raises** — validation error.
- **Downloaded objects tied to a `%engine.require`'d URL are role-tagged with the downloads faucet role** — provenance is preserved.
- **A required URL and a subsequently `%(url)`-referenced URL share one manifest entry** — one fetch total.
