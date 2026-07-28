# Closure
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions_closure",
	"role": "spec for the closure type — a function that captures its outer lexical scope at the point of definition. Introduces no `%self` of its own, but sees the enclosing scope's `%self` (and `%bucket`) through the same capture mechanism as any other binding — so a closure defined inside a method's body has access to the method's receiver, while a closure defined outside any method does not. `%chain` is available same as in bare functions and methods. Used for callbacks, deferred work, and any pattern where a chunk of code needs to remember the environment it was born in. Content TBD beyond the shape captured here.",
	"status": "draft — surface described; deeper semantics of scope capture, mutation, and lifetime to be filled in",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

A **closure** is a function that captures its outer lexical scope. Everything the enclosing scope had bound at the point of definition is reachable from the closure's body.

Inside the body:

- **No own `%self`.** A closure isn't bound to a receiver of its own. It does not introduce a new `%self`; whether `%self` is available inside the closure body depends on the enclosing scope. When a closure is defined inside a method's body, the method's `%self` and `%bucket` are captured through the same outer-scope mechanism as any other binding — inside the closure, `%self` is the enclosing method's receiver and `%bucket` is that receiver's bucket. When the closure is defined outside any method (top level, inside a bare function, or inside another closure that has no captured `%self`), `%self` and `%bucket` are not in scope and referring to them raises.
- **Outer-scope capture.** Names defined in the enclosing scope are reachable from the closure body — the closure carries a reference to that scope so the bindings survive as long as the closure does.
- **[`%chain`](https://puck.uno/documentation/requirements/chain/)** — the ambient capability channel, same as in bare functions and methods. Per-frame and always reachable; carries `%now`, `%stdout`, `%net`, and every other granted global.
- **What's reachable.** Arguments passed in, names defined locally in the body, names inherited from the captured outer scope (including `%self` and `%bucket` when the enclosing scope has them), and `%chain`. The lexical capture is by reference: if the outer scope mutates a binding after the closure is defined, the closure sees the mutation.

## return and %call.return

Closures use `%call.return $value` to exit. The bare `return` keyword returns from the enclosing function or method, not from the closure itself — matching the general rule that `return` targets a function or method boundary while `%call.return` targets whichever frame is currently `%call`. See [exceptions § ReturnException](https://puck.uno/documentation/requirements/exceptions/#returnexception).

## Common use cases

- **Callbacks.** A closure passed to a method or function that runs it later — the closure keeps access to whatever the caller had in scope at the moment of registration.
- **Deferred work.** Building up code that runs "later," when the enclosing state has already moved on.
- **Higher-order patterns.** Any place where a function needs to remember more than its arguments.

## When a function is a closure

A function is a closure when it's declared with the `closure` keyword. That keyword is what triggers outer-scope capture — a bare `function` in the same location would not capture arbitrary variables, and a `method` in the same location would bind to a receiver instead. `closure` can appear anywhere `function` can: top level, inside another function or closure body, inside a method. See [bare function](bare) and [method](method) for the other two types.

## Relationship to the reach spectrum

Closures sit at the widest end of the reach spectrum. Bare functions reach only args, locals, and `%chain` (assignment form) or additionally the enclosing Module's methods via `%module` (named form). Closures capture the full enclosing lexical scope — every variable binding, `%self` and `%bucket` inherited from an enclosing method, and — as a superset — the surrounding scope's Module methods are reachable through the closure's captured `%module`. See [bare § The three tiers of function-scope reach](bare#the-three-tiers-of-function-scope-reach) and [modules](https://puck.uno/documentation/requirements/modules/) for the graded model.

## Testing

- **Captures outer local** — `$outer = 1; $c = closure() return $outer end; &c` returns `1`.
- **Sees mutation of outer local** — `$x = 1; $c = closure() return $x end; $x = 2; &c` returns `2` (by-reference capture).
- **Mutation from inside closure visible outside** — `$x = 1; $c = closure() $x = 5 end; &c; $x` is `5`.
- **Outlives parent scope** — a closure returned from a function keeps the parent's locals reachable after the parent has returned.
- **Closure of closure captures both scopes** — an inner closure defined inside an outer closure sees both sets of locals.
- **Captures caller's `%chain`** — `%chain` inside the closure body is available and per-frame.
- **`%call.return` exits the closure** — `closure() %call.return 'x'; 'y' end` invoked returns `'x'`.
- **Bare `return` exits enclosing function, not closure** — inside a function body, `&some_method do return 'x' end` returns `'x'` from the enclosing function, not from the closure.
- **`%self` reachable when defined in a method body** — a closure defined inside a method's body sees the method's `%self`.
- **`%bucket` reachable when defined in a method body** — same as above; `@field` writes go to the enclosing method's receiver.
- **`%self` raises outside method context** — a closure defined at the top level referencing `%self` raises.
- **`%bucket` raises outside method context** — same as `%self`.
- **Closures can accept args** — `closure($a, $b) return $a + $b end` called with `(1, 2)` returns `3`.
- **Optional args behave like bare functions** — `closure($a: {default: 5}) return $a end` called with no args returns `5`.
- **Multiple closures share the captured scope** — two closures defined in the same parent see mutations each other makes to shared locals.
- **Closure as callback receives args** — a closure handed to a receiver that yields with args gets those args as `%call.args` (per the `%call` spec) or as parameters when the block declares them.
- **Closure passed cross-role captures original role's locals** — the captured locals remain reachable inside the closure body regardless of who calls it.
- **`do ... end` block is a closure** — a `do` block reading a caller local produces that local's value.
- **`dofunc ... end` block is a bare function** — a `dofunc` block referencing a caller local raises.
