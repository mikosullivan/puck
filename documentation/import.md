# `%import` — loading things by URL

~~~vibecode
{"vibecode": {
	"doc": "documentation_import",
	"role": "user-facing introduction to %import (and its short form %()) — what it does, the load-once cached-forever model (same as Python's import, Ruby's require, Node's require), the 'top-level is a declaration' contract, the shared-mutation caveat, %import.uncache for dropping a specific cache entry, and %import.flush_unused for sweeping unreferenced entries. For transient one-shot loads that shouldn't be cached, see the companion %fetch operator (documentation/fetch).",
	"status": "user doc — accompanies (does not duplicate) the spec at requirements/import",
	"audience": "Caspian programmers loading libraries, classes, or values from URLs"
}}
~~~

## What it does

`%import(url)` — usually written in its short form `%(url)` — loads whatever's at that URL and returns its top-level value. What you get back is whatever the code at that URL evaluates to: a class, a function, a hash, whatever.

~~~caspian
$greetings = %('foo.bar/greetings.casp')
$greetings.hello    # invokes a method the loaded value defined
~~~

Under the hood: fetch the source (from local cache or the network) → transpile to CaspM → run the top level → return whatever it produced. The URL is the value's identity; where the bytes come from (local cache, GitHub, direct HTTP) is decided by the fetcher array — see [fetch-discovery](https://puck.uno/requirements/fetch-discovery).

## Same URL, same value — for the life of the process

Two calls to `%()` with the same URL return the **same value**:

~~~caspian
$a = %('foo.bar/greetings.casp')
$b = %('foo.bar/greetings.casp')
$a == $b    # true — literally the same object
~~~

First import runs the top-level code and stores the result. Every later import of the same URL is a cheap lookup returning that stored value. The value stays for the lifetime of the process.

Same model as **Python's `import`**, **Ruby's `require`**, and **Node's `require`**. If you've used any of those, this will feel familiar: once loaded, always loaded, same identity.

Consequence: if `%('foo.bar/gup.casp')` returns a class, every caller that imports the same URL gets the same class object. Instances share identity — `$foo.class == $bar.class` holds for any two instances of that class, regardless of which caller created them.

## The contract on downloadable files

The top level of a downloadable file **runs once per process**, at first import. What it evaluates to is what gets stored and returned by every subsequent import. Design accordingly.

**Do — top level defines a stable value:**

~~~caspian
# foo.bar/greetings.casp
class
	method &hello()
		puts 'hello, world'
	end
end
~~~

Returns a class. Every `%()` returns the same class. Instances share identity.

**Don't — top level generates a fresh value:**

~~~caspian
# foo.bar/uuid-getter.casp
&('core:random').uuid
~~~

Top level runs once, generates one UUID, stores it. Every `%()` for the rest of the process returns the same UUID. Almost certainly not what you wanted.

**Do — dynamic behavior wrapped in a callable:**

~~~caspian
# foo.bar/uuid-maker.casp
function &()
	&('core:random').uuid
end
~~~

Returns a function. Every `%()` returns the same function (stored once, returned forever). To get a fresh UUID, invoke it:

~~~caspian
$fn = %('foo.bar/uuid-maker.casp')
&$fn    # fresh UUID
&$fn    # different fresh UUID
~~~

**Rule of thumb.** The top level of a downloadable file is a declaration that runs once at first import. If dynamic behavior is needed, return a callable and let the caller invoke it. Same principle applies in Python (top-level `MODULE_LEVEL = get_uuid()` vs. defining `def get_uuid()` and calling it), Ruby, and Node.

## Shared mutation

Since every caller of a URL gets the **same** object, **runtime mutations are visible to everyone**. Add a method to an imported class, and every other caller of that URL sees the added method too. Mutate a field in an imported hash, and every other holder sees the mutation.

~~~caspian
# somewhere:
$class = %('foo.bar/gup.casp')
$class.inherits $other_class    # runtime mutation

# elsewhere, unrelated code:
$class_elsewhere = %('foo.bar/gup.casp')
# $class_elsewhere DOES inherit from $other_class.
# There's only one object; you're both looking at it.
~~~

Same shape as monkey-patching an imported module in Python, opening a class in Ruby, or mutating an exported object in Node. Advice is the same across languages:

- **Prefer editing the source over runtime mutation.** If a class should inherit from `$other_class`, edit the source.
- **If you must mutate at runtime, understand it's process-wide.** Every future caller of the URL will see the mutation.
- **Need a fresh copy?** Don't import again — you'll get the shared value. For a class, use `.new()` to get a fresh instance. If the class provides a `.clone` or `.copy` method, use that.

## When you don't want caching: use `%fetch`

Some values shouldn't be kept in memory forever. A huge library you'll use once, a large data file you'll process and throw away — nothing to gain from pinning them in the load registry. Use the companion `%fetch` operator instead — every call runs top level fresh and returns a value that isn't cached:

~~~caspian
$parser = %fetch('foo.bar/heavy-xml-parser.casp')
$result = &$parser.parse($doc)
# $parser goes out of scope; the parser collects normally.
~~~

