# Bare function
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions_bare",
	"role": "spec for the bare-function type — the type most languages just call a 'function'. Declared with the `function` keyword. No captured outer variables, no `%self`, no receiver. Two declaration forms with DIFFERENT effect: `function &name(...) ... end` adds `name` as a method on the enclosing Module (siblings reach each other via `%module.name` — no variable binding, no `&name` shorthand for Module methods); `$var = function(...) ... end` binds a local callable variable and does NOT touch the Module. Both forms produce fully-hermetic function bodies — the body sees only args, locals, and `%chain`. Cross-sibling access is via explicit `%module` lookup, always — Caspian does NOT walk up implicitly from `&name` to `%module.name`. There are no mystery variables in a function's namespace. See modules/index for the Module concept the named form plugs into. Covers the two forms, the `.call` / `&name` equivalence for variable-held callables, the method surface a function object carries (`.call`, `.params`, everything on `.object`), parameter mechanics (metadata, optional/required, `*args`, `**opts`, lazy, public/private names, programmatic access), return, and `%call`.",
	"status": "draft — surface and parameter mechanics filled in; the Module-method model is settled as the sibling-access mechanism (supersedes the earlier sibling-&-name-capture design)",
	"audience": "developers writing Caspian; parser implementers",
	"example_universe": "star trek — picard, ranks, ships, registries"
}}
~~~

A **bare function** is a standalone callable. It takes arguments and produces a value; that's it.

Inside the body:

