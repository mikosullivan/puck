# `%fetch`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_puck",
	"role": "spec for %fetch — the gateway for downloading objects by URL. Each call returns a fresh object; bytes may be cached for efficiency but objects are not shared between calls."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%fetch`.

`%fetch` is the gateway between Caspian code and the Puck object system. An object is identified by a URL; `%fetch` downloads the object and returns it. Each call returns a **fresh object** — two `%fetch('url')` calls return two independent objects, even when the URL is the same.

Caspian doesn't have a "library" concept as a technical primitive — `%fetch` downloads objects (classes, instances, records, etc.). See [concepts § Objects, not libraries](https://puck.uno/documentation/requirements/concepts#objects-not-libraries) for the framing.

## Download, don't execute

Downloading an object does not run any of its code. The object arrives ready to receive method calls; its methods only execute when called. If a method needs another object, that method calls `%fetch('other-url')` from inside its own body — the dependency download happens at method-call time, not at the original download.

This means downloading an object is cheap and has no side effects beyond fetching the bytes (and possibly caching them). All execution happens later, when method calls actually run.

## Entry points

| Surface | Purpose |
|---|---|
| `%fetch(url)` | Download the object at `url` and return it. Each call returns a fresh object. `%(url)` is the further-shortened form — preferred in code samples. |
| `%fetch.lookup(url, opts?)` | Long form of the download; takes options the bracket form doesn't expose (e.g. `as_self:`). |
| `%fetch.register(url, ...)` | Register an object under a URL so other code can `%(url)` it. |
| `%fetch.fetch(url, ...)` | Raw byte fetch — bypasses the object layer; useful when you want the on-the-wire representation rather than a usable object. |

## Caching: bytes, not objects

The bytes returned by a URL may be cached so a re-download doesn't hit the network. The cache is at the byte layer; the **object** built from those bytes is fresh on every `%fetch('url')` call. Two callers downloading from the same URL get two separate objects, even if both were built from the same cached bytes. State in one object doesn't leak to the other.

## The `as_self` option

By default, a downloaded object is owned by the **`%fetch` faucet's role** — same as any other value pulled through a faucet, per the [faucet model](https://puck.uno/documentation/requirements/plumbing/faucets/#every-faucet-has-its-own-role). Downloaded objects don't get their own per-object roles; they share the puck-faucet's role, distinct from the caller's role. That means when the caller invokes a method on the downloaded object, the method body runs as the puck-faucet's role (per [methods run as their object's role](https://puck.uno/documentation/requirements/roles/#methods-run-as-their-objects-role)) and doesn't inherit the caller's `%engine` access or other capabilities.

The `as_self: true` kwarg overrides the faucet-role default:

~~~caspian
$obj = %fetch('https://example.com/widget')                  # owned by the %fetch faucet's role
$obj = %fetch('https://example.com/widget', as_self: true)   # owned by the caller's role
~~~

With `as_self: true`:

- The object is owned by the **caller's** role, not by the faucet's.
- Code in the object's methods runs with the caller's authority — including `%engine` access if the caller is `user`. This is the explicit opt-in for "treat this object as part of my own identity."
- `as_self` does NOT transitively apply. If a method on the object calls `%fetch('other-url')` without specifying `as_self`, the further object gets the faucet role (not the original caller's). Per-call control.

Use `as_self: true` when an object is trusted enough to act with the loader's authority — typically project-internal objects the loader wrote themselves, or objects the loader explicitly wants to fold into its own identity.

## Where the spec lives

The full Puck-protocol spec — URL resolution rules, the fetcher chain, the cache, the version constraints — has its own home (will land under `requirements/puck/`). This page is the Caspian-side surface; the protocol is the same regardless of which language host uses it.

## Testing

- **Bracket shorthand returns object** — `%fetch('https://example.com/widget')` returns the object at that URL when the URL is reachable and serves a Caspian-parseable body.
- **`%(url)` further shorthand** — `%('https://example.com/widget')` is equivalent to `%fetch('https://example.com/widget')` and returns the same object.
- **`%fetch.lookup` long form** — `%fetch.lookup('https://example.com/widget')` returns the same object as the bracket shorthand.
- **Two calls, two independent objects** — `$a = %fetch('url'); $b = %fetch('url')` produces distinct objects; mutating a property on `$a` does not affect `$b`.
- **Downloading does not execute** — downloading `https://example.com/side-effect-on-load` (an object whose top-level would set a global flag if executed) leaves the flag unset until a method is explicitly called.
- **Method call triggers dependency download** — a downloaded object whose method body calls `%fetch('other-url')` fetches the dependency only when that method is invoked, not at the original download.
- **Byte cache hit skips network** — after a first successful download, a second `%fetch('url')` in the same run does not issue a second network fetch; the bytes come from the cache.
- **Cache hit still produces fresh object** — two calls served from the byte cache still return two independent objects (state does not leak between them).
- **Default owner is the `%fetch` faucet's role** — inside a downloaded object's method, `%chain.role` (or equivalent introspection) reports the puck-faucet role, not the caller's role.
- **Default owner cannot reach `%engine`** — a downloaded object's method that references `%engine` raises capability-not-granted when the caller is `user` but did not pass `as_self: true`.
- **`as_self: true` gives object the caller's role** — with `as_self: true`, the downloaded object's methods run under the caller's role and can reach `%engine` when the caller is `user`.
- **`as_self` does not transit** — an `as_self: true` object whose method calls `%fetch('other-url')` without `as_self:` gets a further object owned by the puck-faucet role, not the caller's.
- **`%fetch.register` makes URL resolvable** — after `%fetch.register('https://example.com/widget', obj)`, `%fetch('https://example.com/widget')` returns objects backed by that registration.
- **`%fetch.fetch` returns raw bytes** — `%fetch.fetch('https://example.com/widget')` returns the on-the-wire byte representation, not a usable object; the object layer is bypassed.
- **404 raises** — `%fetch('https://example.com/does-not-exist')` against a URL that returns HTTP 404 raises a puck-lookup error.
- **Network unreachable raises** — a URL that cannot be resolved (DNS failure) raises a puck-lookup error.
- **Redirect followed** — a URL that returns a 301/302 to another location resolves to the object at the redirect target.
- **Timeout on hung fetch raises** — a URL that never returns bytes causes the fetch to raise after the engine-configured deadline (does not hang indefinitely).
- **Non-Caspian MIME type dispatch** — a URL serving `image/png` or `application/json` returns an object whose class matches the MIME type dispatch rule (not a parse error).
- **Unicode URL path** — `%fetch('https://example.com/wídget')` (non-ASCII in the path) resolves normally with proper percent-encoding.
- **Cache dir honoured** — bytes are written under the engine-configured cache directory; changing the cache dir between runs causes a fresh network fetch.
- **Missing URL arg raises** — `%fetch()` and `%fetch.lookup()` both raise for missing required argument.
- **Wrong-type URL arg raises** — `%fetch(42)` (integer where URL string expected) raises a type error.
- **Empty-string URL raises** — `%fetch('')` raises a puck-lookup error (empty URL is not a legal identifier).
- **Class-vs-instance download** — downloading a URL whose object is a class returns the class object (methods callable to instantiate); downloading a URL whose object is a pre-built instance returns that instance directly.
- **Default-granted across role boundaries** — a non-user role invoked without an explicit `%fetch` grant can still call `%fetch('url')` (this capability is default-granted).
- **Fresh object each call under registration** — after `%fetch.register('url', factory)`, repeated `%fetch('url')` calls each produce a fresh object from the factory.
