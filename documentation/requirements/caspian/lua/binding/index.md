# Binding

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_lua_binding",
	"role": "design for how Caspian code accesses Lua libraries — the bridge from Caspian-side syntax to Lua-side functions, tables, and values. First-draft proposal: %lua['name'] sigil returns a wrapper object; type marshalling handles the common Lua→Caspian and Caspian→Lua conversions; Lua errors surface as Caspian exceptions. Applies to any Lua library available at runtime (bundled in the caspian binary, pre-installed to disk, or user-installed via `caspian --install-lua`).",
	"status": "first draft — access pattern, type marshalling shape, and error-bridging model proposed; details of userdata handling, callback direction (Lua calling back into Caspian), and metatable exposure open",
	"audience": "developers writing Caspian code that needs to call Lua libraries; anyone implementing the Caspian-to-Lua bridge"
}}
~~~

Caspian's runtime is Lua under the hood, but Caspian is its own language and Caspian code doesn't speak Lua directly. When a developer wants to use a Lua library — xml2lua, cjson, luasocket, or anything they've installed via `caspian --install-lua` — the language needs a way to reach into the Lua world and call that library's functions. This page specs how.

## Access pattern

Caspian code loads a Lua library through the `%lua` sigil, indexed by the module name (the same name you'd pass to Lua's `require`):

~~~caspian
$xml = %lua['xml2lua']
~~~

Under the hood, `%lua['xml2lua']` calls Lua's `require('xml2lua')` and wraps the returned value as a Caspian object.

`$xml` is a Caspian wrapper object whose properties and methods correspond to the Lua module's exports. If xml2lua's Lua-side surface is a table with `parse` and `tostring` functions, then from Caspian:

~~~caspian
$doc = $xml.parse $xml_string
$out = $xml.tostring $doc
~~~

Wrapper objects delegate every property access, method call, and index operation through to the underlying Lua value. The wrapper is created fresh on each `%lua[…]` access — but Lua's own `require` mechanism caches the underlying module, so repeated loads are cheap.

## Under the hood — the generic wrapper

**Developers do NOT write a Caspian wrapper for each Lua library.** There's one generic wrapper class that Caspian's runtime provides; it handles any Lua value by proxying property access, method calls, and index operations through to the Lua side.

### The mechanism

When `%lua['name']` is evaluated:

1. Caspian's runtime calls Lua's `require('name')` internally, getting back whatever the module returns (usually a table).
2. That Lua value gets wrapped in an instance of the generic wrapper class.
3. The wrapper is returned to Caspian code.

The wrapper implements Caspian's dynamic-access protocol — every `.foo`, `[key]`, and method call on the wrapper translates to the corresponding operation on the wrapped Lua value.

### Why one wrapper class handles everything

Lua's object model is unusually simple: every value is either a primitive (string, number, boolean, nil), a function, a table, or userdata. Even Lua's "objects" are just tables with metatables — no separate class system to model.

Because the surface area is that small, a single wrapper class can handle every Lua library. It doesn't need to know about xml2lua or cjson or luasocket specifically — it just needs to know how to look up a field in a table, call a function, index by an arbitrary key, and delegate through metatables when present.

### What the wrapper actually does

Say `$xml = %lua['xml2lua']`. Then:

- **`$xml.parse`** — wrapper's property-access looks up `"parse"` on the wrapped Lua table, gets back a Lua function, wraps that function in another wrapper instance (Lua functions are values too), returns the wrapper.
- **`$xml.parse $string`** — wrapper's method-call: marshals `$string` (Caspian string → Lua string), invokes the underlying Lua function, wraps the return value on its way back.
- **`$xml[$key]`** — wrapper's index: marshals `$key`, does `lua_table[key]`, wraps the result.

For chained access like `$doc.rss.channel.item`, each `.rss`, `.channel`, `.item` is a property lookup on the previous wrapper. Each returns a new wrapper for the intermediate table. The chaining works because wrappers-around-tables are indistinguishable from wrappers-around-any-other-table.

### When developers DO write a Caspian class on top

Optionally, a developer can write a Caspian class that wraps `%lua['name']` internally and exposes a more Caspian-idiomatic API — Caspian-specific method names, validation, error mapping to particular exception classes, hidden Lua-side arguments, etc.

That's a **convenience layer**, never a requirement. Any Lua library is directly usable via the generic wrapper without a hand-written Caspian class in front of it.

### Caching

- **Lua's own `require` caches** the module — repeated `require('xml2lua')` calls all return the same underlying Lua table.
- **The Caspian wrapper is not cached** — each `%lua['xml2lua']` call produces a fresh wrapper instance around the (same) underlying table.

That's the natural pattern: the wrapper is lightweight (essentially a pointer + a metatable), so there's no benefit to reusing wrapper instances. And it means two Caspian variables holding wrappers around the same Lua value are still distinct Caspian objects — separate lifecycles, separate role attribution.

