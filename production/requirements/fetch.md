# `%fetch`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_fetch",
	"role": "spec for %fetch — Caspian's sole download operator. Downloads a source file (or serialized object) by URL, runs its top-level code, and returns the value it produces. Each call returns a fresh object with a fresh role — no cached identity, no shared entry, no load registry. The engine MAY cache raw bytes for network efficiency (see cache-dir), but a byte-cache hit still runs the top level again and returns a new object. Developers who want shared identity across callers fetch once and pass the reference around explicitly. Supports the as_self kwarg for ownership-role override."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%fetch`.

`%fetch` is the gateway between Caspian code and the Puck object system. An object is identified by a URL; `%fetch(url)` downloads the source at that URL, runs its top-level code, and returns the value the top level evaluates to. **Each call returns a fresh object.** Two `%fetch('url')` calls with the same URL produce two independent objects — `$a == $b` is false, `.isa?` won't cross-match, a mutation to `$a` is not visible via `$b`.

Each fetched object carries a **fresh role per fetch**, per Rule 7 of the security model. Two fetches of the same URL produce two objects with two distinct roles.

Caspian doesn't do globals or ambient shared identity. If a program wants one shared value for a URL across many callers, it fetches once and passes the reference around explicitly. Two independent fetches produce two different objects — that's the intended semantics.

Caspian doesn't have a "library" concept as a technical primitive — `%fetch` downloads objects (classes, instances, records, etc.). See [concepts § Objects, not libraries](concepts#objects-not-libraries) for the framing.

## What runs at fetch time

Fetching a source file runs its **top-level code once per call** — enough to evaluate what the file returns. **Method bodies do NOT run at fetch time.** They execute only when their method is called. If a method needs another object, that method's body calls `%fetch(...)` — the dependency load happens then, not at the original fetch.

The **top-level should be a declaration**, not a computation. A file whose top level defines a class, function, or hash is well-behaved; a file whose top level generates a UUID or reads the current time will produce a different value on every fetch. That's usually fine (no silent caching to hide it), but callers relying on a stable per-URL value should either fetch once and share, or move the dynamic behavior into a callable.

## Entry points

| Surface | Purpose |
|---|---|
| `%fetch(url)` | Download the source at `url`, run its top level, return the value. Every call runs the top level again and returns a fresh object. `%(url)` is the further-shortened form — preferred in code samples. |
| `%fetch(url, opts?)` | Options form. Accepts `as_self: true` and future options. |
| `%fetch.register(url, ...)` | Register an object under a URL so other code can `%(url)` it. |

## Byte caching (network efficiency, not identity)

The engine MAY cache raw response bytes for network efficiency — a repeated fetch of the same URL doesn't need to re-download when the bytes are still fresh (see [cache-dir](cache-dir)). HTTP cache-control directives (`Cache-Control`, `Expires`, `ETag`) govern freshness; a cached byte version is served when fresh, re-validated when stale.

**Byte caching never produces a same-object result.** A cached byte hit still runs the top level again and returns a new object with a fresh role. The byte cache is a network optimization, not an identity mechanism.

## The `as_self` option

By default, a fetched object is owned by the **puck-faucet's role** — same as any other value pulled through a faucet, per the [faucet model](plumbing/faucets/#every-faucet-has-its-own-role). Each fetch mints a fresh instance of that role (Rule 7), so different fetches never share a role even in the default case. When the caller invokes a method on the fetched object, the method body runs as the puck-faucet role (per [methods run as their object's role](roles/#methods-run-as-their-objects-role)) and doesn't inherit the caller's `%engine` access or other capabilities.

The `as_self: true` kwarg overrides the faucet-role default:

~~~caspian
$obj = %fetch('https://example.com/widget')                  # owned by a fresh puck-faucet role
$obj = %fetch('https://example.com/widget', as_self: true)   # owned by the caller's role
~~~

With `as_self: true`:

- The object is owned by the **caller's** role, not by a puck-faucet role.
- Code in the object's methods runs with the caller's authority — including `%engine` access if the caller is `user`. This is the explicit opt-in for "treat this object as part of my own identity."
- `as_self` does NOT transitively apply. If a method on the object calls `%fetch('other-url')` without specifying `as_self`, the further object gets the puck-faucet role (not the original caller's). Per-call control.

Use `as_self: true` when an object is trusted enough to act with the loader's authority — typically project-internal objects the loader wrote themselves, or objects the loader explicitly wants to fold into its own identity.

## Where the spec lives

The full Puck-protocol spec — URL resolution rules, the fetcher chain, the cache, the version constraints — has its own home (will land under `requirements/puck/`). This page is the Caspian-side surface; the protocol is the same regardless of which language host uses it.

## Testing

- **Bracket shorthand returns object** — `%fetch('https://example.com/widget')` returns the object at that URL when the URL is reachable and serves a Caspian-parseable body.
- **`%(url)` further shorthand** — `%('https://example.com/widget')` is equivalent to `%fetch('https://example.com/widget')` and returns the same shape of object.
- **Two calls, two distinct objects** — `$a = %fetch('url'); $b = %fetch('url')` produces two distinct objects; `$a == $b` is false; a runtime mutation to `$a` is NOT visible via `$b`.
- **Two calls, two distinct roles** — the roles owning `$a` and `$b` are distinct (Rule 7).
- **Top-level runs every call** — fetching a file whose top level generates a UUID produces a different UUID on each fetch.
- **Method bodies don't run at fetch time** — fetching a file whose METHOD sets a flag leaves the flag unset until the method is explicitly called; only the top level runs at fetch.
- **Byte cache hit skips network** — a fetch of a URL whose bytes are already in the byte cache does not issue a network request; the bytes come from the cache, but the top level still runs and a new object still comes back.
- **Byte cache never shares identity** — after byte caching, a second `%fetch('url')` still returns an object distinct from the first (byte cache is not an identity cache).
- **Value collects when reference dropped** — after `$a = %fetch('url'); $a = null`, the fetched value is unreachable and can be garbage-collected. Nothing pins it.
- **Method call triggers dependency fetch** — a fetched object whose method body calls `%fetch('other-url')` does not fetch the dependency at fetch time; it fetches only when the method is invoked.
- **Default owner is a puck-faucet role** — inside a fetched object's method, role introspection reports a puck-faucet role, not the caller's role.
- **Default owner cannot reach `%engine`** — a fetched object's method that references `%engine` raises capability-not-granted when the caller is `user` but did not pass `as_self: true`.
- **`as_self: true` gives object the caller's role** — with `as_self: true`, the fetched object's methods run under the caller's role and can reach `%engine` when the caller is `user`.
- **`as_self` does not transit** — an `as_self: true` object whose method calls `%fetch('other-url')` without `as_self:` gets a further object owned by a puck-faucet role, not the caller's.
- **`%fetch.register` makes URL resolvable** — after `%fetch.register('https://example.com/widget', obj)`, `%fetch('https://example.com/widget')` returns objects backed by that registration (still one fresh object per call).
- **404 raises** — `%fetch('https://example.com/does-not-exist')` against a URL that returns HTTP 404 raises a puck-lookup error.
- **Network unreachable raises** — a URL that cannot be resolved (DNS failure) raises a puck-lookup error.
- **Redirect followed** — a URL that returns a 301/302 to another location resolves to the object at the redirect target.
- **Timeout on hung fetch raises** — a URL that never returns bytes causes the fetch to raise after the engine-configured deadline (does not hang indefinitely).
- **Non-Caspian MIME type dispatch** — a URL serving `image/png` or `application/json` returns an object whose class matches the MIME type dispatch rule (not a parse error). See [non-caspian-mime-types](non-caspian-mime-types).
- **Unicode URL path** — `%fetch('https://example.com/wídget')` (non-ASCII in the path) resolves normally with proper percent-encoding.
- **Cache dir honoured** — bytes are written under the engine-configured cache directory; changing the cache dir between runs causes a fresh network fetch.
- **Missing URL arg raises** — `%fetch()` raises for missing required argument.
- **Wrong-type URL arg raises** — `%fetch(42)` (integer where URL string expected) raises a type error.
- **Empty-string URL raises** — `%fetch('')` raises a puck-lookup error (empty URL is not a legal identifier).
- **Class-vs-instance fetch** — fetching a URL whose object is a class returns the class object (methods callable to instantiate); fetching a URL whose object is a pre-built instance returns that instance directly (still fresh per fetch).
- **Default-granted across role boundaries** — a non-user role invoked without an explicit `%fetch` grant can still call `%fetch('url')` (this capability is default-granted).
