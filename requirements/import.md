# `%import`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_import",
	"role": "spec for %import — the gateway for downloading objects by URL. Downloads a source file (or serialized object), runs its top-level once, and returns whatever the top level evaluates to. Cache is keyed by (url, target-role) — non-as_self imports share a single entry under the puck-faucet role; as_self imports get per-role entries. Same URL in the same role → same object; %import.uncache and %import.flush_unused are role-scoped (user role can flush everything). For transient loads use the companion %fetch operator."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%import`.

`%import` is the gateway between Caspian code and the Puck object system. An object is identified by a URL; `%import` downloads the source at that URL, runs its top-level code, and returns the value the top level evaluates to. Repeated calls with the same URL return the **same value** — first import runs the top level and stores the result in the process's load registry; every subsequent import is a lookup returning the stored value directly. Loaded values stay for the lifetime of the process — same model as Python's `import`, Ruby's `require`, Node's `require`.

**Companion operator:** [`%fetch(url)`](fetch) is the transient counterpart — runs the top level fresh on every call, doesn't cache, returns a new object each time. Use `%fetch` for one-shot loads (heavy libraries used once, large data files processed and discarded) where caching would waste memory. Both operators support the `as_self` option identically; see [The `as_self` option](#the-as_self-option) below.

User-facing background: [documentation/import](https://puck.uno/documentation/import) covers the "top-level is a declaration" contract, the shared-mutation caveat, `%import.uncache`, and `%import.flush_unused`. [documentation/fetch](https://puck.uno/documentation/fetch) covers `%fetch`.

Caspian doesn't have a "library" concept as a technical primitive — `%import` downloads objects (classes, instances, records, etc.). See [concepts § Objects, not libraries](https://puck.uno/requirements/concepts#objects-not-libraries) for the framing.

## What runs at import time

Importing a source file runs its **top-level code once** — enough to evaluate what the file returns. **Method bodies do NOT run at import time.** They execute only when their method is called. If a method needs another object, that method calls `%import('other-url')` from inside its own body — the dependency download happens at method-call time, not at the original import.

The **top-level should be a declaration**, not a computation. A file whose top level defines a class, function, or hash is well-behaved; a file whose top level generates a UUID or reads the current time will produce a value that gets cached and returned identically on every subsequent import — usually not what the author intended. See [documentation/import § The contract on downloadable files](https://puck.uno/documentation/import#the-contract-on-downloadable-files) for the developer-facing rule.

## Entry points

| Surface | Purpose |
|---|---|
| `%import(url)` | Import the source at `url`, run its top level, return the value it produces. First import of a given URL runs the top level and stores the result; every subsequent import of the same URL returns the stored value. `%(url)` is the further-shortened form — preferred in code samples. |
| `%import(url, opts?)` | Options form. Accepts `as_self: true` and future options. |
| `%import.uncache(url)` | Drop entries for `url` from the load registry. **User role: drops entries across every role.** Other roles: drops only entries under the caller's own role. Existing references continue to work. |
| `%import.flush_unused()` | Sweep the load registry, dropping entries whose values are not referenced outside the registry. **User role: sweeps everything across all roles.** Other roles: sweeps only entries under the caller's own role. Returns the number of entries dropped. |
| `%import.register(url, ...)` | Register an object under a URL so other code can `%(url)` it. |

## Two levels of caching

`%import` uses two independent caches:

- **Load registry** (per-process, in-memory). Maps `(url, target-role)` → value produced by the first import for that pair. Repeated `%import(url)` calls with the same URL AND the same target role return the stored value directly — no re-execution, no re-transpile, no re-fetch. Loaded values stay for the lifetime of the process. This is what makes `$foo.class == $bar.class` hold when `$foo` and `$bar` are both instances of a class imported from the same URL under the same target role. The target role is puck-faucet by default and the caller's role with `as_self: true` — see [Per-role caching](#per-role-caching) below. To bypass or clear the registry, use [`%fetch(url)`](fetch) (bypass, transient), [`%import.uncache(url)`](#the-import-uncache-url-operation) (drop a specific entry), or [`%import.flush_unused()`](#the-import-flush_unused-operation) (sweep unreferenced entries).
- **Byte cache** (persistent, on-disk, shared with `%fetch`). Downloaded bytes are cached per the Puck cache-directory format ([cache-dir](https://puck.uno/requirements/cache-dir)) so a load-registry miss (first import of a URL in a fresh process) doesn't necessarily hit the network. The byte cache is version-aware — it can hold multiple timestamped versions of the same URL and answer time-scoped queries. HTTP cache-control directives (`Cache-Control`, `Expires`, `ETag`) govern freshness for direct fetches through Wire; a cached byte version is served when fresh, re-validated when stale.

Same URL, same process → one execution ever. Different process, same URL → the byte cache usually avoids re-download; the top level runs once in the new process.

**Runtime mutations to an imported value are visible to every other caller sharing the same cache entry** — for non-as_self imports (single shared entry under puck-faucet), that means every caller across every role. For as_self imports (per-role entries), that means every caller within the same role only. Same caveat as monkey-patching an imported module in Python / Ruby / Node. See [documentation/import § Shared mutation](https://puck.uno/documentation/import#shared-mutation) for the developer-facing explanation.

## Per-role caching

The cache key is **(url, target-role)** where target-role is determined by whether `as_self: true` was passed:

- **Non-as_self imports** — target-role is the puck-faucet role. Every caller across every role uses the same key `(url, puck-faucet)`, so all callers share a single cache entry. One value per URL for the default case; no memory duplication.
- **`as_self: true` imports** — target-role is the caller's role. Cache key is `(url, caller-role)`. Same-role callers share the entry; different-role callers each get their own.

Illustration:

~~~caspian
# In user code:
$a = %('foo.bar/lib.casp')                 # cached under (lib.casp, puck-faucet)
$b = %('foo.bar/lib.casp', as_self: true)  # cached under (lib.casp, user)
$a == $b                                    # false — two different cached values

# In some library code (different role):
$c = %('foo.bar/lib.casp')                 # cached under (lib.casp, puck-faucet) — HIT
$a == $c                                    # true — same cached value as $a

$d = %('foo.bar/lib.casp', as_self: true)  # cached under (lib.casp, library-role)
$b == $d                                    # false — different roles → different entries
~~~

**Why the split.** The default `%import(url)` is intended to be a shared library load — anyone can get it; methods run under puck-faucet's neutral authority; single value in the cache for efficiency. The `as_self: true` form is intended for a caller's own project files — the caller wants those files to run under its OWN role's authority. Different roles each doing `as_self` are each declaring "these files are mine" — they legitimately want their own copies, not shared. Per-role cache entries under as_self honors that intent.

**Class identity across roles.** For default imports, class identity holds across roles (everyone gets the same puck-faucet-owned class). For as_self imports, class identity holds within a role (same role → same class object) but not across (role A's `%(url, as_self: true).new()` and role B's produce instances whose `.class` fields differ). That's the correct semantics under Caspian's role model — as_self is opt-in role personalization, and different roles claiming a value as their own get separate values.

**Same URL, both forms, same role.** Nothing prevents a role from importing the same URL both ways:

~~~caspian
$shared = %('foo.bar/lib.casp')                    # (lib.casp, puck-faucet)
$mine   = %('foo.bar/lib.casp', as_self: true)     # (lib.casp, user)
~~~

Two live cached values for the same URL, distinguished by which key they're stored under. `$shared` and `$mine` are different objects. Later bare `%()` calls (no as_self) always return the puck-faucet entry (`$shared`); `%(url, as_self: true)` calls always return the caller-role entry (`$mine`). No ambiguity — each cache entry has its own lookup path.

## The `%import.uncache(url)` operation

Drops cache entries for `url` from the load registry. The **name is deliberately "uncache" rather than "unload"** — the operation removes the URL from the cache, but it does NOT destroy the loaded value. If anything else in the program still holds a reference to the value (variables, instances, other objects containing it), the value stays alive; only the cache entry goes away.

The scope depends on the caller's role:

- **Called from user role** — drops **all** entries for `url` across every role (the puck-faucet entry AND every per-role as_self entry). User is the god role; uncache from user is a clean sweep.
- **Called from any other role** — drops only entries for `url` under the caller's own role. Other roles' entries (including the puck-faucet entry if the caller isn't puck-faucet) are unaffected.

A subsequent `%(url)` (with the appropriate as_self setting) runs the top level fresh and returns a new value under the dropped key. For a brief window after uncache, two versions of the URL's value may coexist: the old one held by existing references, and the new one produced by the next import.

**Idempotent.** Uncaching a URL that has no matching entries is a no-op — no error.

## The `%import.flush_unused()` operation

Sweeps the load registry, dropping entries whose values are not referenced anywhere outside the registry itself. Returns the number of entries dropped. Scope depends on the caller's role:

- **Called from user role** — sweeps **the entire registry** across every role. Any (url, role) entry whose value is only pinned by the registry itself gets dropped.
- **Called from any other role** — sweeps only entries under the caller's own role. Other roles' entries are untouched.

Rarely needed under normal use — the registry footprint is bounded by distinct URLs the program has touched (times distinct as_self-using roles), which for most programs is a small set. Useful for:

- **Memory pressure recovery.** A program hitting memory limits can call `%import.flush_unused()` at a natural boundary (end of a request, end of a batch job) to reclaim entries for URLs no longer in use.
- **Long-running processes with variable workloads.** An agent that loads different libraries per task can flush between tasks to keep the resident set trim.
- **After a phase transition.** A program that loads a bunch of setup libraries during initialization and then never needs them again can flush after initialization completes.

**Same discipline as garbage collection.** The operation runs when called; it decides what to drop based on current reachability; entries with any external reference (a variable holding the value, an instance of a class, another object containing it) are kept. Same rules as ordinary GC, applied specifically to registry entries.

**Composes with `%import.uncache`.** `flush_unused` handles the "release whatever's not being used" case; `uncache` handles the "release this specific URL" case. Both role-scope the same way (user-wide vs caller-role-scoped).

## The `as_self` option

**Supported on both `%import` and `%fetch`** with identical semantics on ownership. Documented here canonically; [`%fetch`](fetch#the-as_self-option) points back to this section. **Caching interaction is different between the two operators** — see [Per-role caching](#per-role-caching) for `%import`'s cache-key behavior; `%fetch` doesn't cache regardless.

By default, a downloaded object is owned by the **puck-faucet's role** — same as any other value pulled through a faucet, per the [faucet model](https://puck.uno/requirements/plumbing/faucets/#every-faucet-has-its-own-role). Downloaded objects don't get their own per-object roles; they share the puck-faucet's role, distinct from the caller's role. That means when the caller invokes a method on the downloaded object, the method body runs as the puck-faucet's role (per [methods run as their object's role](https://puck.uno/requirements/roles/#methods-run-as-their-objects-role)) and doesn't inherit the caller's `%engine` access or other capabilities.

The `as_self: true` kwarg overrides the faucet-role default:

~~~caspian
$obj = %import('https://example.com/widget')                  # owned by the puck-faucet's role
$obj = %import('https://example.com/widget', as_self: true)   # owned by the caller's role
$obj = %fetch('https://example.com/widget', as_self: true)    # same option, same semantics, transient value
~~~

With `as_self: true`:

- The object is owned by the **caller's** role, not by the faucet's.
- Code in the object's methods runs with the caller's authority — including `%engine` access if the caller is `user`. This is the explicit opt-in for "treat this object as part of my own identity."
- `as_self` does NOT transitively apply. If a method on the object calls `%import('other-url')` or `%fetch('other-url')` without specifying `as_self`, the further object gets the faucet role (not the original caller's). Per-call control.

Use `as_self: true` when an object is trusted enough to act with the loader's authority — typically project-internal objects the loader wrote themselves, or objects the loader explicitly wants to fold into its own identity.

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
- **`%import.uncache` drops the registry entry** — after `$a = %import('url'); %import.uncache('url'); $b = %import('url')` in the same role, `$a` and `$b` are different objects.
- **`%import.uncache` preserves existing references** — after `$a = %import('url'); %import.uncache('url')`, `$a` continues to work and any instances derived from it stay valid.
- **`%import.uncache` is idempotent** — uncaching a URL that has no matching entries is a no-op, no error.
- **`%import.uncache` from user role drops all-roles entries** — after any role imports `url` (default or as_self), a `%import.uncache('url')` call from user role drops all matching entries across every role.
- **`%import.uncache` from non-user role scoped to own role** — after user imports `url` and library-role imports `url` with as_self, a `%import.uncache('url')` call from library role drops only library-role's as_self entry; user's puck-faucet entry survives.
- **`%import.flush_unused` drops unreferenced entries** — after `%import('url'); # discard result; %import.flush_unused()` in the same role, a subsequent `%import('url')` runs the top level again (the flush dropped the registry entry).
- **`%import.flush_unused` preserves referenced entries** — after `$a = %import('url'); %import.flush_unused()`, `%import('url')` returns the same object as `$a` (still referenced).
- **`%import.flush_unused` returns the drop count** — the return value is the integer number of entries dropped in this call.
- **`%import.flush_unused` from user role sweeps all roles** — user's flush drops any unreferenced entries across every role.
- **`%import.flush_unused` from non-user role scoped to own role** — a library-role flush only drops entries under library role; other roles' unreferenced entries survive.
- **Default and as_self imports produce separate cache entries** — from the same role, `$a = %import('url'); $b = %import('url', as_self: true)` produces two different objects; `$a == $b` is false; both remain live in the registry until explicitly uncached or garbage-collected.
- **Default imports share across roles** — `%import('url')` from role A and `%import('url')` from role B return the same object (both hit the (url, puck-faucet) entry).
- **`as_self` imports isolated across roles** — `%import('url', as_self: true)` from role A and `%import('url', as_self: true)` from role B return two different objects (each role has its own (url, role) entry); mutations to A's copy are NOT visible via B's copy.
- **`as_self` imports shared within a role** — repeated `%import('url', as_self: true)` from the same role return the same object; mutation to one is visible via all.
- **Default owner is the `%import` faucet's role** — inside an imported object's method, `%role` (or equivalent introspection) reports the puck-faucet role, not the caller's role.
- **Default owner cannot reach `%engine`** — an imported object's method that references `%engine` raises capability-not-granted when the caller is `user` but did not pass `as_self: true`.
- **`as_self: true` gives object the caller's role** — with `as_self: true`, the imported object's methods run under the caller's role and can reach `%engine` when the caller is `user`.
- **`as_self` does not transit** — an `as_self: true` object whose method calls `%import('other-url')` without `as_self:` gets a further object owned by the puck-faucet role, not the caller's.
- **`as_self` works identically on `%fetch`** — `%fetch('url', as_self: true)` gives the fetched (transient) object the caller's role, same rules as on `%import`.
- **`%import.register` makes URL resolvable** — after `%import.register('https://example.com/widget', obj)`, `%import('https://example.com/widget')` returns objects backed by that registration.
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
