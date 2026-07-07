# Closure
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_functions_types_closure",
	"role": "spec for the closure type — a function that captures its outer lexical scope at the point of definition. No `%self`. `%chain` is available same as in bare functions and methods. Used for callbacks, deferred work, and any pattern where a chunk of code needs to remember the environment it was born in. Content TBD beyond the shape captured here.",
	"status": "draft — surface described; deeper semantics of scope capture, mutation, and lifetime to be filled in",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

A **closure** is a function that captures its outer lexical scope. Everything the enclosing scope had bound at the point of definition is reachable from the closure's body.

Inside the body:

- **No `%self`.** A closure isn't bound to a receiver. Referring to `%self` inside a closure raises.
- **Outer-scope capture.** Names defined in the enclosing scope are reachable from the closure body — the closure carries a reference to that scope so the bindings survive as long as the closure does.
- **[`%chain`](https://puck.uno/documentation/requirements/caspian/chain/)** — the ambient capability channel, same as in bare functions and methods. Per-frame and always reachable; carries `%now`, `%stdout`, `%net`, and every other granted global.
- **What's reachable.** Arguments passed in, names defined locally in the body, names inherited from the captured outer scope, and `%chain`. The lexical capture is by reference: if the outer scope mutates a binding after the closure is defined, the closure sees the mutation.

## return and %call.return

Closures use `%call.return $value` to exit. The bare `return` keyword returns from the enclosing function or method, not from the closure itself — matching the general rule that `return` targets a function or method boundary while `%call.return` targets whichever frame is currently `%call`. See [exceptions § ReturnException](https://puck.uno/documentation/requirements/caspian/exceptions/#returnexception).

## Common use cases

- **Callbacks.** A closure passed to a method or function that runs it later — the closure keeps access to whatever the caller had in scope at the moment of registration.
- **Deferred work.** Building up code that runs "later," when the enclosing state has already moved on.
- **Higher-order patterns.** Any place where a function needs to remember more than its arguments.

## When a function is a closure

A function is a closure when it's declared with the `closure` keyword. That keyword is what triggers outer-scope capture — a bare `function` in the same location would not capture, and a `method` in the same location would bind to a receiver instead. `closure` can appear anywhere `function` can: top level, inside another function or closure body, inside a method. See [bare function](bare) and [method](method) for the other two types.
