# `%fetch` — one-shot URL loads

~~~vibecode
{"vibecode": {
	"doc": "documentation_fetch",
	"role": "user-facing introduction to %fetch — the transient companion to %import. Fetches a URL, runs its top level, returns the value, doesn't cache. Every call produces a new object. Use for heavy libraries you only need once, large data files you process and discard, or any case where pinning the loaded value in memory would be wasteful.",
	"status": "user doc — accompanies (does not duplicate) the spec at requirements/fetch",
	"audience": "Caspian programmers who need a URL-loaded value once and want it collected as soon as they're done with it"
}}
~~~

## What it does

`%fetch(url)` loads whatever's at that URL, runs its top-level code, and returns the resulting value. **Nothing is cached.** The value lives only as long as your reference to it; when you drop the reference, it collects normally.

Every call to `%fetch(url)` runs the top level again and returns a **new object**. Two calls to `%fetch` on the same URL produce two independent values.

~~~caspian
$parser = %fetch('foo.bar/heavy-xml-parser.casp')
$result = &$parser.parse($doc)
# $parser goes out of scope; the parser collects normally.
# Nothing was added to the load registry.
~~~

## `%fetch` vs `%import`

Caspian has two URL-loading operators. Pick based on what you're doing:

| Operator | Cached? | Same URL → same value? | When to use |
|---|---|---|---|
| `%import(url)` — a.k.a. `%(url)` | **Yes** (process-lifetime) | Yes | Ordinary library loading. Almost always what you want. |
| `%fetch(url)` | **No** | No (fresh object every call) | Heavy libraries used once. Large data loads processed and discarded. Anywhere caching would waste memory. |

**Default to `%import`.** The cache is small compared to the cost of re-running top-level code repeatedly, and identity preservation (same URL → same object) is what makes `$foo.class == $bar.class` work across the program. Only reach for `%fetch` when you know a load is truly one-shot.

## What runs at fetch time

Same as `%import`: the file's **top level runs once per call** — enough to produce the return value. **Method bodies do NOT run** at fetch time; they execute only when their method is called. If a method needs another object, that method's body calls `%fetch(...)` or `%import(...)` itself; the dependency load happens then, not at the original fetch.

## No identity across calls

Since `%fetch` doesn't cache, repeated calls with the same URL return **different objects**:

~~~caspian
$a = %fetch('foo.bar/gup.casp')
$b = %fetch('foo.bar/gup.casp')
$a == $b   # false — two different objects
~~~

If `foo.bar/gup.casp` returns a class, `$a.new()` and `$b.new()` produce instances whose `.class` fields are different objects. That's the trade-off you're accepting when you opt for `%fetch` over `%import`. If identity matters, use `%import`.

## When you need a fresh copy of something already loaded

If a URL is already cached via `%import`, and you want a **fresh** independent copy of what the source defines (not the shared cached version), `%fetch(url)` bypasses the cache and gives you a fresh one:

~~~caspian
$shared = %('foo.bar/gup.casp')       # cached via %import
$fresh = %fetch('foo.bar/gup.casp')   # fresh — runs top level again
$shared == $fresh                      # false — different objects
~~~

The cached version stays cached (still returned by future `%()` calls); your fresh copy lives independently.

## Bytes still cached

`%fetch` doesn't cache the returned VALUE, but the **byte cache** ([cache-dir](https://puck.uno/requirements/cache-dir)) still applies. If the URL's source has been downloaded before (this process or another), `%fetch` uses the cached bytes and doesn't re-download. Only the top-level execution runs on every call.

So `%fetch` isn't as expensive as "fetch source over network every time" — it's "run top level every time" with byte-level caching on the source itself. For a heavy XML-parser class definition, that's still a real cost (running the top level might allocate hundreds of objects), but no network round trip.

## The `as_self` option

`%fetch` supports the same `as_self: true` option that `%import` does. By default, a fetched object runs its methods under the puck-faucet's role (not the caller's), so a downloaded class's methods can't reach `%engine` or other caller capabilities. Passing `as_self: true` overrides that — the fetched object runs under the caller's role.

~~~caspian
$obj = %fetch('foo.bar/widget.casp')                 # default: puck-faucet role
$obj = %fetch('foo.bar/widget.casp', as_self: true)  # caller's role
~~~

Ownership semantics are identical to `%import`'s — see [`%import` § The `as_self` option](https://puck.uno/requirements/import#the-as_self-option). What DIFFERS is caching: `%fetch` doesn't cache regardless of `as_self`, so every call is a fresh execution producing a new object. The per-role cache complication that applies to `%import(url, as_self: true)` doesn't arise here.

**When to reach for `%fetch(url, as_self: true)` vs `%import(url, as_self: true)`:**

- **`%import(url, as_self: true)`** — you want your role's copy of this URL's value, cached and shared with other same-role calls to the same URL. Common for project-internal library files.
- **`%fetch(url, as_self: true)`** — you want a fresh copy running as your role, for THIS call only, unshared even with your own future imports. Rarer; use when the value must be genuinely one-shot.

## Summary

- `%fetch(url)` — fresh object every call, no caching, value collects when you drop the reference.
- `%import(url)` — cached, same URL → same value forever. Almost always what you want.
- Use `%fetch` for one-shot loads: heavy libraries used once, large data files processed and discarded, cases where caching would waste memory.
- Bytes are still cached; only the value is re-produced per call.
