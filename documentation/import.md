# `%import` — loading things by URL

~~~vibecode
{"vibecode": {
	"doc": "documentation_import",
	"role": "user-facing introduction to %import (and its short form %()) — what it does, the load-once cached-forever model (same as Python's import, Ruby's require, Node's require), the 'top-level is a declaration' contract, the shared-mutation caveat, the cache: false opt-out for one-shot loads, and %import.unload for explicit release.",
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

## When you don't want caching: `cache: false`

Some values shouldn't be kept in memory forever. A huge library you'll use once, a large data file you'll process and throw away — nothing to gain from pinning them in the load registry. Opt out with `cache: false`:

~~~caspian
$parser = %('foo.bar/heavy-xml-parser.casp', cache: false)
$result = &$parser.parse($doc)
# $parser goes out of scope; the parser collects normally.
# Nothing was added to the load registry.
~~~

Semantics of `cache: false`:

- **Always fresh execution.** The top level runs regardless of whether the URL is already in the load registry. You get a new value; the registry is not consulted.
- **Not stored.** The result is not added to the load registry. When you drop your reference to it, it collects like any other value.
- **Predictable.** `cache: false` means the same thing every time. What other code has imported doesn't affect it.

**Consequence: identity is not preserved for `cache: false` imports.** Two calls to `%('url', cache: false)` return two different objects; two `.new()`s from two `cache: false` imports of the same class produce instances whose `.class` fields are different objects. That's the trade-off — the identity guarantee applies only to cached imports.

**When to reach for it:**

- Loading a heavy library for a single operation and never again.
- Reading a large config or data file once at startup, then discarding.
- Any case where you know a fetched value is one-shot and would waste memory sitting in the registry.

**When NOT to reach for it:**

- Ordinary library imports. The registry is small compared to the cost of re-running top-level code repeatedly.
- Classes whose instances you'll create and use across the program. You want those instances to share identity via a single class object.
- Anything you're going to import in more than one place. Caching gives you sharing for free; opting out means each call site gets its own copy.

## `%import.unload('url')` — explicit release

For the case where a URL was cached and you want to release it (memory pressure, dev iteration after editing the source, changed your mind about installing something), `%import.unload('url')` drops the URL from the load registry. A subsequent `%('url')` runs the top level fresh and returns a new value.

~~~caspian
$class = %('foo.bar/gup.casp')          # cached
# ...done with it, want the memory back...
%import.unload('foo.bar/gup.casp')      # remove from load registry
# next import runs top level again:
$fresh = %('foo.bar/gup.casp')          # different object from $class
~~~

**A note.** If code elsewhere in the process is still holding a reference to the previously-cached value (existing instances of a class you unloaded, a variable bound to the class, etc.), those references still work — the value stays alive as long as anything holds it. Only future `%()` calls of the URL run fresh. That means for a brief window you may have two versions of the same URL's value coexisting — the old one held by existing references, the new one produced by the next import. Usually harmless; occasionally worth being aware of during dev iteration.

## `%import.flush_unused()` — release everything not being used

When you want to reclaim memory without naming URLs one at a time, `%import.flush_unused()` sweeps the whole load registry and drops any entry whose value isn't referenced from outside the registry. Returns the number of entries dropped.

~~~caspian
%import.flush_unused()   # returns 3, say — dropped three URLs' cached values
~~~

Rarely needed. The registry footprint is bounded by distinct URLs the program has ever imported, which for most programs is a small set. Reach for it when:

- Your program hit a memory limit and you want to reclaim what you can.
- You just finished a batch of tasks that loaded heavy one-off libraries and want to release them.
- Your program has a phase transition (setup done; runtime beginning) and wants to drop initialization-only libraries.

**Same rules as regular garbage collection**, applied to the registry: entries with any external reference (a live variable holding the value, an instance of a class you imported, another object that contains the value) are kept. Entries whose values are only pinned by the registry get dropped.

**When to use `flush_unused` vs `unload`:**
- **`unload('url')`** — you know exactly which URL to release.
- **`flush_unused()`** — you know a good moment to release, but don't want to enumerate.

Both are opt-in escape hatches. Ordinary programs never need to call either.

## Summary

- `%('url')` returns the value at the URL — same URL, same value, for the lifetime of the process. Same shape as Python's `import`, Ruby's `require`, Node's `require`.
- Downloadable files have a **declaration** at the top level, not a computation. Top level runs once at first import.
- Runtime mutations to imported values are visible to all other callers — same caveat as Python / Ruby / Node.
- `%('url', cache: false)` opts out of caching for one-shot loads. Always fresh, never stored, no identity across calls.
- `%import.unload('url')` drops a specific cached URL from the registry; a subsequent import runs fresh.
- `%import.flush_unused()` sweeps the registry, dropping any entry whose value isn't otherwise referenced. Rarely needed; escape hatch for memory pressure.
