# `%module`
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_module",
	"role": "spec for %module — the global that returns the Module frame the current code was lexically declared in. Modules are execution frames, not the objects code produces: a class body runs on a ClassBody frame but the resulting class object isn't a Module; a function body runs on a per-invocation frame but the function object isn't a Module. For code declared at Script scope, %module returns the persistent Script frame. For code declared inside a function body, %module returns the per-invocation frame the enclosing function created — so nested named definitions (function &inner inside function &outer) are fresh per outer-invocation. The frame surface exposes ONLY the named definitions the source published — .methods (from function &name) and .classes (from class # name) — NOT local variables, NOT %chain entries, NOT any other frame state. No .parent accessor in V1. See modules for the frame concept and its subclass tree.",
	"settled": "the accessor returns the innermost declaration-scope Module frame; per-invocation semantics for function body-frames means nested named defs are fresh per call; the returned object exposes .methods, .classes, and .type — and nothing else on the base surface; %module.methods['name'] returns the method object for reference-holding; the &name shorthand for %module.name inside a sibling body remains as ergonomic sugar; %module is determined by lexical declaration site, not by runtime call chain — a passed-out function's %module is still the frame it was declared in",
	"audience": "developers writing Caspian; anyone reading code that uses the Module concept to reach siblings"
}}
~~~

`%module` is a global available at any point in a Caspian program. It returns the **Module frame** the current code was lexically declared in. For code at the top level of a script, that's the persistent `Script` frame. For code inside a function body, that's the per-invocation frame the enclosing function created when it was called.

`%module` is its own global — not a `%chain` entry, not tied to `%call`. It's determined by where the code was written, not by how it was invoked.

## Modules are frames, not the objects code produces

The important distinction: `%module` returns the execution **frame** the code runs on, not any object the code has produced. When a class body executes, the frame is a `ClassBody` Module; the class object produced by the definition pass is NOT a Module (it's just a class value). When a function body executes, the frame is a `Function` Module; the function object bound to the enclosing scope is NOT a Module (it's just a function value).

