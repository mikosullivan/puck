# Functions
<!--index: 12-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions",
	"role": "stub — spec for Caspian's function surface. 'Function' is the umbrella term; every callable is a function. There are three types, each declared by its own keyword: `function` (bare — no captured scope, no receiver), `closure` (captures the outer lexical scope), and `method` (bound to a receiver with %self and bucket access, no captured scope). Bare functions and closures can be declared anywhere; methods must be declared inside a class definition or applied on an object. The syntactic form is otherwise uniform. Sub-pages cover each type and call syntax.",
	"status": "stub — three-type framing settled; deeper specifics of each type to be filled in",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

**Every callable in Caspian is a function.** "Function" is the umbrella term. Within that category, three types differ in what the body has access to, and each has its own declaration keyword:

- **[Bare function](bare)** — declared with `function`. No captured outer scope, no receiver.
- **[Closure](closure)** — declared with `closure`. Captures the outer lexical scope.
- **[Method](method)** — declared with `method`. Bound to a receiver with `%self` and `%bucket`.

**The keyword picks the type; the location determines what's legal.** `function` and `closure` can be declared anywhere. `method` must appear inside a class definition or be applied on an object (see [downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods)). The three types are non-overlapping — a function is bare, or a closure, or a method — not two at once.

**The definition form is spec'd on the [bare function](bare) page.** That page carries the full syntax: parameter list, body, return, everything. The [closure](closure) and [method](method) pages then describe how each type differs from the bare form — the differences are minor, and both pages assume the bare-function page as the baseline.

Call-site syntax (which is uniform across all three types) lives at [call](call).

Parameter defaults — including the fresh-object-per-call semantics and the `function` vs. `closure` scope rules — are spec'd at [parameter-defaults](tag:parameter-defaults).
