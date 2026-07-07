# Bare function
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_functions_types_bare",
	"role": "spec for the bare-function type — the type most languages just call a 'function'. Declared with the `function` keyword. No captured outer scope, no `%self`, no receiver. The body only sees its arguments, its locals, and `%chain`. Sealed scope is central to Caspian's security model — it is why untrusted code is safe to run. Covers sealed scope / security model, definition (assignment form and named form), the `.call` / `&name` equivalence, the method surface a function object carries (`.call`, `.params`, everything on `.object`), parameter mechanics (metadata, optional/required, `*args`, `**opts`, lazy, public/private names, programmatic access), return, and `%call`.",
	"status": "draft — surface and parameter mechanics filled in; deeper semantics of first-class value handling and lifecycle still to be spec'd",
	"audience": "developers writing Caspian; parser implementers",
	"example_universe": "star trek — picard, ranks, ships, registries"
}}
~~~

A **bare function** is a standalone callable. It takes arguments and produces a value; that's it.

Inside the body:

- **No `%self`.** The bare function isn't bound to any receiver. Referring to `%self` inside a bare function raises.
- **No captured outer scope.** Even if the bare function is defined inside another function's body, it does not capture that outer function's locals. Names defined outside the body are not reachable from inside it.
- **What's reachable.** Only the arguments passed in (via the parameter list), the names defined locally within the body, and [`%chain`](https://puck.uno/documentation/requirements/caspian/chain/).

## Sealed scope

A bare function's body can see exactly two things:

1. **Its parameters and locals.** The arguments the caller passed, and anything the body defines with `$x = ...`.
2. **`%chain`.** The ambient capability channel — the global methods (`%now`, `%stdout`, `%net`, ...) that the caller had, plus anything the caller placed on the chain before calling.

Nothing else. Not the outer function's locals if the bare function is defined inside another function. Not the enclosing script's top-level variables. Not other functions defined nearby. Not any state from wherever the bare function was defined. The definition site's environment is invisible from inside the body.

### Why this is Caspian's security model

**Sealed scope is what makes untrusted code safe to run.** Hand a bare function to code you don't trust, and the function can only reach:

- What it's given at the call site (arguments).
- What the caller explicitly hands down through `%chain`.

There is no ambient reach into the caller's data. No introspection into the enclosing lexical scope. No back-channel through closure capture — bare functions don't close over anything, by construction. If the caller wants the function to have file access, they grant it on `%chain`. If they don't grant it, the function has no path to it. Capabilities are handed down one surface at a time, on `%chain`, and default-deny for anything the caller hasn't explicitly passed across a role boundary.

The property depends on both halves working together: sealed lexical scope keeps the function from reading anything by name, and `%chain`'s per-frame capability model keeps ambient surfaces from leaking in without explicit grant. Bare functions supply the first half; `%chain` supplies the second. Neither half alone would be enough — a language with sealed lexical scope but ambient globals is still a wide-open attack surface, and a language with capability-based ambient access but lexical capture leaks state through the closure. Caspian's guarantee holds because both mechanisms line up.