## Type marshalling

Values crossing the boundary get converted in both directions:

| Lua | ↔ | Caspian |
|---|---|---|
| `nil` | ↔ | `null` |
| `boolean` | ↔ | boolean |
| `number` | ↔ | number |
| `string` | ↔ | string |
| `table` (integer-keyed, 1..n) | ↔ | array |
| `table` (string-keyed) | ↔ | hash |
| `table` (mixed) | ↔ | hash with numeric string keys |
| `function` | ↔ | callable Caspian object |
| `userdata` | → | opaque Caspian wrapper |
| Caspian object | → | userdata (with a metatable proxying back to Caspian) |

Marshalling is **lazy for containers** — the wrapper doesn't recursively convert a Lua table when you receive it. Field access on the Caspian side triggers a per-field conversion at read time. This avoids duplicating large data structures across the boundary.

## Method calls

Method-call syntax on a Caspian wrapper translates to Lua's colon-call semantics:

~~~caspian
$dir.method $arg1, $arg2
~~~

...becomes, on the Lua side:

~~~lua
dir:method(arg1, arg2)
~~~

Explicit function calls (not method calls) map to Lua's dot-call:

~~~caspian
$xml.parse $string
~~~

...becomes:

~~~lua
xml.parse(string)
~~~

Note: `.` in Caspian is currently the method separator, so distinguishing "method call" vs "function called on a namespace" needs a convention. Open decision — see below.

## Error handling

Lua errors — whether from `error()` or from failed C calls — surface as Caspian exceptions:

~~~caspian
try
	$doc = $xml.parse $malformed
catch $e
	# $e is a Caspian exception; $e.message is the Lua error string
end
~~~

The exception's class reflects the Lua error's kind where possible (runtime error, out-of-memory, etc.), and the message field carries whatever the Lua side raised.

Conversely, Caspian exceptions thrown inside a callback that Lua invokes propagate back as Lua errors, then re-emerge as Caspian exceptions if Caspian eventually catches them.

## Working example

Parsing an XML document from Caspian using the pre-installed [xml2lua](../../core/pre-installed-libs):

~~~caspian
%vibecode: <<END
	role: parse an RSS feed and print each item title
END

$xml = %lua['xml2lua']
$doc = $xml.parse '<rss><channel><item><title>Hello</title></item></channel></rss>'

$items = $doc.rss.channel.item
if $items.length > 0
	for $item in $items
		%stdout.print $item.title
	end
end
~~~

## Impact on the floppy budget

The generic wrapper is pure Lua code — part of Caspian's engine/stdlib. Rough estimate: **10–30 kb of Lua source**, depending on how much error-handling and edge-case polish gets baked in (a straightforward `__index` / `__call` / `__newindex` implementation is small; robust type marshalling, error bridging, userdata identity handling, and metatable transparency each add a bit).

The wrapper's ~20 kb is now reflected in the [ships-with-Caspian bundle](../../core/) — total 1095 kb, 345 kb of headroom against the 1.44 MB floppy target. Negligible impact on remaining room.

No new C extension is needed for the basic wrapper — Lua's built-in metatable mechanism handles all the dispatch. If profiling later reveals hot paths that would benefit from a C-level fast path (a specialized `__index` shortcut for common lookups, say), we can add a small C helper, but that's an optimization, not a requirement for the feature to ship.

**Where the weight lands:** the wrapper is part of Caspian's engine (Executable tier). The **Caspian engine + stdlib** row in the bundle table currently shows 260 kb; that number nudges up by roughly the wrapper's size once the binding lands.

## Open decisions

- **Method vs namespace-function distinction.** Caspian's `.` is the method separator; Lua distinguishes `foo:method()` (self as first arg) from `foo.func()` (no self). How does Caspian syntax pick between the two? Options: infer from wrapper metadata; explicit `.self_call` vs `.no_self`; convention that starts assuming one and lets the other be overridden.
- **Callback direction.** Lua libraries that accept callbacks (event handlers, iterators, etc.) need to call *back* into Caspian code. How does a Caspian function or closure get passed to a Lua-side call? Presumably transparent for pure functions; metatables and self-references get thornier.
- **Metatable exposure.** Lua's object-orientation is built on metatables. When a wrapper's underlying Lua value has a metatable (methods, `__index`, `__call`, etc.), how much of that is surfaced through the Caspian wrapper? Full transparency is powerful but exposes Lua idioms Caspian normally hides.
- **Userdata identity.** When a Lua function returns userdata (an opaque C-side handle), we wrap it as an opaque Caspian object. Do calls through the wrapper preserve identity (same underlying userdata → same wrapper object each time)? Matters for equality checks, weak tables on the Lua side, GC finalizers.
- **Load-time vs first-use.** Should `%lua['name']` fail immediately if the module isn't available, or defer until the first method call? Immediate is safer; deferred is more forgiving in scripts that conditionally use libs.
