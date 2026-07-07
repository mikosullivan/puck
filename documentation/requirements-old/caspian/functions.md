# Functions

*A `function` in Caspian is a closed unit of code — it can only see its own parameters. Outer scope is invisible. The `closure` form captures outer scope; `function` deliberately does not.*

~~~vibecode
{"vibecode": {
	"doc": "caspian_functions",
	"role": "spec for the Caspian function form's scoping rule — functions are closed and can only see their declared parameters; closures (a separate form) capture outer scope",
	"key_concepts": ["function_is_closed_no_outer_scope_capture",
		"function_can_only_see_its_declared_params",
		"closure_is_the_separate_form_that_captures_scope",
		"explicit_params_are_the_only_input_channel"]
}}
~~~

A **function** in Caspian sees only what's passed to it as a parameter. Variables in the surrounding code — locals, top-level bindings, anything outside the function's own param list — are **invisible** from inside the function body. This is by design: functions are closed units, intentionally restricted to their explicit inputs.

```
$message = 'hello'

$greet = function() do
    &print($message)    # ERROR — $message is invisible here
end
```

The function body has no access to `$message` even though it's declared right above. Inside `function() do ... end`, the only variables in scope are the function's own parameters (none, in this example) and anything declared inside the body.

## What a function can see

A function body can see:

- Its own declared parameters.
- Variables it declares inside its own body with `$var = ...`.
- **`%chain`** — the ambient capability channel that carries every default-reachable global method (`%now`, `%stdout`, `%net`, ...) plus anything the caller placed on the chain before calling. This is the same `%chain` methods have; it's per-frame and always reachable inside any function, closure, or method body.
- Other system surfaces accessible by sigil (`%engine`, `%puck`, etc. — these aren't scope captures, they're language primitives).
- Module members, when the function is defined as a method on a module (see [modules.md](modules.md)).

That's the whole list. A function cannot see:

- Locals from the enclosing function or block.
- Top-level bindings.
- Other functions defined at the same level (unless they're explicitly passed in, or both are methods on the same module).

## The closure alternative

When you need to capture outer scope, use **`closure`** instead of `function`:

```
$message = 'hello'

$greet = closure() do
    &print($message)    # OK — closure captures the surrounding scope
end
```

`closure` and `function` look syntactically similar but have opposite scoping behavior: `function` is closed and explicit; `closure` is open and captures. Two distinct forms, chosen deliberately by the developer based on whether outer scope should be visible.

## Why this matters for `function`

The closed scoping is what makes Caspian functions safe units of code to pass around, run under different roles, send across role boundaries, hand to an AI agent via [`$agent.yield`](https://puck.uno/documentation/ideas/agent-yield), or otherwise execute in contexts other than where they were defined. A function's behavior is fully determined by its parameters and its body — there's no hidden state from the surrounding scope that would silently affect what it does.

This is the same property that lets the [roles system](https://puck.uno/documentation/requirements/caspian/roles) reason about cross-role calls cleanly: when a function is invoked across a role boundary, the engine knows exactly what the function can see — its parameters and nothing else.

## See also

- [Modules](https://puck.uno/documentation/requirements/caspian/modules) — how mutual function references work when functions can't see each other (modules provide a shared object for method-style calls).
- [Caspian roles](https://puck.uno/documentation/requirements/caspian/roles) — why closed function scope is important for the security model.
- [Parameters](https://puck.uno/documentation/requirements/caspian/syntax/parameters) — declaring what a function takes in.
