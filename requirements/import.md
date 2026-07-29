# `%import`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_import",
	"role": "spec for %import — the gateway for downloading objects by URL. Downloads a source file (or serialized object), runs its top-level once, and returns whatever the top level evaluates to. The returned value is stored in the process's load registry and returned identically on every subsequent import of the same URL — same model as Python's import, Ruby's require, Node's require. Loaded values stay for the lifetime of the process. The cache: false option opts out of caching for one-shot imports; %import.unload(url) drops a cached URL from the registry."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%import`.

`%import` is the gateway between Caspian code and the Puck object system. An object is identified by a URL; `%import` downloads the source at that URL, runs its top-level code, and returns the value the top level evaluates to. Repeated calls with the same URL return the **same value** — first import runs the top level and stores the result in the process's load registry; every subsequent import is a lookup returning the stored value directly. Loaded values stay for the lifetime of the process — same model as Python's `import`, Ruby's `require`, Node's `require`.

User-facing background: [documentation/import](https://puck.uno/documentation/import) covers the "top-level is a declaration" contract, the shared-mutation caveat, the `cache: false` opt-out, and `%import.unload`.

Caspian doesn't have a "library" concept as a technical primitive — `%import` downloads objects (classes, instances, records, etc.). See [concepts § Objects, not libraries](https://puck.uno/requirements/concepts#objects-not-libraries) for the framing.

## What runs at import time

Importing a source file runs its **top-level code once** — enough to evaluate what the file returns. **Method bodies do NOT run at import time.** They execute only when their method is called. If a method needs another object, that method calls `%import('other-url')` from inside its own body — the dependency download happens at method-call time, not at the original import.

The **top-level should be a declaration**, not a computation. A file whose top level defines a class, function, or hash is well-behaved; a file whose top level generates a UUID or reads the current time will produce a value that gets cached and returned identically on every subsequent import — usually not what the author intended. See [documentation/import § The contract on downloadable files](https://puck.uno/documentation/import#the-contract-on-downloadable-files) for the developer-facing rule.

## Entry points

| Surface | Purpose |
|---|---|
| `%import(url)` | Import the source at `url`, run its top level, return the value it produces. First import of a given URL runs the top level and stores the result; every subsequent import of the same URL returns the stored value. `%(url)` is the further-shortened form — preferred in code samples. |
| `%import(url, cache: false)` | One-shot import. Runs the top level fresh regardless of the load registry; does not store the result. Every call returns a new object. Use for heavy libraries used once, large data loads, or any case where pinning in the registry would waste memory. |
| `%import(url, opts?)` | Options form. Accepts `cache: false`, `as_self: true`, and future options. |
| `%import.unload(url)` | Drop `url` from the load registry. A subsequent `%import(url)` runs the top level fresh and returns a new value. Existing references to the previously-cached value continue to work. |
| `%import.flush_unused()` | Sweep the load registry, dropping entries whose values are not referenced anywhere outside the registry itself. Rarely needed; useful for memory pressure or after a batch operation that loaded and released large libraries. Returns the number of entries dropped. |
| `%import.register(url, ...)` | Register an object under a URL so other code can `%(url)` it. |
| `%import.raw(url)` | Raw byte fetch — bypasses the object layer; useful when you want the on-the-wire representation rather than a usable object. |

## Two levels of caching

`%import` uses two independent caches:

- **Load registry** (per-process, in-memory). Maps URL → value produced by the first import. Repeated `%import(url)` calls with the same URL return the stored value directly — no re-execution, no re-transpile, no re-fetch. Loaded values stay for the lifetime of the process. This is what makes `$foo.class == $bar.class` hold when `$foo` and `$bar` are both instances of a class imported from the same URL. The `cache: false` option and `%import.unload(url)` are the two mechanisms for bypassing / clearing the registry.
- **Byte cache** (persistent, on-disk). Downloaded bytes are cached per the Puck cache-directory format ([cache-dir](https://puck.uno/requirements/cache-dir)) so a load-registry miss (first import of a URL in a fresh process) doesn't necessarily hit the network. The byte cache is version-aware — it can hold multiple timestamped versions of the same URL and answer time-scoped queries. HTTP cache-control directives (`Cache-Control`, `Expires`, `ETag`) govern freshness for direct fetches through Wire; a cached byte version is served when fresh, re-validated when stale.

Same URL, same process → one execution ever. Different process, same URL → the byte cache usually avoids re-download; the top level runs once in the new process. Same URL, `cache: false` → top level runs on every call, no registry entry.

**Runtime mutations to an imported value are visible to every other caller of the same URL** — since there's only one cached value per URL, mutations are effectively global. Same caveat as monkey-patching an imported module in Python / Ruby / Node. See [documentation/import § Shared mutation](https://puck.uno/documentation/import#shared-mutation) for the developer-facing explanation.

## The `cache: false` option

Bypasses the load registry entirely. When called:

1. The top level of the URL's source runs, regardless of whether the URL is already in the registry.
2. The result is returned to the caller.
3. Nothing is added to the registry; nothing existing in the registry is modified.

Consequence: two calls to `%(url, cache: false)` return two different objects. Two `.new()` instantiations from two `cache: false` imports of the same class produce instances whose `.class` fields are different objects. Identity is NOT preserved across `cache: false` calls — that's the trade-off for opting out of caching.

Meaningful only for values that would waste memory if pinned indefinitely — heavy libraries used once, large data files processed and discarded. For ordinary library imports, omit the option (default cached behavior is right).

## The `%import.unload(url)` operation

Drops `url` from the load registry. A subsequent `%(url)` runs the top level fresh and returns a new value.

**Existing references survive.** If code elsewhere in the process is still holding a reference to the previously-cached value (variables, instances of a class, other objects containing it), those references continue to work — the value stays alive as long as anything holds it. Only future `%(url)` calls run fresh. For a brief window after unload, two versions of the URL's value may coexist: the old one held by existing references, and the new one produced by the next import. Usually harmless; occasionally relevant during dev iteration.

**Idempotent.** Unloading a URL that isn't in the registry is a no-op — no error.

## The `%import.flush_unused()` operation

Sweeps the load registry, dropping entries whose values are not referenced anywhere outside the registry itself. Returns the number of entries dropped.

Rarely needed under normal use — the registry footprint is bounded by distinct URLs the program has touched, and most programs' URL sets are small. Useful for:

- **Memory pressure recovery.** A program hitting memory limits can call `%import.flush_unused()` at a natural boundary (end of a request, end of a batch job) to reclaim entries for URLs no longer in use.
- **Long-running processes with variable workloads.** An agent that loads different libraries per task can flush between tasks to keep the resident set trim.
- **After a phase transition.** A program that loads a bunch of setup libraries during initialization and then never needs them again can flush after initialization completes.

**Same discipline as garbage collection.** The operation runs when called; it decides what to drop based on current reachability; entries with any external reference (a variable holding the value, an instance of a class, another object containing it) are kept. Same rules as ordinary GC, applied specifically to registry entries.

**Composes with `%import.unload`.** `flush_unused` handles the "release whatever's not being used" case; `unload` handles the "release this specific thing" case. Pick based on whether you know the target URL or just the moment.

## The `as_self` option

By default, a downloaded object is owned by the **`%import` faucet's role** — same as any other value pulled through a faucet, per the [faucet model](https://puck.uno/requirements/plumbing/faucets/#every-faucet-has-its-own-role). Downloaded objects don't get their own per-object roles; they share the puck-faucet's role, distinct from the caller's role. That means when the caller invokes a method on the downloaded object, the method body runs as the puck-faucet's role (per [methods run as their object's role](https://puck.uno/requirements/roles/#methods-run-as-their-objects-role)) and doesn't inherit the caller's `%engine` access or other capabilities.

The `as_self: true` kwarg overrides the faucet-role default:

~~~caspian
$obj = %import('https://example.com/widget')                  # owned by the %import faucet's role
$obj = %import('https://example.com/widget', as_self: true)   # owned by the caller's role
~~~

With `as_self: true`:

- The object is owned by the **caller's** role, not by the faucet's.
- Code in the object's methods runs with the caller's authority — including `%engine` access if the caller is `user`. This is the explicit opt-in for "treat this object as part of my own identity."
- `as_self` does NOT transitively apply. If a method on the object calls `%import('other-url')` without specifying `as_self`, the further object gets the faucet role (not the original caller's). Per-call control.

Use `as_self: true` when an object is trusted enough to act with the loader's authority — typically project-internal objects the loader wrote themselves, or objects the loader explicitly wants to fold into its own identity.

`cache: false` and `as_self: true` compose freely — you can pass both to a single call.

## Where the spec lives

The full Puck-protocol spec — URL resolution rules, the fetcher chain, the cache, the version constraints — has its own home (will land under `requirements/puck/`). This page is the Caspian-side surface; the protocol is the same regardless of which language host uses it.

## Testing

- **Bracket shorthand returns object** — `%import('https://example.com/widget')` returns the object at that URL when the URL is reachable and serves a Caspian-parseable body.
- **`%(url)` further shorthand** — `%('https://example.com/widget')` is equivalent to `%import('https://example.com/widget')` and returns the same object.
- **Two calls, same object** — `$a = %import('url'); $b = %import('url')` produces the same object; `$a == $b` holds, and a runtime mutation to `$a` is visible via `$b`.
- **Top-level runs at import; method bodies don't** — importing a file whose top level sets a global flag causes the flag to fire once at import time; importing a file whose METHOD sets the flag leaves the flag unset until the method is explicitly called.
- **Top-level runs once per process per URL** — the second `%import('url')` in the same process does not re-execute the top level, even if the caller discarded the first import's result. The value stays in the load registry for the process's lifetime.
- **Loaded values pin for process lifetime** — `%import('url')` followed by discarding the result, then a much-later `%import('url')`, returns the same object as the first call. Values are not garbage-collected from the load registry.
- **Method call triggers dependency import** — an imported object whose method body calls `%import('other-url')` fetches the dependency only when that method is invoked, not at the original import.
- **Byte cache hit skips network** — a first import of a URL in a fresh process consults the byte cache before hitting the network; if fresh bytes are cached, no HTTP request is made.
- **Shared mutation is visible across callers** — after `%import('url').inherits $other_class`, a later `%import('url')` from unrelated code sees the added inheritance (it's the same value).
- **`cache: false` returns a fresh object every call** — `$a = %import('url', cache: false); $b = %import('url', cache: false)` produces two distinct objects; `$a == $b` is false; a mutation to `$a` is NOT visible via `$b`.
- **`cache: false` bypasses an existing cache entry** — after `%import('url')` has cached a value, `%import('url', cache: false)` runs the top level fresh and returns a new value distinct from the cached one. The registry entry is unchanged.
- **`cache: false` does not store** — after `%import('url', cache: false)` where `url` was not previously cached, a subsequent `%import('url')` (without the option) runs the top level again (nothing was stored).
- **`%import.unload` drops the registry entry** — after `$a = %import('url'); %import.unload('url'); $b = %import('url')`, `$a` and `$b` are different objects.
- **`%import.unload` preserves existing references** — after `$a = %import('url'); %import.unload('url')`, `$a` continues to work and any instances derived from it stay valid.
- **`%import.unload` is idempotent** — unloading a URL that was never imported (or already unloaded) is a no-op, no error.
- **`%import.flush_unused` drops unreferenced entries** — after `%import('url'); # discard result; %import.flush_unused()`, a subsequent `%import('url')` runs the top level again (the flush dropped the registry entry).
- **`%import.flush_unused` preserves referenced entries** — after `$a = %import('url'); %import.flush_unused()`, `%import('url')` returns the same object as `$a` (still referenced).
- **`%import.flush_unused` returns the drop count** — the return value is the integer number of entries dropped in this call.
- **Default owner is the `%import` faucet's role** — inside an imported object's method, `%role` (or equivalent introspection) reports the puck-faucet role, not the caller's role.
- **Default owner cannot reach `%engine`** — an imported object's method that references `%engine` raises capability-not-granted when the caller is `user` but did not pass `as_self: true`.
- **`as_self: true` gives object the caller's role** — with `as_self: true`, the imported object's methods run under the caller's role and can reach `%engine` when the caller is `user`.
- **`as_self` does not transit** — an `as_self: true` object whose method calls `%import('other-url')` without `as_self:` gets a further object owned by the puck-faucet role, not the caller's.
- **`cache: false` and `as_self: true` compose** — both may be passed to a single call; each takes effect independently.
- **`%import.register` makes URL resolvable** — after `%import.register('https://example.com/widget', obj)`, `%import('https://example.com/widget')` returns objects backed by that registration.
- **`%import.raw` returns raw bytes** — `%import.raw('https://example.com/widget')` returns the on-the-wire byte representation, not a usable object; the object layer is bypassed.
- **404 raises** — `%import('https://example.com/does-not-exist')` against a URL that returns HTTP 404 raises a puck-lookup error.
- **Network unreachable raises** — a URL that cannot be resolved (DNS failure) raises a puck-lookup error.
- **Redirect followed** — a URL that returns a 301/302 to another location resolves to the object at the redirect target.
- **Timeout on hung fetch raises** — a URL that never returns bytes causes the import to raise after the engine-configured deadline (does not hang indefinitely).
- **Non-Caspian MIME type dispatch** — a URL serving `image/png` or `application/json` returns an object whose class matches the MIME type dispatch rule (not a parse error).
- **Unicode URL path** — `%import('https://example.com/wídget')` (non-ASCII in the path) resolves normally with proper percent-encoding.
- **Cache dir honoured** — bytes are written under the engine-configured cache directory; changing the cache dir between runs causes a fresh network fetch.
- **Missing URL arg raises** — `%import()` raises for missing required argument.
- **Wrong-type URL arg raises** — `%import(42)` (integer where URL string expected) raises a type error.
- **Empty-string URL raises** — `%import('')` raises a puck-lookup error (empty URL is not a legal identifier).
- **Class-vs-instance import** — importing a URL whose object is a class returns the class object (methods callable to instantiate); importing a URL whose object is a pre-built instance returns that instance directly.
- **Default-granted across role boundaries** — a non-user role invoked without an explicit `%import` grant can still call `%import('url')` (this capability is default-granted).
- **Registration participates in identity cache** — after `%import.register('url', value)`, repeated `%import('url')` calls return the same registered value; identity preservation applies to registered values the same as imported ones.