See [documentation/fetch](https://puck.uno/documentation/fetch) for the full story on when to reach for `%fetch` over `%import`.

## `%import.uncache('url')` — drop the cache entry

For the case where a URL was cached and you want to drop it from the cache (memory pressure, dev iteration after editing the source, changed your mind about installing something), `%import.uncache('url')` removes the URL from the load registry. A subsequent `%('url')` runs the top level fresh and returns a new value.

~~~caspian
$class = %('foo.bar/gup.casp')          # cached
# ...done with it, want the memory back...
%import.uncache('foo.bar/gup.casp')      # remove from load registry
# next import runs top level again:
$fresh = %('foo.bar/gup.casp')          # different object from $class
~~~

**The name is deliberately "uncache," not "unload."** The operation removes the URL from the cache; it doesn't destroy the loaded value. If `$class` above is still bound to a variable when `%import.uncache` runs, `$class` keeps working — the value stays alive as long as anything holds it. Only the CACHE entry is dropped; future `%(url)` calls that would have hit the cache now run fresh.

**Role scope.** From user role, uncache drops all entries for the URL across every role (both the default puck-faucet entry AND every per-role `as_self` entry). From any other role, uncache only drops entries under the caller's own role.

**Two live values may briefly coexist.** For a brief window after uncache, you may have two versions of the same URL's value coexisting — the old one held by existing references, the new one produced by the next import. Usually harmless; occasionally worth being aware of during dev iteration.

## The `as_self` option

`%import` (and its companion [`%fetch`](https://puck.uno/documentation/fetch)) support an `as_self: true` option that changes which role an imported object's methods run under. By default, an imported object runs its methods under the puck-faucet's role (not yours), so a downloaded class's methods can't reach `%engine` or other caller capabilities — a security default. Passing `as_self: true` opts in to running the object's methods under the caller's role.

~~~caspian
$obj = %('foo.bar/widget.casp')                       # default: puck-faucet role
$obj = %import('foo.bar/widget.casp', as_self: true)  # your role — object can reach your capabilities
~~~

Use `as_self: true` when the loaded object is trusted enough to act with your authority — typically your own project's objects, or objects you deliberately want to fold into your own identity.

**How `as_self` interacts with the cache:** the cache is keyed by URL AND role. Default imports (no `as_self`) all share one entry — everyone gets the same puck-faucet-owned object regardless of which role called. `as_self: true` imports get per-role entries — each role that imports the same URL as_self gets its own copy. If you (as user) do `%import(url, as_self: true)` and another role also does `%import(url, as_self: true)`, you each have your own class object; instances from your copy have a different `.class` than instances from theirs. Within your own role, repeated as_self imports of the same URL share (cache hit); across roles, they don't.

**Class identity across roles.** For default imports (no `as_self`), class identity holds across roles — everyone's `%(url)` returns the same class object. For `as_self` imports, class identity holds only within a role. If you pass an as_self-loaded instance from your role to another role, the receiving role's `%(url, as_self: true)` returns a DIFFERENT class from your instance's `.class`. That's the intended behavior — as_self is opt-in role personalization, and different roles claiming ownership get separate values.

See [`%import` spec § The `as_self` option](https://puck.uno/requirements/import#the-as_self-option) and [`%import` spec § Per-role caching](https://puck.uno/requirements/import#per-role-caching) for the full details. The same option works identically on `%fetch` for the ownership question, but `%fetch` doesn't cache regardless of `as_self`.

## `%import.flush_unused()` — release everything not being used

When you want to reclaim memory without naming URLs one at a time, `%import.flush_unused()` sweeps the load registry and drops any entry whose value isn't referenced from outside the registry. Returns the number of entries dropped.

~~~caspian
%import.flush_unused()   # returns 3, say — dropped three URLs' cached values
~~~

**Role scope.** From user role, this sweeps everything across all roles (user is the god role). From any other role, it sweeps only entries under the caller's own role — you can't reach into another role's cache. Same rule applies to [`%import.uncache(url)`](#import-uncache-url-drop-the-cache-entry): user's uncache is a clean sweep across roles; another role's uncache only drops that role's entry.

Rarely needed. The registry footprint is bounded by distinct URLs the program has ever imported (times the roles that used `as_self`), which for most programs is a small set. Reach for it when:

- Your program hit a memory limit and you want to reclaim what you can.
- You just finished a batch of tasks that loaded heavy one-off libraries and want to release them.
- Your program has a phase transition (setup done; runtime beginning) and wants to drop initialization-only libraries.

**Same rules as regular garbage collection**, applied to the registry: entries with any external reference (a live variable holding the value, an instance of a class you imported, another object that contains the value) are kept. Entries whose values are only pinned by the registry get dropped.

**When to use `flush_unused` vs `uncache`:**
- **`uncache('url')`** — you know exactly which URL to release.
- **`flush_unused()`** — you know a good moment to release, but don't want to enumerate.

Both are opt-in escape hatches. Ordinary programs never need to call either.

## Summary

- `%('url')` returns the value at the URL — same URL, same value, for the lifetime of the process. Same shape as Python's `import`, Ruby's `require`, Node's `require`.
- Downloadable files have a **declaration** at the top level, not a computation. Top level runs once at first import.
- Runtime mutations to imported values are visible to all other callers — same caveat as Python / Ruby / Node.
- For one-shot loads that shouldn't be cached, use [`%fetch`](https://puck.uno/documentation/fetch) — always fresh, never stored, no identity across calls.
- `%import.uncache('url')` drops a specific cached URL from the registry; a subsequent import runs fresh.
- `%import.flush_unused()` sweeps the registry, dropping any entry whose value isn't otherwise referenced. Rarely needed; escape hatch for memory pressure.
