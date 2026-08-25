~~~vibecode
{"doc": "requirements_expressions_primitives_while", "role": "Engine primitive: while loop. Standalone command (not a binary operator) — lives on the engine namespace. Signature is `engine.while($test, $action)` — two EAGER args, both carrying closure values (not lazy-wrapped by the walker; the closures already exist in CaspM). Invokes the test closure; if truthy, invokes the action closure; loops. Exits when the test is falsy. Returns null. Same shape as [engine.if](./if) — closures as values, primitive drives invocation."}
~~~

# while

While loop. Standalone command — lives on the `engine` namespace. Invokes the test closure; if truthy, invokes the action closure; repeats. Exits when the test returns falsy. Returns null.

## Signature

    engine.while $closure, $closure

- **First arg** — eager. A closure value (the test). Invoked before each iteration; its return value decides whether the loop continues.
- **Second arg** — eager. A closure value (the action / loop body). Invoked once per iteration on which the test returned truthy.

Both args are eager. The walker doesn't do lazy-arg wrapping for engine.while — the closures are already IN CaspM (as `cl` atoms the normalizer wraps around the source-level test and body). engine.while receives those closures as values and invokes them selectively.

## Pseudocode

~~~lua
function while_(test, action)
	while truthy(invoke_closure(test)) do
		invoke_closure(action)
	end

	return null
end
~~~

## Source-level shape

| Source | args |
|---|---|
| `while X do Y end` | `[&{X}, &{Y}]` |
| `while X do Y end` (multi-statement body) | `[&{X}, &{ Y1; Y2; Y3 }]` |

Notation: `&{expr}` means "a closure whose body is `expr`."

## Mapping to the current CaspM while atom

The current transpiler emits a `while_end` atom in a positional-array shape:

    ["scope", "while_end", <test-atom>, {"bd": <body-array>}]

- Position 2 is the test — a raw expression atom (in the example, an `fc` for the `.<` comparison). NOT a `cl` closure.
- Position 3 is `{"bd": [...]}` — the body wrapped in a `bd` (body) hash. Also NOT a `cl` closure.

The normalizer's job is to rewrite that atom into an `fc` call to engine.while:

    [{"cmd": "mc"}, {
        "rc": {"var": "engine"},
        "fn": "while",
        "a": [
            <test_closure>,
            <body_closure>
        ]
    }]

Rewrites needed:

- **Replace the `["scope", "while_end", ...]` atom with an `fc` atom** on `engine`.
- **Wrap the test as a closure.** The transpiler emits it as a raw expression atom; the normalizer wraps it in a `cl` so engine.while can invoke it selectively (once per iteration).
- **Wrap the body as a closure.** Convert `{"bd": [...]}` to `{"cl": {"pm": [], "bd": [...]}}` — same body statements, wrapped as a callable closure.

## Notes

- **Standalone command, not a binary operator.** `while` doesn't have a primary operand. Lives on `engine` for the same reason as [engine.if](./if): no receiver value should logically own the dispatch.
- **Both args eager; closures are values.** engine.while doesn't use the lazy-arg mechanism — the closures pre-exist in CaspM (after normalizer rewriting). The walker passes them through as values; engine.while invokes them via `invoke_closure` each iteration.
- **Iteration is the primitive's business.** engine.while loops in its Lua body; `frame_stmt_idx` never moves backward. Each `invoke_closure` call spawns a fresh nested frame for the test / body; those frames run and reap; engine.while continues its loop.
- **Test is re-invoked every iteration.** Each iteration spawns a fresh test frame — the test's closure body executes anew, sees the current state of variables in its captured scope, and returns a fresh value. This is what makes loop-terminating updates (like `$x++` in the body) actually cause the loop to exit: the body mutates `$x` in the captured scope; the next test invocation reads the new value; the loop eventually terminates.
- **Returns null.** The while loop's own return value is null. If a caller wants to accumulate values across iterations, they do it explicitly in the body (writing to variables captured from an enclosing scope). This matches standard imperative loop semantics.
- **Zero iterations if the test is falsy on entry.** No iterations run; the body's closure never invokes; returns null immediately.
- **The Lua function is named `while_`** because `while` is a Lua keyword. At the Caspian level it's `engine.while`; the underscore is a Lua workaround.
