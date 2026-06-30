# `%puck`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_puck",
	"role": "spec for %puck — the gateway for downloading objects by URL. Each call returns a fresh object; bytes may be cached for efficiency but objects are not shared between calls."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%puck`.

`%puck` is the gateway between Caspian code and the Puck object system. An object is identified by a URL; `%puck` downloads the object and returns it. Each call returns a **fresh object** — two `%puck['url']` calls return two independent objects, even when the URL is the same.

## Download, don't execute

Downloading an object does not run any of its code. The object arrives ready to receive method calls; its methods only execute when called. If a method needs another object, that method calls `%puck['other-url']` from inside its own body — the dependency download happens at method-call time, not at the original download.

This means downloading an object is cheap and has no side effects beyond fetching the bytes (and possibly caching them). All execution happens later, when method calls actually run.

## Entry points

| Surface | Purpose |
|---|---|
| `%puck[url]` | Download the object at `url` and return it. Each call returns a fresh object. `%[url]` is the further-shortened form — preferred in code samples. |
| `%puck.lookup(url, opts?)` | Long form of the download; takes options the bracket form doesn't expose (e.g. `as_self:`). |
| `%puck.register(url, ...)` | Register an object under a URL so other code can `%[url]` it. |
| `%puck.fetch(url, ...)` | Raw byte fetch — bypasses the object layer; useful when you want the on-the-wire representation rather than a usable object. |

## Caching: bytes, not objects

The bytes returned by a URL may be cached so a re-download doesn't hit the network. The cache is at the byte layer; the **object** built from those bytes is fresh on every `%puck['url']` call. Two callers downloading from the same URL get two separate objects, even if both were built from the same cached bytes. State in one object doesn't leak to the other.

## The `as_self` option

By default, a downloaded object lives in its own role (see [roles § Library role](../../roles/#library-role)). The `as_self: true` kwarg overrides this:

~~~caspian
$obj = %puck['https://example.com/widget']                  # owned by its own role
$obj = %puck['https://example.com/widget', as_self: true]   # owned by the caller's role
~~~

With `as_self: true`:

- The object is owned by the **caller's** role, not by its own.
- Code in the object's methods runs with the caller's authority — including `%engine` access if the caller is `user`. This is the explicit opt-in for "treat this object as part of my own identity."
- `as_self` does NOT transitively apply. If a method on the object calls `%puck['other-url']` without specifying `as_self`, the further object gets its own role (not the original caller's). Per-call control.

Use `as_self: true` when an object is trusted enough to act with the loader's authority — typically project-internal objects the loader wrote themselves, or objects the loader explicitly wants to fold into its own identity.

## Where the spec lives

The full Puck-protocol spec — URL resolution rules, the fetcher chain, the cache, the version constraints — has its own home (will land under `requirements/puck/`). This page is the Caspian-side surface; the protocol is the same regardless of which language host uses it.
