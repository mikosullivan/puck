~~~vibecode
{"doc": "primitive-spec", "sprint": "expressions",
	"role": "Engine primitive: dispatches every Caspian call. Called by the walker when it encounters an fc node in CaspM. Receives method name, receiver, and arg-closures; looks up the method on the receiver's class stack; consults its signature; auto-invokes eager arg-closures (spawning nested frames), passes lazy arg-closures through; dispatches the method body; returns the method's return value. Written in Lua — cannot be Caspian (would recurse infinitely). See also the [method-call sprint](https://puck.uno/sprints/method-call/) for the broader design context."}
~~~

# method_call

The engine primitive every Caspian call reduces to. One `fc` node in CaspM → one invocation of this function.

## Invocation

Called from the walker's Lua code, not from Caspian source. There's no Caspian-visible signature — method_call is what IMPLEMENTS the eager/lazy machinery; its own args come from the walker as raw values, not per a signature.

- **`method`** — either a Lua string (the method's name; look it up on the receiver) OR a callable object directly (already-resolved function / closure; skip the lookup). Named `method` rather than `method_name` because it isn't always a name.
- **`receiver`** — Caspian object whose class stack the lookup walks when `method` is a string. When `method` is a callable directly (a closure with its own captured scope, a bare function reference), `receiver` may be nil or ignored.
- **`arg_closures`** — Lua array of Caspian closure objects, one per source-level arg. The walker wrapped each source-level arg expression in a closure; method_call decides what to do with each closure based on the callee's signature.

## Pseudocode

~~~lua
function method_call(method, receiver, arg_closures)
	-- 1. Resolve the callable. Branch on whether `method` is a name to
	--    look up or a callable object handed in directly.
	local callable

	if type(method) == 'string' then
		-- Named dispatch: walk receiver's class stack, top-first.
		callable = find_method(receiver, method)

		if callable == nil then
			return raise('no_such_method: ' .. method .. ' on ' .. class_of(receiver))
		end
	else
		-- Direct dispatch: `method` is already a callable (closure, bare
		-- function reference). No lookup; use as-is. `receiver` may be nil.
		callable = method
	end

	-- 2. Consult the callee's signature to decide per-arg eager vs lazy.
	local sig  = callable.signature
	local args = {}

	for i, closure in ipairs(arg_closures) do
		if sig[i].eager then
			-- 3a. Eager: invoke the closure now; the returned value is the arg.
			args[i] = invoke_closure(closure)
		else
			-- 3b. Lazy: pass the closure through; the callee will `.call` it.
			args[i] = closure
		end
	end

	-- 4. Dispatch the callable with args in place; return whatever it returns.
	return callable.invoke(receiver, args)
end
~~~

## Examples

### Method call on an object

~~~caspian
$foo.bar(1, 2)
~~~

Walker builds:

    method_call('bar', $foo, [<closure→1>, <closure→2>])

Named dispatch. Looks up `bar` on `$foo`'s class stack. Bar's signature declares both args eager, so each arg-closure invokes to produce a value; bar's body runs with those two values.

### Amp-call

~~~caspian
&foo(1, 2)
~~~

Walker builds:

    method_call('call', $foo, [<closure→1>, <closure→2>])

Amp-calls always dispatch `.call` on the receiver. Same shape as any other named dispatch — the method name is just always `'call'`.

### Bare literal

~~~caspian
'foo'
~~~

Walker builds:

    method_call('new', String, [<closure→'foo'>])

Under the walking-skeleton discipline, even a bare-literal command dispatches through method_call — it's a call to `String.new` with the source literal as its sole eager arg. The primitive materializes a Caspian String from the raw source data and returns it; the command's `rv` holds the String. Same primitive for numeric literals (`42` → `method_call('new', Number, [<closure→42>])`), boolean literals, and so on. Leaf-inline optimization will eventually skip this dispatch entirely for bare-literal cases; for now, uniformity through the full mechanism is the point.

### Operator

~~~caspian
1 + 2
~~~

Walker builds:

    method_call('+', 1, [<closure→2>])

Operators are methods on the left operand. Named dispatch to `+`; the primitive `.+` on Number has one eager arg; the arg-closure invokes to Number(2); addition happens.

### Short-circuiting call

~~~caspian
$a || &b
~~~

Walker builds:

    method_call('or', $a.obj, [<closure→b>])

`.or` lives in the `.obj` namespace on Object — non-overridable, single lazy param `(&b)`. `%self` (which is `$a`) is the eager operand; no explicit signature entry for it. method_call sees position 0 is lazy, so the closure passes through unchanged. `.or`'s body receives `%self = $a` and `b = closure_for_b`; if `%self` is truthy it returns without invoking `closure_for_b` — no frame ever spawns for `&b`'s body.

### Ternary

~~~caspian
$foo ? 1 : 0
~~~

Walker builds:

    method_call('if', engine, [<closure→$foo>, <closure→1>, <closure→0>])

`if` is a standalone command (not a binary operator), so it lives on the `engine` namespace rather than on `.obj` of any value. Signature is `(&cond, &then, &else)` — all three lazy. method_call passes all three closures through unchanged. engine.if invokes `&cond`, checks truthiness of the result, then invokes exactly one of the branches. The parser treats `:` as syntactic sugar between the branch args — functionally a fancy comma. Same primitive powers the `if X then A else B end` keyword form.

### Direct dispatch — engine-internal

Not a shape Caspian source produces. Used by engine helpers that already have a callable in hand and want to skip the name-lookup step. For instance, `invoke_closure` (called internally by method_call for its own eager args) could be implemented as:

~~~lua
function invoke_closure(closure)
	return method_call(closure, nil, {})
end
~~~

The `method` position holds the callable itself; `receiver` is nil (the closure carries its own captured scope, so no receiver is needed for scope-lookup); no args to pass. Closures invoked from Caspian source go through named dispatch on `'call'`, not this path.

## Notes

- **Two dispatch modes.** Named (`method` is a string, lookup on receiver's class stack) is what `.foo` / `&foo` / operator calls produce — the transpiler emits string method names. Direct (`method` is already a callable) is what invoking a stored closure or a bare function reference produces — no name to look up. Same primitive; the branch is on the first arg's type.
- **Failure aborts before any arg runs.** In the named-dispatch branch, `find_method` returning nil raises immediately; the loop that invokes closures never starts. Callers can rely on "arg side-effects don't fire unless the method was actually found" (see [eval-algorithm](../eval-algorithm)). Direct dispatch skips this failure mode entirely — the callable was already resolved by whoever handed it in.
- **`invoke_closure` spawns a nested CVM frame** that runs the closure's body. method_call pauses; when the child frame reaps, `invoke_closure` returns the child's rv, which fills the arg slot.
- **method_call doesn't recurse through Lua.** When the closure's body itself contains calls, those calls fire method_call again — but via the frame-dispatch layer, not via direct Lua recursion. The base case is `invoke_closure`, which spawns a frame; the frame runs; when the frame's own dispatch hits a call, THAT triggers a fresh method_call invocation. Lua stack depth stays bounded.
- **`callable.signature`** is a Lua-side representation of the Caspian function's parameter declaration — an array of `{eager: bool}` entries, one per parameter. Populated when the callable was materialized (function definition, method definition, etc.). Both named and direct dispatch resolve to a `callable` that carries this signature.
