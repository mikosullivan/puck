~~~vibecode
{"doc": "primitive-spec", "sprint": "expressions",
	"role": "Engine primitive: short-circuit logical or. Lives in the `.obj` namespace on Object — non-overridable, standard semantics for every value in the language. `%self` (the receiver) is the eager operand; one lazy param — the right-hand operand as a closure. `A || B` in source normalizes to `A.obj.or(B)`, dispatched as `method_call('or', A.obj, [<closure→B>])`. If `%self` is truthy, returns `%self` without invoking the closure; otherwise invokes the closure and returns its value."}
~~~

# or

Short-circuit logical or. Returns `%self` if truthy; otherwise invokes the arg's closure and returns its value. Lives in the `.obj` namespace on Object — non-overridable, standard semantics for every value in the language.

## Signature

    .obj.or(&b)

- **`&b`** — lazy. Passed through as a closure; only invoked if `%self` is falsy.

`%self` (the receiver) is the eager operand — already resolved by the time the method dispatches, so no explicit signature entry is needed for it.

## Pseudocode

~~~lua
function or_(self, b)
	if truthy(self) then
		-- Short-circuit: don't touch `b`. Its closure never fires; any
		-- side effects in the source-level `B` never happen.
		return self
	end

	-- `self` was falsy. Invoke `b`'s closure to get its value.
	return invoke_closure(b)
end
~~~

## Notes

- **Lives on `.obj`, non-overridable.** Semantics are language-level and fixed. No class can override `.or` on itself; every value goes through the same implementation. That's what makes putting it on `.obj` safe — the polymorphism concern that would attend a regular method doesn't apply.
- **`&b` is a closure at call time.** The walker wrapped source-level `B` in a closure at the call site; method_call saw `&b` was lazy in `.or`'s signature and passed the closure through unchanged. `or`'s body has a closure in `b`; `invoke_closure(b)` spawns a nested frame to run the closure body and returns its rv.
- **If `%self` is truthy, `&b` never runs.** Its closure sits unused; no frame ever spawns for it; any side effects in the source-level `B` never fire. This IS the short-circuit — implemented without any walker special case, just "the callee didn't invoke this arg."
- **Returns `%self` itself, not just its truthiness.** `$x = &foo || 'default'` binds `$foo`'s value if truthy, `'default'` if not — matches the Ruby / Perl "return the truthy operand, not a Boolean" convention.
- **Source-level surface.** Users write `$a || $b`, not `$a.obj.or(&b)`. The transpiler normalizes `||` into the `.obj.or` dispatch under the hood; the method form is what the engine sees, not what users type.
- **The Lua function is named `or_`** because `or` is a Lua keyword. At the Caspian level it's `.or`; the underscore is a Lua workaround.
