# `%fetch`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_fetch",
	"role": "spec for %fetch — the transient companion to %import. Downloads a source file (or serialized object), runs its top-level once, and returns whatever the top level evaluates to. The returned value is NOT stored in the load registry; every call runs the top level fresh and returns a new object. Use for one-shot loads where identity preservation isn't wanted and memory shouldn't be pinned. Byte cache still applies (source download is cached); only the top-level execution is fresh per call."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%fetch`.

`%fetch` is the transient URL-loading operator. Where `%import(url)` runs the top level once per process and caches the result (see [`%import`](import)), `%fetch(url)` runs the top level **on every call** and does not cache. Each call returns a **fresh object**. Two `%fetch('url')` calls return two independent values.

User-facing background: [documentation/fetch](https://puck.uno/documentation/fetch) covers when to use `%fetch` vs `%import`.

## What runs at fetch time

Fetching a source file runs its **top-level code once per call** — enough to evaluate what the file returns. **Method bodies do NOT run at fetch time.** They execute only when their method is called. If a method needs another object, that method's body calls `%fetch(...)` or `%import(...)` — the dependency load happens then, not at the original fetch.

The same "top-level should be a declaration" contract applies (see [`%import` § What runs at import time](import#what-runs-at-import-time)) but is much less painful under `%fetch`: since nothing is cached, a top level that produces a fresh UUID gives you a fresh UUID every call — not the silently-cached bug you'd get under `%import`. Even so, top-level-as-a-declaration is the idiomatic shape; use a callable if you want dynamic behavior per invocation.

## Entry points

| Surface | Purpose |
|---|---|
| `%fetch(url)` | Fetch the source at `url`, run its top level, return the value. No caching; every call runs the top level again. Long form; not commonly shortened since the transient case is the rare one. |
| `%fetch(url, opts?)` | Options form. Accepts `as_self: true` and future options. |

## Relationship to `%import`

The two operators serve distinct intents at the call site:

- `%import(url)` — permanent load, cached in the process's load registry, identity preserved across calls. Almost always what you want.
- `%fetch(url)` — transient load, no caching, fresh object per call. Use for one-shot heavy libraries, large data loads, cases where pinning the loaded value would waste memory.

Both use the same fetcher array ([fetch-discovery](https://puck.uno/requirements/fetch-discovery)) and the same byte cache ([cache-dir](https://puck.uno/requirements/cache-dir)). The difference is what happens to the top-level execution's return value:

- `%import` stores it in the load registry and returns the stored value on every subsequent call.
- `%fetch` returns it directly to the caller and never stores it.

`%fetch(url)` **does not consult the import registry.** Even if `url` is already cached via `%import`, `%fetch(url)` runs the top level fresh and returns a new value distinct from the cached one. The registry entry is unchanged; the cached value is unaffected.

This lets `%fetch(url)` serve as "give me a fresh copy of what this URL's source defines" — useful when a caller needs an independent instance rather than the shared cached one.

## Two levels of caching (still applies)

The value cache doesn't apply to `%fetch`, but the byte cache does:

- **Load registry** (per-process, in-memory, only used by `%import`). `%fetch` neither reads nor writes it.
- **Byte cache** (persistent, on-disk, shared with `%import`). Downloaded bytes are cached per [cache-dir](https://puck.uno/requirements/cache-dir); a `%fetch` call for a URL whose bytes are already cached does not re-download. Only the top-level execution runs fresh.

This means `%fetch` is not "expensive network fetch every call" — it's "cheap byte-cache hit + fresh top-level execution." For heavy top levels (a class definition allocating hundreds of objects at declaration time), the execution cost is real; for lightweight top levels, it's near-free.

## The `as_self` option

**Ownership semantics identical to `%import`'s** — see [`%import` § The `as_self` option](import#the-as_self-option). By default a fetched object is owned by the puck-faucet's role; `as_self: true` overrides to give it the caller's role.

**Caching interaction differs from `%import`'s.** `%fetch` doesn't cache regardless of the `as_self` setting — every call runs the top level fresh and returns a new object. So the per-role cache complexity that applies to `%import(url, as_self: true)` (see [`%import` § Per-role caching](import#per-role-caching)) doesn't arise here: each `%fetch` call produces its own value with its own role tag, independent of any other call.

When to reach for `%fetch(url, as_self: true)` vs `%import(url, as_self: true)`:

- **`%import(url, as_self: true)`** — you want your role's copy of the URL's value, cached and shared with other same-role calls to the same URL. Common for project-internal library files.
- **`%fetch(url, as_self: true)`** — you want a fresh copy running as your role for THIS call only, unshared even with your own future imports. Less common; use when the value should be genuinely one-shot.

## Testing

- **Two calls, two independent objects** — `$a = %fetch('url'); $b = %fetch('url')` produces two distinct objects; `$a == $b` is false; a runtime mutation to `$a` is NOT visible via `$b`.
- **Top-level runs on every call** — downloading a file whose top level generates a UUID via `%fetch('url')` produces a different UUID on each call. Under `%import('url')` this would silently return the same UUID.
- **Method bodies don't run at fetch time** — downloading a file whose METHOD sets a global flag leaves the flag unset until the method is explicitly called; only the top level runs at fetch.
- **`%fetch` does not consult the import registry** — after `%import('url')` has cached a value, `%fetch('url')` runs the top level fresh and returns a new value distinct from the cached one.
- **`%fetch` does not populate the import registry** — after `%fetch('url')` where `url` was not previously imported, a subsequent `%import('url')` runs the top level from scratch (nothing was stored by the `%fetch` call).
- **Byte cache hit skips network** — a `%fetch` call for a URL whose bytes are already in the byte cache does not issue a network fetch; the bytes come from the cache, only the top-level execution runs fresh.
- **Value collects when reference dropped** — after `$a = %fetch('url'); $a = null`, the fetched value is unreachable and can be garbage-collected. Nothing pins it.
- **Method call triggers dependency import** — a fetched object whose method body calls `%fetch('other-url')` (or `%import('other-url')`) does not trigger the dependency at fetch time; it triggers only when the method is invoked.
- **Default owner is the `%fetch` faucet's role** — inside a fetched object's method, `%chain.role` (or equivalent introspection) reports the puck-faucet role, not the caller's role.
- **`as_self: true` gives object the caller's role** — with `as_self: true`, the fetched object's methods run under the caller's role.
- **404 raises** — `%fetch('https://example.com/does-not-exist')` against a URL that returns HTTP 404 raises a puck-lookup error.
- **Network unreachable raises** — a URL that cannot be resolved (DNS failure) raises a puck-lookup error.
- **Timeout on hung fetch raises** — a URL that never returns bytes causes the fetch to raise after the engine-configured deadline.
- **Missing URL arg raises** — `%fetch()` raises for missing required argument.
- **Wrong-type URL arg raises** — `%fetch(42)` (integer where URL string expected) raises a type error.
- **Empty-string URL raises** — `%fetch('')` raises a puck-lookup error.
- **Default-granted across role boundaries** — a non-user role invoked without an explicit `%fetch` grant can still call `%fetch('url')` (this capability is default-granted, same as `%import`).
