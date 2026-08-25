~~~vibecode
{"doc": "requirements_expressions_primitives_if", "role": "Engine primitive: if / elsif / else / ternary. Standalone command (not a binary operator) — lives on the engine namespace rather than on `.obj`. Signature is `engine.if($conditions, $else_branch)` — two EAGER args that carry closures as values (not lazy-wrapped by the walker; the closures already exist in CaspM). $conditions is an array of `[test_closure, action_closure]` pairs; $else_branch is an optional closure. Matches the current CaspM `if` atom's shape one-to-one: `conditions` field → first arg, `else` field → second arg. Same primitive powers `if ... elsif ... else ... end`, `if X do Y end`, and `X ? Y : Z`."}
~~~

# if

If / elsif / else / ternary. Standalone command — lives on the `engine` namespace. Receives an eager list of `[test, action]` closure-pairs plus an optional else closure. Invokes each test closure in order; on the first truthy result, invokes the matching action closure and returns. If no test matches, invokes the else closure (if present); otherwise returns null.

## Signature

    engine.if([ [closure, closure], [closure, closure]... ], $closure)

- **First arg** — eager. An Array of two-element Arrays. Each inner Array is `[closure, closure]`; both elements are closure values. By convention: index 0 is the test closure (invoked first to check truthiness); index 1 is the action closure (invoked when index 0 returned truthy).
- **Second arg** — eager. A single closure value (the else), or null when the source had no else clause.

Both args are eager. The walker doesn't do lazy-arg wrapping for engine.if — the closures are already IN CaspM (in the `cl` atoms the transpiler emits for `if` bodies and else). engine.if receives those closures as ordinary values and invokes them selectively.

## Pseudocode

~~~lua
function if_(conditions, else_branch)
	for _, pair in ipairs(conditions) do
		local test   = pair[1]
		local action = pair[2]

		if truthy(invoke_closure(test)) then
			return invoke_closure(action)
		end
	end

	if else_branch ~= nil then
		return invoke_closure(else_branch)
	end

	return null
end
~~~

## Source-level shapes

All of these normalize to the same primitive; the `conditions` list length and the presence/absence of `$else_branch` describe the branch structure.

| Source | conditions | else_branch |
|---|---|---|
| `if X then A end` | `[[&{X}, &{A}]]` | null |
| `if X then A else B end` | `[[&{X}, &{A}]]` | `&{B}` |
| `if X then A elsif Y then B end` | `[[&{X}, &{A}], [&{Y}, &{B}]]` | null |
| `if X then A elsif Y then B else C end` | `[[&{X}, &{A}], [&{Y}, &{B}]]` | `&{C}` |
| `if X do Y end` | `[[&{X}, &{Y}]]` | null |
| `X ? A : B` | `[[&{X}, &{A}]]` | `&{B}` |

Notation: `&{expr}` means "a closure whose body is `expr`."

## Mapping to the current CaspM `if` atom

The current transpiler emits an `if` atom shaped:

    {"if": {
        "conditions": [
            {"test": ..., "action": {"cl": ...}},
            {"test": ..., "action": {"cl": ...}}
        ],
        "else": {"cl": ...}
    }}

The normalizer's job is to rewrite that atom into an `fc` call to engine.if:

    [{"cmd": "mc"}, {
        "rc": {"var": "engine"},
        "fn": "if",
        "a": [
            [
                [<test_1_closure>, <action_1_closure>],
                [<test_2_closure>, <action_2_closure>]
            ],
            <else_closure or null>
        ]
    }]

Rewrites needed:

- **Replace the `{if: ...}` atom with an `fc` atom** on `engine`.
- **Fold `conditions` into a list of pairs.** Each `{test, action}` hash becomes a `[test, action]` two-element list.
- **Wrap each test as a closure.** The transpiler currently emits tests as raw var refs / expression atoms; they need to be `cl`-wrapped so engine.if can invoke them selectively.
- **Pass the else through.** Already a `cl` atom in current CaspM; just becomes the second arg. If the source had no else, the second arg is null.

## Notes

- **Matches CaspM's shape directly.** The `conditions` list and `else` field of the current `if` atom become the two positional args to engine.if. No structural rewriting beyond wrapping tests as closures.
- **Standalone command, not a binary operator.** `if` doesn't have a primary operand the way `+` has a left operand. That's why it lives on `engine` instead of on `.obj`.
- **Both args eager; closures are values.** engine.if doesn't use the lazy-arg mechanism — the closures pre-exist in CaspM (as `cl` atoms from the transpiler). The walker passes them through as values; engine.if invokes them selectively via `invoke_closure`.
- **Selective invocation IS the short-circuit.** engine.if invokes tests one at a time until one is truthy; if a test is falsy, its action closure never invokes. Similarly the else invokes only when no test matched. Unused closures sit unused; no frame ever spawns for them; any side effects in their source-level expressions never fire.
- **Ternary reduces here too.** `X ? A : B` produces a 2-arg call with a one-pair conditions list and a non-null else — semantically identical to `if X then A else B end`. Same primitive, three source-level surfaces (keyword `if`, one-arm `if...do...end`, ternary `?:`).
- **The Lua function is named `if_`** because `if` is a Lua keyword. At the Caspian level it's `engine.if`; the underscore is a Lua workaround.