See [`%chain`](https://puck.uno/documentation/requirements/caspian/chain/) for how the capability side works — grant propagation, role boundaries, default-deny vs. default-grant per surface.

## Definition

**Functions are objects.** A function is a first-class value like any other — a class instance that happens to be callable. The formal way to define one is to use the `function` command and assign the result to a variable:

~~~caspian
$foo = function()
end
~~~

The `function() ... end` construct evaluates to a function object; the assignment stores it at `$foo`. From that point on, `$foo` holds a callable value that can be invoked, passed around, stored in a hash or array, or handed to any code that accepts a function argument.

The empty parameter list and empty body above is the minimum legal form. Add parameters and body content as needed:

~~~caspian
$greet = function($name)
	puts 'Hello, ' + $name
end
~~~

**Two call forms, exactly equivalent.** Because functions are objects, they carry a `.call` method — and `&name` is sugar for it. The two forms below do exactly the same thing:

~~~caspian
&greet 'alice'
$greet.call 'alice'
~~~

Use whichever reads better in context. Full call-site syntax (keyword args, splat expansion, method calls) lives on the [call](call) page.

**Named form.** The same definition can be written with the name baked into the `function` construct itself:

~~~caspian
function &greet()
end
~~~

This is exactly equivalent to `$greet = function() end` — the function is created and bound to `$greet` in one step. Both forms produce the same result: a function object accessible as `$greet` and callable as `&greet`. Use whichever reads better in context — the named form is common for top-level definitions where the name is fixed, and the assignment form is common when the function is one value among others (stored in a hash, returned from another function, etc.).

## Method surface

A function object exposes a small set of methods directly, plus everything on the [`object` namespace](https://puck.uno/documentation/requirements/caspian/built-in-classes/object) that every value carries.

**Direct methods on a function:**

| Method | Purpose |
|---|---|
| [`.call(args)`](call) | Invoke the function with the given arguments. `$fn.call args` and `&fn args` produce identical results; the sigil form is sugar for `.call`. |
| `.params` | Hash of parameter metadata objects, keyed by private name (without the `$`). Each entry carries `.lazy`, `.optional`, `.default`, and `.public_name` properties. See [§ Parameters](#parameters) for the full spec of what each entry holds. |

**Cross-cutting `object` methods:**

Everything on the `.object` namespace is available — `$fn.object.freeze`, `$fn.object.isa?(...)`, `$fn.object.classes`, `$fn.object.jail(...)`, and so on. Function objects use the same `object` surface every other value does; they don't add anything special or hide anything from it. See [built-in-classes/object](https://puck.uno/documentation/requirements/caspian/built-in-classes/object) for the catalog.

## Parameters

Every parameter is an object with a metadata hash. The metadata controls how the parameter behaves — evaluated lazily, whether it's optional, what public name it exposes at the call site, and so on. Metadata can be declared inline in the signature or set programmatically on the function object after definition; both forms are equivalent.

### Basic form

Parameters are declared in the signature, left to right:

~~~caspian
$foo = function($name, $rank)
	return null
end
~~~

**Parameters are required by default.** The form above declares `$name` and `$rank` as required — calling `&foo` without both raises. Optionality is opt-in via the `optional:` (or `default:`) metadata; see [§ Required and optional](#required-and-optional) below.

Each parameter has two names:

- **Private name** — the `$`-prefixed name used inside the function body.
- **Public name** — the name used at the call site for keyword arguments. Defaults to the private name with the leading `$` stripped (so `$name` → `name`). Override with the `public_name` metadata property (see below).

### Inline metadata

Attach metadata with a hash literal after the parameter name:

~~~caspian
$evaluate = function($left: {lazy: true}, $right: {lazy: true})
	return null
end
~~~

The inline hash is sugar for setting properties on the parameter object. The two forms below are identical:

~~~caspian
$foo = function($bar: {lazy: true})
	return null
end
~~~

~~~caspian
$foo = function($bar)
	return null
end

$foo.params['bar'].lazy = true
~~~

Inside the metadata hash, use a colon followed by a single space (`lazy: true`, not `lazy:true`). Between entries, no space before the comma and a single space after (`optional: true, default: 'ensign'`).

### Known metadata properties

| Property | Type | Default | Description |
|---|---|---|---|
| `lazy` | boolean | `false` | If `true`, the argument is not evaluated before the call. A zero-argument callable is passed instead; the function calls `.call` on it to evaluate. Enables short-circuit and deferred evaluation. |
| `optional` | boolean | `false` | If `true`, the parameter is optional, and **all subsequent parameters become optional too** (propagation rule — see below). An optional parameter with no default receives `null` when omitted. |
| `default` | expression | `null` | Expression re-evaluated on each omission to produce the value. Setting a default implicitly makes the parameter optional. See [§ Default expressions](#default-expressions). |
| `public_name` | string | private name minus `$` | Public (call-site) keyword name for this parameter. |

### Public and private names

Each parameter has a private name (used inside the function) and a public name (used at the call site). Default mapping strips the leading `$` from the private name — `$name` → `name`, `$rank` → `rank`:

~~~caspian
$foo = function($name, $rank)
	return null
end

&foo name: 'picard', rank: 'captain'
~~~

Override with the `public_name` metadata property when the private name would be a poor external name:

~~~caspian
$foo = function($title_sent: {public_name: 'title'})
	return null
end

&foo 'picard', title: 'captain'
~~~

Inside the function, the parameter is `$title_sent`; from the outside, it's `title`. Calling with `title_sent:` (the private name) raises — the call site can only use public names.

### Required and optional

Parameters are **required by default**. Mark one optional with `optional: true`:

~~~caspian
$foo = function($name, $rank: {optional: true}, $phrase)
	return null
end
~~~

**Propagation rule.** Once a parameter is marked `optional: true`, all parameters after it are implicitly optional too. The signature above is equivalent to:

~~~caspian
$foo = function($name, $rank: {optional: true}, $phrase: {optional: true})
	return null
end
~~~

| Parameter | Status |
|---|---|
| `$name` | required |
| `$rank` | optional (explicitly) |
| `$phrase` | optional (inherited) |

Why: positional calls bind left to right. If only `$rank` were optional and `$phrase` required, `&foo 'picard'` would be ambiguous — the caller skipped one argument, but which one? Propagation eliminates that ambiguity — once optional starts, the caller may stop providing positional arguments at any point.

**Defaults.** An omitted optional parameter takes its `default` value if one is set, otherwise `null`:

~~~caspian
$foo = function($name, $rank: {optional: true, default: 'ensign'})
	return null
end

&foo 'picard'              # $rank = 'ensign'
&foo 'picard', 'admiral'   # $rank = 'admiral'
~~~

Setting `default` implicitly marks the parameter optional, so `{default: 'x'}` is equivalent to `{optional: true, default: 'x'}`. The default's evaluation semantics are spec'd next.

### Default expressions

The value after `default:` is treated as an **expression**, not a pre-evaluated value. The engine re-evaluates the expression on **each** call where the parameter is omitted — every omission produces a fresh result.

Two consequences that matter:

**No shared mutable defaults.** Each omission constructs a new object, so `default: []` gives every caller its own empty array. There's no Python-style shared-list trap where a mutable default silently accumulates state across calls.

~~~caspian
$foo = function($opts: {default: []})
	$opts.push 'x'
	return $opts
end

&foo   # returns ['x']
&foo   # returns ['x'] — fresh array; not ['x', 'x']
~~~

**Defaults can depend on call-time context.** Because the expression runs at call time, it can name anything reachable at that moment — `%chain`, `%now`, any surface the function has.

~~~caspian
$log = function($stamp: {default: %now})
	return $stamp
end

&log   # returns whatever %now is right now — different value on each call
~~~

**Introspection.** Reading `$foo.params['opts'].default` returns the **thunk**, not the result. To read the value once, call it explicitly:

~~~caspian
$sample = $foo.params['opts'].default.call
~~~

If per-parameter default-value inspection turns out to be common, a `.default_value` accessor that calls the thunk once may be added — TBD.

#### Implementation notes

**The sugar equivalence.** `.default` on a parameter object is a slot that holds a callable. The inline `default: X` form in the signature is sugar for assigning a bare function to that slot. These two definitions are equivalent:

~~~caspian
$myfunc = function($foo: {default: 'bar'})
	return null
end
~~~

is equivalent to:

~~~caspian
$myfunc = function($foo)
	return null
end

$myfunc.params['foo'].default = function()
	return 'bar'
end
~~~

Both write the same callable onto `.default`. Reading `$myfunc.params['foo'].default` returns the stored callable; invoking `.call` on it evaluates the expression and produces the value.

**Capture note.** Because the inline sugar produces a bare `function`, the default expression has no captured outer scope. It can name `%chain` (which is per-frame and always available inside a function body), but it cannot reference locals from the surrounding lexical scope. If a default genuinely needs to capture an outer local, assign a closure explicitly:

~~~caspian
$prefix = 'ensign '

$myfunc.params['foo'].default = closure()
	return $prefix + &random_name
end
~~~

**Callable signature.** `.default.call` is invoked with **zero arguments** — the runtime never passes anything in. So the callable assigned to `.default` must accept an empty argument list. A signature with required parameters won't work:

~~~caspian
# does not work — $blah is required, but nothing is passed
$myfunc.params['foo'].default = function($blah)
	return $blah
end
~~~

The parameter list must be empty, or every parameter must be optional. The bare form the inline sugar produces (`function() return X end`) satisfies this automatically.

**How defaults are applied at call time.** When the runtime detects that a parameter is optional and its argument was omitted, it invokes the stored callable's `.call` and binds the result. The callable runs against the function frame's `%chain`, not the caller's — matching the intuition that defaults are function-side behavior.

Sketch of the per-omission step:

~~~caspian
if $param.default != null
	$value = $param.default.call
else
	$value = null
end
~~~

One follow-on detail worth flagging:

- **No memoization.** Nothing in this model caches the callable's result. An expensive default is re-run on every omission. If per-call re-evaluation becomes a hot path later, a `default_once: true` (or similar) metadata property could layer memoization on top — but the base semantics remain "fresh each time."

### Lazy parameters

A `lazy: true` parameter is the mechanism behind binary-operator evaluators and any other construct that needs deferred evaluation. The caller's expression is wrapped in a zero-argument callable before the call; inside the function, `.call` evaluates it:

~~~caspian
class # ander
	method evaluate($left: {lazy: true}, $right: {lazy: true})
		if ! $left.call
			return false
		end

		return $right.call
	end
end
~~~

`$foo && $bar` desugars to a call on this evaluator with two lazy arguments. `$right.call` is never reached if `$left.call` returns false — genuine short-circuit evaluation with no special parser support.

### Rest positional: `*args`

A `*args` parameter captures all remaining positional arguments into an array:

~~~caspian
$foo = function($name, *args)
	return null
end

&foo 'picard', 'admiral', 'flagship'
# $name = 'picard'
# $args = ['admiral', 'flagship']
~~~

If no extra positional arguments are passed, `$args` is an empty array.

### Rest named: `**opts`

A `**opts` parameter captures all remaining named arguments into a hash, keyed by their public names:

~~~caspian
$foo = function($name, **opts)
	return null
end

&foo 'picard', ship: 'enterprise', registry: 'ncc-1701'
# $name = 'picard'
# $opts = {ship: 'enterprise', registry: 'ncc-1701'}
~~~

If no extra named arguments are passed, `$opts` is an empty hash. Without `**opts`, an unknown named argument at the call site raises; with `**opts`, unknown names are quietly absorbed into the hash.

### Combined rest

A signature can combine normal parameters, `*args`, and `**opts` — in that order. At most one `*args` and one `**opts` per signature:

~~~caspian
$foo = function($name, *args, **opts)
	return null
end

&foo 'picard', 'admiral', 'flagship', ship: 'enterprise'
# $name = 'picard'
# $args = ['admiral', 'flagship']
# $opts = {ship: 'enterprise'}
~~~

### Programmatic access

Every function object exposes a `params` hash in its bucket. Each key is a parameter name (without `$`); each value is that parameter's metadata object.

~~~caspian
$foo = function($bar, $gup)
	return null
end

$foo.params['bar'].lazy = true
$foo.params['gup'].optional = true
$foo.params['gup'].default = 'ensign'
~~~

Programmatic access is useful for frameworks, validators, and generated functions where the metadata isn't known until runtime.

### Definition errors

These raise when the function is defined, not when called:

- **Duplicate public names.** Two parameters resolve to the same public name.
- **Public/private collision.** A `public_name:` override collides with another parameter's private name.
- **Multiple `*args`.** At most one `*args` per signature.
- **Multiple `**opts`.** At most one `**opts` per signature.

### Call-site details

Argument binding order, the positional-until-named rule, splat expansion (`*array` / `**hash`), and mixed positional/named calls all live on the [#call](call) page.

### Open questions

- Whether a `.default_value` accessor is worth adding as sugar for `param.default.call` when introspection turns out to be common (see [§ Default expressions](#default-expressions)).

## return

Exits with `return $value` (bare keyword) or `%call.return $value`. Both raise the return exception targeted at this function's frame; the engine catches at the function boundary and hands the value back as the call's return value. See [exceptions § ReturnException](https://puck.uno/documentation/requirements/caspian/exceptions/#returnexception).

## `%call`

Inside a bare function's body, `%call` is a global that returns the **call object** — a first-class object representing the in-progress call. It carries who made the call (`%call.role`), any blocks the caller passed, and the primitives for ending the call early (`%call.return`) or yielding back to a passed block. `%call` is scoped per frame — each function invocation has its own — and it's owned by the caller's role, not the function's.

Full spec, including the yield / dispatcher surface used for DSL-style blocks, is on [`%call`](https://puck.uno/documentation/requirements/caspian/global-methods/call/).

## When a function is bare

A function is a bare function when it's declared with the `function` keyword. That keyword is what makes it bare — no captured outer scope, no receiver — regardless of where the declaration appears. `function` can appear anywhere in a Caspian program: top level, inside another function's body, inside a closure, inside a method. See [closure](closure) and [method](method) for the other two types.