Full spec of the Module concept, subclass tree, and per-invocation semantics: [modules](https://puck.uno/requirements/modules/).

## Frame identity

`%module` returns a Module frame — an instance of some subclass of `Module`. The specific subclass depends on the code's enclosing container: `Script` at file top level, `Function` inside a bare function body, `Closure` inside a closure (including if/unless branch closures and loop bodies), `Method` inside a method body, `Begin` inside a `begin ... end`, `ClassBody` inside a class body.

`%module.obj.isa?(%('caspian.uno/module'))` is `true` for every case. The specific subclass can be checked via `%module.type` (see [Direct methods](#direct-methods) below) or via `%module.obj.isa?(%('caspian.uno/module/function'))` and similar.

## Reaching siblings

The primary use — replaces the earlier "sibling &-name capture" mechanism and its `$foo` variable leak:

~~~caspian
function &foo()
	return 'foo!'
end

function &bar()
	return %module.foo         # invoke sibling — always explicit through %module
end
~~~

**No implicit walk-up.** `&foo` inside `bar`'s body does NOT resolve to `%module.foo`. `&name` in Caspian is sugar for `.call` on the variable `$name`, and bar's hermetic body has no `$foo` variable (the `$foo` bound by the `function &foo()` declaration lives in the enclosing declaring scope, not in bar's body). Sibling access from inside a body goes through `%module` every time — the explicit path is the only path.

At the enclosing declaring scope itself, `&foo` works normally — `$foo` is a variable right there.

If you need the method as a value (to pass, store, invoke later), reach through `.methods`:

~~~caspian
$saved = %module.methods['foo']    # method object, callable later
$saved.call
~~~

This is the deliberate way to hold a reference to a Module method — an explicit lookup, not an implicit variable binding.

## No walk-up in V1

V1 Modules do NOT expose a `.parent` accessor. Nested code cannot reach an enclosing Module through the `%module` surface — the containment chain is not traversable.

If a nested body needs a name defined in an outer Module, either:

- **Use `closure(...)`** — a closure captures the full enclosing lexical scope, including outer-Module names bound to variables.
- **Have the enclosing scope pass the reference in.** Explicit arg-passing (or `%chain`, when appropriate) rather than reaching outward.

Adding a `.parent` accessor later is open for the community to argue for if a compelling use case emerges. The initial design leaves it off deliberately: fewer surfaces means fewer accidental-leak vectors.

## The Module surface is minimal by design

`%module` returns an object with a **strictly limited surface** — only the named definitions the source made public through `function &name(...) end` and `class # name ... end`. Not exposed:

- **Local variables.** `$x = 5; %module.methods['x']` is absent.
- **Assignment-form callables.** `$foo = function() end` binds a variable; it does not touch the Module.
- **`%chain` entries.** The ambient capability channel is not part of the Module's surface.
- **`%self`, `%bucket`, or any other frame-scoped globals.** Those live on their own accessors.
- **Enclosing state.** No `.parent`, no caller reference, no reach beyond the immediate lexical Module.

That exclusion is deliberate and load-bearing for Caspian's security posture. `%module` is a lookup surface for what the source explicitly published; it is not an introspection channel into everything the body could see.

## Direct methods

The base `Module` surface — same shape for every subclass:

| Method | Purpose |
|---|---|
| `.methods` | Hash of named functions / methods this Module contains, keyed by name. Each value is the callable. |
| `.classes` | Hash of class definitions this Module contains, keyed by name. |
| `.type` | Short string naming the specific frame kind — `"script"`, `"function"`, `"closure"`, `"method"`, `"begin"`, `"class_body"`. |
| `.<method_name>` | Dispatch to a contained method. `%module.foo` is equivalent to `%module.methods['foo'].call` when `foo` is a Module method. |

Nothing else on the base surface in V1. Subclass-specific accessors extend it:

- **`Script`** — `.path` gives the source-file path.
- **`Function`** / **`Closure`** / **`Method`** — the execution frame for the corresponding callable's body. The frame is created per-invocation (fresh each call); nested named definitions inside the body land on this frame. The **callable object** itself (the function bound to a variable or published on the enclosing Module) is NOT a Module — it's a separate value.
- **`Begin`** — frame for a bare block. `.as` gives the `as $name` controller-binding name if the block declared one.
- **`ClassBody`** — frame for a class body during the one-shot definition pass. Populates the resulting class **object** (which is not a Module) with the fields, methods, and inheritance the definition declared. See [classes](https://puck.uno/requirements/classes/) for the class-value surface.

## Determined by where the code was written, not by how it was invoked

`%module` is a lexical accessor: it depends on the source location, not on the runtime call chain. A function passed out of its declaring scope and invoked from somewhere else still sees its OWN declaring Module through `%module`:

~~~caspian
function &foo()
	return %module     # returns the Script frame foo was declared in
end

$stashed = &foo
$something_else.pass_it_along($stashed)   # someone else invokes it far away
# invoked wherever — %module inside foo's body is still foo's declaration Script
~~~

That's the mechanism that makes "Module methods reach siblings even after being passed out" work: `bar` calls `%module.foo`, `%module` is bar's declaring Module (which contains foo), and dispatch finds foo — regardless of where bar was invoked from. Compare to [see it, call it](tag:see-it-call-it): the callable carries its declaring Module as part of its identity, same way a method carries its `%self`.

## Per-invocation semantics for function-body frames

For code declared at the **top level of a script**, `%module` returns the persistent `Script` frame — one instance per file load, stable across every invocation of any top-level function.

For code declared **inside a function body**, `%module` returns the per-invocation frame the enclosing function created when it was called — so each outer-invocation produces a **fresh** frame, and any nested named definitions declared in that body-frame are fresh per outer-call. Example:

~~~caspian
function &outer()
	function &inner()
		return %module     # per-invocation frame — different each outer-call
	end

	return %module.methods['inner']
end

$a = &outer()   # inner declared in one outer-frame
$b = &outer()   # inner declared in a different outer-frame
$a.call() == $b.call()   # false — different frame instances
~~~

For the common case (function bodies with no nested named definitions), the per-invocation-vs-persistent distinction is invisible — the body-frame's `.methods` and `.classes` are empty, and code inside just reads `%module` to reach whatever's on the enclosing declaration frame.

## Testing

- **`%module` at script top level returns the Script Module** — `%module.type` is `"script"`.
- **`%module` inside a bare function returns that function's Module** — `function &foo() return %module.type end; %module.foo` returns `"function"`.
- **`%module.foo` invokes a sibling** — `function &foo() return 'x' end; function &bar() return %module.foo end; %module.bar` returns `'x'`.
- **`&foo` does NOT resolve to `%module.foo`** — inside a sibling body, `&foo` raises: `&name` looks up the variable `$name`, and named-form declarations do not bind it. Use `%module.foo` for sibling access.
- **`%module.methods['foo']` returns the method object** — `.methods['foo'].call` invokes it; the value can be passed around and invoked later.
- **Assignment-form function is NOT on `%module.methods`** — after `$foo = function() end`, `%module.methods['foo']` is absent.
- **Local variables are not exposed** — `$x = 5; %module.methods['x']` is absent; `%module` has no accessor listing variables at all.
- **`%chain` entries are not exposed** — nothing on the Module surface enumerates chain entries.
- **No `.parent` accessor in V1** — reading `%module.parent` raises (no such method).
- **Passed-out function's `%module` is its declaration Module** — `function &foo() return %module end` returns the Script Module even when foo is stashed in a hash and invoked from a completely different frame.
- **`%module` inside an `if` branch is the branch's Closure Module** — `if $t; return %module.type; end` returns `"closure"`.
- **Definition inside `if` branch is scoped to that branch** — `if $t; function &foo() end; end` puts foo on the branch Closure Module, not the enclosing Script; `%module.methods['foo']` at Script level is absent (see [modules § Definitions live in their lexical Module](https://puck.uno/requirements/modules/#definitions-live-in-their-lexical-module)).
- **Class body is a Module during the definition pass** — inside `class ... end`, `%module.type` returns `"class_body"`.
- **Class object is NOT a Module** — `class # widget end` produces a widget class value; `widget.obj.isa?(%('caspian.uno/module'))` is `false`.
- **Nested named definition is fresh per outer-invocation** — `function &outer() function &inner() end; return %module.methods['inner'] end; %module.outer().obj.id != %module.outer().obj.id`: two calls to outer produce two distinct inner function objects.
- **Top-level function's `%module` is the persistent Script frame** — `function &foo() return %module.obj.id end; %module.foo == %module.foo`: two calls return the same frame id.
- **Nested function's `%module` is a per-invocation frame** — `function &outer() function &inner() return %module.obj.id end; return %module.methods['inner'] end; %module.outer().call != %module.outer().call`: two outer-invocations produce two frames.
