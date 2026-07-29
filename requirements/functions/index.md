# Functions
<!--index: 12-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions",
	"role": "stub — spec for Caspian's function surface. 'Function' is the umbrella term; every callable is a function. Three types, each declared by its own keyword: `function` (bare — no captured variables, no receiver), `closure` (captures the outer lexical scope), and `method` (bound to a receiver with %self and bucket access, no captured scope). Bare functions and closures can be declared anywhere; methods must be declared inside a class definition or applied on an object. The `function` type further splits by declaration form: `function &name(...) end` publishes the function as a method on the enclosing Module — siblings reach it via `%module.name` (always explicit; no `&name` shorthand for Module methods); `$var = function(...) end` binds a local variable and does NOT touch the Module (fully hermetic — the security escape hatch). See functions/bare.md § Sibling access via %module and the modules spec.",
	"status": "stub — three-type framing settled, and the Module-method model on bare functions is settled; deeper specifics of each type to be filled in",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

**Every callable in Caspian is a function.** "Function" is the umbrella term. Within that category, three types differ in what the body has access to, and each has its own declaration keyword:

- **[Bare function](bare)** — declared with `function`. No captured outer variables, no receiver. Two declaration forms with different source-level effect: `function &name(...) end` publishes the function as a method on the enclosing [Module](https://puck.uno/requirements/modules/) (ergonomic for mutually-referencing modules); `$var = function(...) end` binds a local variable and is fully hermetic (the security default).
- **[Closure](closure)** — declared with `closure`. Captures the outer lexical scope.
- **[Method](method)** — declared with `method`. Bound to a receiver with `%self` and `%bucket`.

**The keyword picks the type; the location determines what's legal.** `function` and `closure` can be declared anywhere. `method` must appear inside a class definition or be applied on an object (see [downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods)). The three types are non-overlapping — a function is bare, or a closure, or a method — not two at once.

**The reach spectrum.** Across the three types (and the two declaration forms of `function`), the amount of enclosing state a function can see grows in a graded, opt-in way:

| Form | Reaches |
|---|---|
| `$x = function(...) end` | Nothing beyond args, locals, and `%chain` — fully hermetic. Not published on any Module. |
| `function &name(...) end` | Args, locals, `%chain`, and the enclosing Module's methods / classes via `%module`. Published as a Module method. |
| `closure(...) end` | Args, locals, `%chain`, and the full enclosing lexical scope (variables and Module methods alike). |
| `method &name(...) end` inside a class | `%self`, `%bucket`, sibling methods on the class (reached via `%self.class` — the class object holds the methods; the class body's Module frame was ephemeral). See [method](method). |

Every step is an explicit choice by the author; there is no "default lexical capture" behavior. See [bare § Sibling access via %module](bare#sibling-access-via-module) and [modules](https://puck.uno/requirements/modules/) for the Module mechanism the named form plugs into.

**The definition form is spec'd on the [bare function](bare) page.** That page carries the full syntax: parameter list, body, return, everything. The [closure](closure) and [method](method) pages then describe how each type differs from the bare form — the differences are minor, and both pages assume the bare-function page as the baseline.

Call-site syntax (which is uniform across all three types) lives at [call](call).

Parameter defaults — including the fresh-object-per-call semantics and the `function` vs. `closure` scope rules — are spec'd at [parameter-defaults](tag:parameter-defaults).