- **No `%self`.** The bare function isn't bound to any receiver. Referring to `%self` inside a bare function raises.
- **No captured outer variables.** Even if the bare function is defined inside another function's body, it does not capture that outer function's locals or any other variable binding.
- **What's reachable.** The arguments passed in (via the parameter list), the names defined locally within the body, [`%chain`](https://puck.uno/requirements/chain/), and — when the function was declared with the named form (`function &name(...) end`) — the surrounding [Module](https://puck.uno/requirements/modules/)'s methods and classes via [`%module`](https://puck.uno/requirements/global-methods/module/).

## Sealed scope

A bare function's body can see:

1. **Its parameters and locals.** The arguments the caller passed, and anything the body defines with `$x = ...`.
2. **`%chain`.** The ambient capability channel — the global methods (`%stdout`, `%net`, `%fetch`, ...) that the caller had, plus anything the caller placed on the chain before calling.
3. **Its own Module via `%module`.** Because the body is inside SOME code-container, `%module` returns the innermost containing Module. What's on that Module — `%module.methods`, `%module.classes` — is only the source's explicitly-named declarations at that container's scope. See [modules](https://puck.uno/requirements/modules/) for what a Module exposes and (importantly) what it does NOT expose.

That's the full list. No outer function's locals, no enclosing script's top-level variables, no state from wherever the bare function was defined. The definition site's variable environment is invisible from inside the body.

### Why this is Caspian's security model

**Sealed scope is what makes untrusted code safe to run.** Hand a hermetically-declared bare function (`$foo = function(...) end`) to code you don't trust, and the function can only reach:

- What it's given at the call site (arguments).
- What the caller explicitly hands down through `%chain`.

There is no ambient reach into the caller's data. No introspection into the enclosing lexical scope. No back-channel through closure capture. If the caller wants the function to have file access, they grant it on `%chain`. If they don't grant it, the function has no path to it. Capabilities are handed down one surface at a time, on `%chain`, and default-deny for anything the caller hasn't explicitly passed across a role boundary.

Assignment-form functions (`$foo = function(...) end`) are the maximally hermetic form: their body has no `%module` at Module scope (the function itself isn't published on any Module), and their body sees nothing from the enclosing lexical scope. This is the form to reach for when handing a callable across a trust boundary.

Named-form functions (`function &foo(...) end`) add a limited surface: the enclosing Module. Their body can reach sibling Module methods via `%module.other` — always explicit through `%module`, never via a `&other` shorthand (there's no implicit walk-up from `&name` to `%module.name`). That surface is deliberately minimal — see [modules § The Module surface is minimal by design](https://puck.uno/requirements/global-methods/module/#the-module-surface-is-minimal-by-design) for what is and isn't exposed. Local variables in the surrounding scope, `%chain` entries, `%self`, and any other frame state remain invisible; only what the source explicitly published as a named definition (`function &name` or `class # name`) is reachable.

The property depends on both halves working together: sealed lexical scope for variables keeps the function from reading arbitrary bindings by name, and `%chain`'s per-frame capability model keeps ambient surfaces from leaking in without explicit grant. Bare functions supply the first half; `%chain` supplies the second. Neither half alone would be enough — a language with sealed lexical scope but ambient globals is still a wide-open attack surface, and a language with capability-based ambient access but lexical capture leaks state through the closure. Caspian's guarantee holds because both mechanisms line up.

See [`%chain`](https://puck.uno/requirements/chain/) for how the capability side works — grant propagation, role boundaries, default-deny vs. default-grant per surface.

## Definition

**Functions are objects.** A function is a first-class value like any other — a class instance that happens to be callable. Two declaration forms produce the same *kind* of value but do fundamentally different things at the source-level:

**Assignment form** — `$var = function(...) ... end`. The `function(...) ... end` construct evaluates to a function object; the assignment stores it at `$var`.

~~~caspian
$greet = function($name)
	puts 'Hello, ' + $name
end
~~~

The empty parameter list and empty body is the minimum legal form (`$greet = function() end`). Assignment-form functions are **maximally hermetic** — no `%module` involvement, no publication of the function as a Module method, and no way for a sibling to reach it by name. It's a plain callable held in a plain variable. Reach for this form when handing a callable across a trust boundary, storing callables in a hash, returning a callable from another function, or any case where you want the function to be strictly a value, not a published name.

**Named form** — `function &name(...) ... end`. The name is baked into the `function` construct itself; the function is created and **two** bindings happen in the declaring scope:

1. `$name` is bound as a variable in the current scope.
2. `name` is published as a method on the current [Module](https://puck.uno/requirements/modules/).

~~~caspian
function &greet()
end

# after this declaration, at the same scope:
$greet                            # the function value (variable in scope)
%module.greet                     # the Module method — same function, invoked via the Module
~~~

The `$name` variable and the `%module.name` method both point at the same function object. They're two access paths, both live at the declaring scope. See [§ Sibling access via `%module`](#sibling-access-via-module) for why they matter differently to code in sibling function bodies.

**The two forms serve different purposes.** Same runtime shape (both are function objects), but the source-level effect differs. Assignment form binds a value to a variable and does nothing to the enclosing Module. Named form binds a variable AND publishes on the Module. Pick assignment form for hermetic callables you don't want on the Module; pick named form for definitions other Module-scope code should be able to reach by name.

**`&name` invokes a callable held in a variable.** Because functions are objects, they carry a `.call` method — and `&name` is sugar for `$name.call`:

~~~caspian
&greet 'alice'
$greet.call 'alice'
~~~

That's the only lookup rule for `&name`. It reads the variable `$name` and calls `.call` on the resulting callable. It does NOT walk up to the enclosing Module.

Both declaration forms bind `$name` as a variable in the declaring scope, so `&name` works at the same scope where you declared the function — either form. The distinction matters **inside another function's body**: sibling bodies are hermetic frames of their own, and don't see `$name` from the enclosing scope. See [§ Sibling access via `%module`](#sibling-access-via-module) for what to use there.

Full call-site syntax (keyword args, splat expansion, method calls) lives on the [call](call) page.

## Sibling access via `%module`

When two functions live in the same [Module](https://puck.uno/requirements/modules/) and need to reach each other, always go through `%module`:

~~~caspian
function &foo()
	return 'foo!'
end

function &bar()
	return %module.foo         # invoke sibling — always explicit through %module
end

function &fact($n)
	if $n <= 1
		return 1
	end

	return $n * %module.fact($n - 1)   # self-recursion works — fact is a Module method too
end
~~~

**No implicit walk-up.** `&foo` inside `bar`'s body does NOT resolve to `%module.foo`. `&name` in Caspian is sugar for `.call` on the variable `$name`, and bar's body — a hermetic frame of its own — has no `$foo` variable (foo's `$foo` binding lives in the enclosing declaring scope, not in bar's body's scope). Caspian does not silently walk up to the Module for the lookup. If you want to invoke a sibling, name the Module explicitly: `%module.foo`.

The `$foo` variable IS visible at the enclosing scope where both foo and bar were declared. So code at that scope (top-level statements, other statements in the same declaring block) can write `&foo` and it works — `$foo` is right there. What doesn't work is `&foo` from inside bar's or gup's or any other function's own body; those are separate hermetic frames.

For a reference (rather than an invocation), reach through `.methods`:

~~~caspian
function &bar()
	$saved = %module.methods['foo']    # method object
	$saved.call                        # invoke later
	return $saved                      # pass out as a value
end
~~~

This is the deliberate way to hold a reference to a Module method — an explicit lookup, no invisible variable binding in bar's namespace.

### Sibling access does not create hidden variables in the body

Under this design, bar's body has NO hidden `$foo` variable just because `foo` is a sibling on the enclosing Module. bar's namespace is exactly what bar declared (its params, its locals) — nothing else. That's the property that keeps function bodies free of surprises: no name appears in a body's namespace unless the body itself declared it or received it as an arg.

`$foo` IS a variable in the ENCLOSING declaring scope (that's where the `function &foo() end` declaration ran), but that scope isn't visible from inside bar's hermetic body. To reach `foo` from bar, use `%module.foo` (invoke) or `%module.methods['foo']` (get the callable as a value) — both explicit.

### Assignment-form functions are not on the Module

`$hidden = function(...) end` binds a local variable. It does NOT publish `hidden` as a method on the enclosing Module. `%module.methods['hidden']` is absent; `%module.hidden` raises. Same for `&hidden` in a sibling body — no Module method to resolve to.

The assignment-form callable can still be invoked at the same lexical scope where the variable was bound (`&hidden` in that scope is sugar for `$hidden.call`, resolving through the local variable). But cross-function access — the specific case sibling-visibility solved for the named form — requires either passing the variable in explicitly, or moving the declaration to the named form.

### Scope is the enclosing Module

"Same Module" means the same lexical Module — top-level declarations are methods on the enclosing `Script` Module; named-form declarations inside another function's body are methods on that Function's Module; and so on. Nested Modules do NOT walk up: a function declared inside another function's body does NOT see the outer function's siblings through `%module`.

~~~caspian
# script.casp — Script Module
function &outer_a()
end

function &outer_b()
	function &inner_a()
	end

	function &inner_b()
		# %module here is outer_b's Function frame (per-invocation of outer_b)
		# %module.inner_a works — inner_a is a Module method on that frame
		# %module.outer_a does NOT work — outer_a is on the Script frame, not this one
	end
end
~~~

`inner_b` can call `%module.inner_a` because they share `outer_b`'s Function frame as their declaration Module. It cannot reach `outer_a` — that's a method on the enclosing `Script` frame, which V1 does not expose from inside `inner_b`'s Module (see [modules § Nesting](https://puck.uno/requirements/modules/#nesting) — no `.parent` accessor in V1).

If a nested function genuinely needs to reach an enclosing-Module name, either:

- **Declare the nested function as a `closure`** — closures capture the full enclosing lexical scope; outer-Module names are reachable through that capture.
- **Have the enclosing scope pass the reference in** — an argument, or a value stashed on `%chain`.

### The three tiers of function-scope reach

Bare functions land in the middle of a three-tier spectrum. Choose the form that matches the reach you want:

| Declaration form | Reaches |
|---|---|
| `$x = function(...) ... end` | Nothing beyond args, locals, and `%chain`. Not published on any Module. Fully hermetic. |
| `function &name(...) ... end` | Args, locals, `%chain`, and the enclosing Module's `.methods` / `.classes` via `%module`. Published as a Module method. |
| `closure(...) ... end` | Args, locals, `%chain`, and the full enclosing lexical scope (variables and Module methods alike). See [closure](closure). |

The hermetic form is the security default: use it whenever you want to guarantee that the function reaches only what it's given. The named form removes the "silly to pass in a function I just defined" friction for related sets of functions by publishing them on the Module. The closure form is the escape hatch when you genuinely need to close over caller state.

**Provisional.** The Module-method design is the current spec, and cleaner than the earlier sibling-&-name-capture approach it replaces (that one leaked hidden `$foo` variables into sibling namespaces). It is not the final word — alternative approaches to function-scope reach are welcome. If you have one, raise it as an issue or a discussion.

## Method surface

A function object exposes a small set of methods directly, plus everything on the [`object` namespace](https://puck.uno/requirements/built-in-classes/object) that every value carries.

**Direct methods on a function:**

| Method | Purpose |
|---|---|
| [`.call(args)`](call) | Invoke the function with the given arguments. `$fn.call args` and `&fn args` produce identical results; the sigil form is sugar for `.call`. |
| `.params` | Hash of parameter metadata objects, keyed by private name (without the `$`). Each entry carries `.lazy`, `.optional`, `.default`, and `.public_name` properties. See [§ Parameters](#parameters) for the full spec of what each entry holds. |

**Cross-cutting `object` methods:**

Everything on the `.object` namespace is available — `$fn.object.freeze`, `$fn.object.isa?(...)`, `$fn.object.classes`, `$fn.object.jail(...)`, and so on. Function objects use the same `object` surface every other value does; they don't add anything special or hide anything from it. See [built-in-classes/object](https://puck.uno/requirements/built-in-classes/object) for the catalog.

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

**Defaults can depend on call-time context.** Because the expression runs at call time, it can name anything reachable at that moment — `%chain`, downloaded core objects, any surface the function has.

~~~caspian
$log = function($stamp: {default: %('core:now').stamp})
	return $stamp
end

&log   # returns the current timestamp — different value on each call
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

Exits with `return $value` (bare keyword) or `%call.return $value`. Both raise the return exception targeted at this function's frame; the engine catches at the function boundary and hands the value back as the call's return value. See [exceptions § ReturnException](https://puck.uno/requirements/exceptions/#returnexception).

## `%call`

Inside a bare function's body, `%call` is a global that returns the **call object** — a first-class object representing the in-progress call. It carries who made the call (`%call.role`), any blocks the caller passed, and the primitives for ending the call early (`%call.return`) or yielding back to a passed block. `%call` is scoped per frame — each function invocation has its own — and it's owned by the caller's role, not the function's.

Full spec, including the block-invocation surface (`%call.blocks[N].call`) and the caller-object mechanism used for DSL-style blocks, is on [`%call`](https://puck.uno/requirements/global-methods/call/) and [caller](tag:caller).

## When a function is bare

A function is a bare function when it's declared with the `function` keyword. That keyword is what makes it bare — no captured outer scope, no receiver — regardless of where the declaration appears. `function` can appear anywhere in a Caspian program: top level, inside another function's body, inside a closure, inside a method. See [closure](closure) and [method](method) for the other two types.

## Testing

- **Assignment form defines a callable** — `$foo = function() end` binds `$foo` to a function object; `$foo.object.isa?(function)` is true.
- **Named form binds the name** — after `function &greet() end`, `$greet` holds the same function object and `&greet` invokes it.
- **Named-form declaration adds a Module method** — `function &foo() return 'x' end; %module.foo` returns `'x'`; `%module.methods['foo']` returns the function object.
- **Named-form ALSO binds a local variable in the declaring scope** — after `function &foo() end`, `$foo` at the same scope is bound to the function value; `&foo` at the same scope invokes it.
- **`$foo` from named-form NOT visible in sibling function bodies** — `function &foo() end; function &bar() return $foo end; %module.bar` raises inside bar's body: the `$foo` variable lives in the enclosing declaring scope, not in bar's hermetic body. Use `%module.foo` from inside bar.
- **Sibling call via `%module`** — `function &foo() return 'x' end; function &bar() return %module.foo end; %module.bar` returns `'x'`.
- **`&name` inside a sibling body does NOT walk up to `%module.name`** — after `function &foo() end; function &bar() &foo end; %module.bar` raises inside bar's body: `&foo` looks for a `$foo` variable, and bar's hermetic body has none (the `$foo` bound by the declaration lives in the enclosing scope, not bar's). Use `%module.foo` for sibling access.
- **Self-recursion via `%module`** — `function &fact($n) if $n <= 1; return 1; end; return $n * %module.fact($n - 1) end; %module.fact(3)` returns `6`.
- **Assignment-form is NOT on the Module** — after `$hidden = function() end`, `%module.methods['hidden']` is absent; `%module.hidden` raises.
- **Assignment-form invocable via `&name` in same scope** — `$foo = function() return 'x' end; &foo` returns `'x'`. `&foo` is sugar for `$foo.call`; the local variable is in scope.
- **Assignment-form not reachable from another function's body** — `$hidden = function() end; function &user() &hidden end; &user` raises: `user`'s body has no `$hidden` variable and the Module has no `hidden` method.
- **Assignment-form body sees no Module methods** — `function &sibling() end; $f = function() &sibling end; &f` raises: assignment-form bodies do not have `%module` access to any surrounding Module.
- **`%module` inside a bare-function body returns that Module** — `function &foo() return %module.type end; %module.foo` returns `"function"`.
- **Nested named-form is scoped to inner Module** — `function &outer_a() end; function &outer_b() function &inner_a() end; function &inner_b() %module.inner_a end; %module.inner_b() end`: `inner_b` can call `%module.inner_a` (both on outer_b's Function frame) but `%module.outer_a` raises inside inner_b (that's on the Script frame, unreachable via `%module` in V1).
- **Empty body is legal** — `function() end` parses and evaluates without raising; calling it returns `null`.
- **Implicit last-value return** — `function() 42 end` invoked returns `42`; no explicit `return` needed.
- **Explicit `return` exits** — `function() return 7; puts 'no' end` returns `7` and does not execute the `puts`.
- **`%call.return` exits from the function** — inside a bare function body, `%call.return 'x'` returns `'x'` as the call's value.
- **`.call` and `&name` are equivalent** — `$greet.call('alice')` and `&greet 'alice'` produce identical return values.
- **Positional args bind left-to-right** — `function($a, $b) return [$a, $b] end` called as `(1, 2)` returns `[1, 2]`.
- **Keyword args bind by public name** — `function($name, $rank) return [$name, $rank] end` called as `(name: 'p', rank: 'c')` returns `['p', 'c']`.
- **Mixed positional/keyword** — `&foo 'p', rank: 'c'` binds `$name = 'p'` and `$rank = 'c'`.
- **Named arg after positional is legal** — positional args allowed before the first named arg; parses without raise.
- **Missing required positional raises** — `function($a, $b) end` called as `()` raises at call time.
- **Missing required keyword raises** — `function($a, $b) end` called as `(a: 1)` raises.
- **Extra positional with no `*args` raises** — `function($a) end` called as `(1, 2)` raises.
- **Extra keyword with no `**opts` raises** — `function($a) end` called as `(a: 1, extra: 2)` raises.
- **Optional parameter defaults to null** — `function($a: {optional: true}) return $a end` called as `()` returns `null`.
- **`default:` implicitly marks optional** — `function($a: {default: 'x'}) return $a end` called as `()` returns `'x'`.
- **Default expression re-evaluates each call** — `function($a: {default: []}) $a.push('y'); return $a end` called twice returns `['y']` each time (fresh array).
- **Default can reference a downloaded core object** — `function($t: {default: %('core:now').stamp}) return $t end` returns the current timestamp on each call.
- **Optionality propagates rightward** — `function($a, $b: {optional: true}, $c) end` allows omission of `$c` even without explicit optional on `$c`.
- **`*args` captures remaining positionals** — `function($x, *$rest) return $rest end` called as `(1, 2, 3, 4)` returns `[2, 3, 4]`.
- **`*args` empty when no extras** — `function($x, *$rest) return $rest end` called as `(1)` returns `[]`.
- **`**opts` captures remaining keywords** — `function($x, **$opts) return $opts end` called as `(1, a: 2, b: 3)` returns `{a: 2, b: 3}`.
- **`**opts` empty when no extras** — `function($x, **$opts) return $opts end` called as `(1)` returns `{}`.
- **Combined rest** — `function($x, *$rest, **$opts) end` binds positionals to `$rest` and keywords to `$opts` independently.
- **`public_name` override changes call-site key** — parameter `$title_sent` with `public_name: 'title'` accepts `title:` at the call site; `title_sent:` raises.
- **Private name unusable at call site by default** — `function($name) end` called with `name:` works; other names raise.
- **Duplicate public names raise at definition** — two params resolving to the same public name error when the function is defined, not called.
- **Public/private collision raises at definition** — `public_name` matching another param's private name is a definition-time error.
- **Multiple `*args` raise at definition** — two `*args` parameters error at definition.
- **Multiple `**opts` raise at definition** — two `**opts` parameters error at definition.
- **Lazy parameter delays evaluation** — `function($x: {lazy: true}) return $x.call end` receives a callable; `.call` produces the value.
- **Lazy short-circuits** — a lazy `$right` whose expression would raise is never evaluated when `.call` isn't invoked.
- **`%self` raises inside a bare function** — referencing `%self` from inside `function() %self end` raises.
- **Outer locals not reachable inside body** — `$outer = 1; $f = function() return $outer end; &f` raises: `$outer` is a variable in the surrounding scope, and bare functions capture neither variables (either declaration form) nor arbitrary bindings.
- **`%chain` is reachable inside body** — inside a bare function, `%chain` returns the caller's chain frame.
- **Programmatic metadata edit takes effect** — after `$foo.params['bar'].optional = true`, calling `&foo` without `bar` no longer raises.
- **`.params` is a hash keyed by private name** — `function($bar) end` produces `.params['bar']` (no `$`).
- **`.default` returns a thunk** — reading `.default` on a param object returns a callable; `.default.call` returns the value.
- **Sealed scope: cross-role handoff cannot read caller's locals** — a bare function passed to another role sees no locals from the defining role.