# Modules

~~~vibecode
{"vibecode": {
	"doc": "requirements_modules",
	"role": "spec for the Module concept — the execution frame every scope where Caspian code runs. Modules are the canvas, not the objects created BY code. When a function is invoked, a fresh Module frame is created for its body to run in; when a class is defined, a fresh Module frame runs the definition pass. The function object / class object that results is a plain value that LIVES ON its enclosing Module — it is not itself a Module. Module frames are per-invocation: each function call creates a new one, so nested named definitions (function &inner inside function &outer) are re-created each outer call — same behavior as JavaScript / Python inner-function declarations. Named-form function declarations (`function &name(...) end`) publish the function as a method on the enclosing Module rather than as a variable binding — that's what removes the earlier design's `$foo` variable-leak. Modules expose ONLY their named definitions (`.methods` and `.classes`) — NO local variables, NO caller state, NO enclosing scope; the non-exposure is deliberate and load-bearing for Caspian's security posture. No `.parent` accessor in V1. Definitions are lexically scoped to the Module frame that contains them — no leak into enclosing Modules, matching Perl's block-scoped `sub` (contrast with Ruby / Python where a conditional definition leaks out).",
	"status": "spec — the Module-as-frame concept, per-invocation semantics, definition-as-method rule, and no-parent / no-variables surface are settled for V1; the exact type names for each subclass and the enumeration surface are still in draft",
	"audience": "developers writing Caspian; parser implementers realizing the Module semantics"
}}
~~~

A **Module** is the execution canvas — the frame every scope where Caspian code runs. When a function body executes, its code runs on a Module. When a class body executes (during the definition pass), that runs on a Module too. When top-level script code runs, that's on a Module. Modules are the *runtime scope*, not the objects that code produces.

## Modules are frames, not objects

The important distinction: a Module is where code **runs**, not the object the code **creates**.

- The scope where `class # widget ... end` executes is a Module (a class-body frame). But the widget **class object** that pops out of that execution is not a Module — it's a class value that carries the fields, methods, and inheritance the definition pass populated.
- The scope where `function &foo() ... end`'s body runs during each invocation is a Module (a function-body frame). But the foo **function object** — the callable value that lives on its enclosing Module as `%module.foo` — is not a Module. It's a function value.

Every scope has an implicit Module:

~~~caspian
# myscript.casp
    module # implicit — Script frame for the file's top-level code
        function &foo()
            module # implicit — Function frame; runs when foo is invoked
                puts 'whatever'
            end
        end
    end
end
~~~

The nested `module # implicit` is *not* real syntax — Modules are never declared explicitly. The tree just illustrates the structure. Every scope where code runs has one, invisibly.

## What kinds of frames are Modules

Each construct that runs code has its own Module subclass. The subclass tags what kind of frame it is; the surface stays uniform.

- **`Script`** — the frame for a `.casp` source file's top-level code. Created when the file loads, persists as long as the file's definitions are alive.
- **`Function`** — the frame for a bare function's body. Created fresh **on each invocation** of the function.
- **`Closure`** — the frame for a closure's body. Created fresh on each invocation. Also the frame for an `if` / `unless` branch body, for a `while` / `until` / `.each` / `.times` loop body (loop bodies are attached `do` closures), and for every attached `~name` hook block ([clause-slots](https://www.puck.uno/requirements/syntax/clause-slots), [functions/closure](https://www.puck.uno/requirements/functions/closure)).
- **`Method`** — the frame for a method body. Created fresh on each invocation.
- **`Begin`** — the frame for a bare block. Created fresh each time the block runs.
- **`ClassBody`** — the frame for a class body during the definition pass. Runs once, when the `class ... end` construct executes; populates the resulting class object with the definition's fields / methods / inheritance and then discards.

There is no `Class` Module type — the class **object** produced by a `ClassBody` frame is a class value, not a Module. Same for the `Function` / `Closure` / `Method` distinction: the *frame* is a Module, the *callable object* is not.

## Per-invocation semantics

Function-body Modules are **per-invocation**: each call to a function creates a fresh Module frame for its body. This matters when a function contains nested named definitions:

~~~caspian
function &outer()
	function &inner()
		return 'inside'
	end

	return %module.methods['inner']
end
~~~

Each call to `outer` (via `%module.outer` at Script scope) produces a **fresh** `inner` function object — not the same one across calls. Same behavior as JavaScript, Python, and most other languages that let you `def` inside `def`; two invocations produce two distinct closures.

For the common case (function bodies with no nested named definitions), per-invocation vs. per-declaration is invisible; the Module frame's `methods` and `classes` hashes are empty. The distinction only matters when nested named definitions are involved.

## Definitions live in their lexical Module

A named definition — `function &name(...) end`, `class # name ... end`, `method &name(...) end` inside a class body — is added to the **Module that lexically contains it**. It doesn't leak out into any enclosing Module.

That means a conditional definition is scoped to the branch closure it was declared in:

~~~caspian
if $check
	function &foo()
	end
end

%module.foo   # RAISES — foo was defined in the if branch's Closure Module, not on the enclosing Script Module
~~~

