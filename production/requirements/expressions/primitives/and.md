~~~vibecode
{"doc": "requirements_expressions_primitives_and", "role": "Engine primitive: short-circuit logical and. Lives in the `.obj` namespace on Object — non-overridable, standard semantics for every value in the language. `%self` (the receiver) is the eager operand; one lazy param — the right-hand operand as a closure. `A && B` in source normalizes to `A.obj.and(B)`, dispatched as `method_call('and', A.obj, [<closure→B>])`. If `%self` is falsy, returns `%self` without invoking the closure; otherwise invokes the closure and returns its value. Mirror image of [or](./or)."}
~~~

# and

Short-circuit logical and. Returns `%self` if falsy; otherwise invokes the arg's closure and returns its value. Lives in the `.obj` namespace on Object — non-overridable, standard semantics for every value in the language.

## Signature

    .obj.and(&b)

- **`&b`** — lazy. Passed through as a closure; only invoked if `%self` is truthy.

`%self` (the receiver) is the eager operand — already resolved by the time the method dispatches, so no explicit signature entry is needed for it.

## Pseudocode

~~~lua
function and_(self, b)
	if not truthy(self) then
		-- Short-circuit: don't touch `b`. Its closure never fires; any
		-- side effects in the source-level `B` never happen.
		return self
	end

	-- `self` was truthy. Invoke `b`'s closure to get its value.
	return invoke_closure(b)
end
~~~

## Notes

- **Lives on `.obj`, non-overridable.** Same rule as [or](./or): semantics are language-level and fixed. No class can override `.and` on itself.
- **`&b` is a closure at call time.** Same mechanism as [or](./or): the walker wrapped source-level `B` in a closure; method_call saw `&b` was lazy in `.and`'s signature and passed the closure through; `.and`'s body invokes it if it needs the value.
- **If `%self` is falsy, `&b` never runs.** Symmetric to or's short-circuit — the callee didn't invoke the arg; no frame spawns; no side effects fire.
- **Returns `%self` itself when falsy.** `$x = &foo && 'ok'` binds `$foo`'s value if falsy (which is the value that STOPPED evaluation), `'ok'` if truthy. Matches the Ruby / Perl convention.
- **Source-level surface.** Users write `$a && $b`, not `$a.obj.and(&b)`. The transpiler normalizes `&&` into the `.obj.and` dispatch under the hood.
- **The Lua function is named `and_`** because `and` is a Lua keyword. Same reason as [or's `or_`](./or).