To make `foo` visible in the enclosing Module, either declare it at the enclosing scope or use the branch to compute a value that the enclosing scope receives.

This is the sensible precedent — Perl's `sub` inside a block is scoped to that block. Ruby and Python leak `def foo` from inside an `if` out to the enclosing scope, which produces conditional-existence bugs; Caspian doesn't.

## The `%module` global

Inside any Caspian code, `%module` returns the **Module frame the code was lexically declared in**. For code at the top level of a script, that's the `Script` frame (persistent — one instance per file load). For code inside a function body, that's the per-invocation frame the enclosing function created when it was called.

`%module` has full spec at [`%module`](https://puck.uno/requirements/global-methods/module/).

Named definitions the source made — `function &name(...) end` and `class # name ... end` — publish onto whichever frame lexically contains them. Sibling code reaches those definitions through `%module`:

~~~caspian
function &foo()
end

function &bar()
	%module.foo
end
~~~

`function &foo()` at script top level publishes `foo` as a method on the `Script` frame. Inside `bar`'s body, `%module` returns that same `Script` frame — that's the frame `bar` was declared in. Standard method dispatch finds `.foo` and calls it.

For **nested** named declarations, per-invocation semantics kick in. Given:

~~~caspian
function &outer()
	function &inner()
		return 'inside'
	end

	return %module.methods['inner']
end
~~~

Each call to `outer` creates a fresh `Function` frame for its body. `inner` is declared **inside** that frame, so `inner` is a fresh function object per outer-invocation. Two calls to outer produce two distinct inner functions. Inside `inner`'s body, `%module` is that specific per-invocation frame (the one the current inner was declared in) — not the enclosing Script.

## The three-tier capture model, restated

The Module concept replaces the earlier "sibling &-name capture" mechanism cleanly. Bare functions still come in two declaration forms with different visibility posture:

| Declaration form | What happens | Body's reach |
|---|---|---|
| `$x = function(...) ... end` | Function object bound to local variable `$x`. Not on the Module. | Args, locals, and `%chain` only. Fully hermetic. |
| `function &name(...) ... end` | BOTH: binds `$name` as a variable in the declaring scope AND adds `name` as a method on the enclosing Module. | Args, locals, `%chain`, and the enclosing Module's methods / classes via `%module` (the body's own frame; not the declaring scope's variables). |
| `closure(...) ... end` | Function object that captures the enclosing lexical scope. | Full lexical scope — variables and Module methods. |

Access via `%module` isn't itself a capture — it's an explicit lookup through the running frame's `%module` global. That means:

- Function bodies don't have hidden variables from the enclosing scope. `function &foo() end` at Script scope binds `$foo` in the Script scope — but Script's variables are NOT visible from inside a sibling `function &bar() end`'s hermetic body. The previous version's "$foo leak into bar's body" is gone.
- If you want a callable reference to a Module method rather than an invocation, ask for it explicitly: `%module.methods['foo']` returns the method object.
- To invoke a Module method from inside a sibling body, always use `%module.name` explicitly. `&name` in Caspian is sugar for `.call` on the variable `$name`; the body has no such variable (it lives in the enclosing scope, not the body), so `&name` inside a sibling body raises. There is no implicit walk-up from `&name` to `%module.name`.
- At the declaring scope itself (top-level statements, other statements in the same declaring block), `&name` DOES work — the `$name` variable is right there in that scope.

## Nesting

Modules nest lexically. A `Script` at top level contains `Function` Modules; a `Function` body contains a `Begin` Module; a `Begin` contains further Modules; and so on. Each Module's `%module` returns just its **own** instance — the innermost lexical Module for the code that reads it.

**No walk-up in V1.** V1 Modules do NOT expose a `.parent` accessor. Enclosing Modules are not reachable through the Module surface. If nested code needs to invoke a name from an enclosing Module, either:

- Reach it by variable capture (`closure(...)` captures its full enclosing scope, including outer-Module names bound to variables).
- Have the enclosing scope pass the reference in explicitly.

Adding a `.parent` accessor is left open for the community to argue for if a compelling use case shows up. The initial design leaves it off deliberately: the fewer surfaces a Module exposes, the smaller the accidental-leak surface.

## Exposure — Modules expose ONLY their named definitions

A Module's surface is **strictly limited to what the source explicitly defined by name** — the `function &name(...) end` and `class # name ... end` declarations. It does NOT expose:

- **Local variables.** `$x = 5` inside a Module is invisible to that Module's `%module.methods` or any other surface.
- **Assignment-form callables.** `$foo = function() end` binds a local variable; it does not add a method to the Module.
- **`%chain` entries.** The ambient capability channel is not part of the Module's surface.
- **`%self`, `%bucket`, or any other frame-scoped globals.** Those live on their own accessors, not on the Module.
- **Enclosing state.** A Module knows nothing about the code that defined it, the caller that invoked it, or any Module that contains it.

That exclusion is deliberate and load-bearing for Caspian's security posture. `%module` is a lookup surface for the definitions the source made public by using the named form; it is not an introspection channel into everything the Module's body has access to.

## Enumeration

A Module exposes what it contains through two named collections:

| Accessor | Contents |
|---|---|
| `.methods` | Hash of the Module's named functions / methods, keyed by name. Each value is the callable itself. |
| `.classes` | Hash of the Module's class definitions, keyed by name. |
| `.type` | Short string naming the specific frame kind — `"script"`, `"function"`, `"closure"`, `"method"`, `"begin"`, `"class_body"`. |

`.methods['foo']` returns the method object; `%module.foo` invokes it via ordinary dispatch. Both work; use whichever reads better.

Nothing else is on the base surface in V1. If a future use case genuinely needs source-line ranges, contained-Modules enumeration, or similar introspection, that's a spec addition to argue for at that time — the base stays minimal by default.

## Garbage collection

Modules are **ordinary objects** for GC purposes. Reachability-based collection handles them naturally: as long as any code (a returned function value, a variable holding a callable, a hash entry) references a Module — directly or through a nested function that carries it as its declaring Module — the Module stays alive. When nothing references it any longer, it becomes unreachable and gets collected.

The trap to avoid: **do NOT treat Modules as special objects with their own lifecycle rules.** Any "Module frames are freed at end of the invocation that created them" logic creates problems the moment a returned inner function needs its declaring outer-frame to survive:

~~~caspian
function &foo()
	function &bar()
	end

	function &gup()
		%module.bar()
	end

	return $gup
end

$gup = &foo()
$gup       # foo's per-invocation frame is still alive here — held by $gup's declaring-Module reference
~~~

Once `&foo()` returns, `$gup` holds a reference to the function object; the function object carries a reference to its declaring Module frame (foo's per-invocation frame); the frame holds `bar` and `gup` as its methods. Everything stays alive as long as `$gup` does. Normal reachability. Nothing special.

## Subclass specifics

The base `Module` surface is uniform, but each frame kind extends it:

- **`Script`** — has a `.path` giving the source-file path.
- **`Function`** / **`Closure`** / **`Method`** — the frame for the corresponding callable's body. The callable **object** (foo the function, m the method) is NOT the Module — it's a value published on the enclosing Module. The frame is what `%module` returns while the body is executing.
- **`Begin`** — frame for a bare block. Carries the `as $name` controller slot if the block declared one.
- **`ClassBody`** — frame for a class body during its one-shot definition pass. Populates the resulting class object with fields / methods / inheritance and then discards. The **class object** is not itself a Module; it is a class value that lives on its enclosing Module (as `%module.classes['name']`).

Each subclass's page is (or will be) the authoritative spec for its specifics. This page just defines the shared base.

## Testing

- **Named function becomes a Module method** — `function &foo() return 'x' end; %module.foo` returns `'x'`.
- **Assignment-form function does NOT become a Module method** — `$foo = function() end; %module.methods['foo']` is absent.
- **Method reference via `.methods[name]`** — `function &foo() end; %module.methods['foo'].call()` invokes foo.
- **Sibling call via `%module.name`** — `function &foo() return 'x' end; function &bar() return %module.foo end; %module.bar` returns `'x'`.
- **`&name` does NOT resolve to Module methods** — after `function &foo() end`, `&foo` (at any scope) raises: `&name` requires a `$name` variable, and named-form declarations don't bind one. Sibling access always uses `%module.name`.
- **Local variables are not exposed** — `$x = 5; %module.methods['x']` is absent; the Module surface holds no reference to local variables.
- **`%chain` entries are not exposed** — `%module` has no accessor listing chain entries; those live on `%chain`, not the Module.
- **Definition inside `if` branch is scoped to that branch** — `if $t; function &foo() end; end; %module.foo` raises: foo was defined in the branch closure's Module, not the enclosing Script.
- **Loop and if branches are Modules** — inside `while $t; %module.type; end`, `%module.type` returns `"closure"` (branch/loop bodies are closures).
- **Class body is a Module during the definition pass** — inside `class ... end`, `%module.type` returns `"class_body"`.
- **Class object is NOT a Module** — after `class # widget ... end` finishes, the resulting widget class value does not satisfy `.obj.isa?(%('caspian.uno/module'))`; it's a class value, not a Module.
- **Fresh Module per function invocation** — `function &outer() function &inner() end; return %module.methods['inner'] end; &outer().obj.id != &outer().obj.id`: two calls to outer produce two distinct inner function objects.
- **No `.parent` accessor in V1** — Modules do not expose an enclosing-Module reference; nested code that needs to reach an outer Module's method receives the reference explicitly (or captures via `closure`).

## Related

- [functions/bare](https://puck.uno/requirements/functions/bare) — the two declaration forms of a bare function; how `function &name` interacts with the Module.
- [global-methods/module](https://puck.uno/requirements/global-methods/module/) — the `%module` global and its full surface.
- [classes](https://puck.uno/requirements/classes/) — the class construct, which was already Module-shaped before the base class was named.
- [syntax/clause-slots](https://www.puck.uno/requirements/syntax/clause-slots) — attached `do` / `~name` blocks are closures, and therefore Modules.
