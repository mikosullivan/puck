~~~vibecode
{"doc": "primitive-spec", "sprint": "expressions",
	"role": "Engine primitive: binds a value to a local variable in the caller's scope. Both params eager. `$x = 5` in source normalizes to `assign('x', 5)` in CaspM; the walker's fc dispatch reaches this primitive with the name materialized and the value already evaluated. Returns the bound value so chained assignments like `$x = $y = 5` fall out."}
~~~

# assign

Binds a value to a local variable in the caller's scope. `$x = 5` in source is this call.

## Signature

    assign($name, $value)

- **`$name`** — eager. The variable name as a materialized String.
- **`$value`** — eager. The value to bind. Fully evaluated before assign runs.

Both eager because assign needs both concrete values before it can do the storage — there's nothing to defer.

## Pseudocode

~~~lua
function assign(name, value)
	-- Reach into the caller's frame (the frame that dispatched us) and
	-- work against its scope chain. Engine-internal — Caspian code
	-- cannot reach across frame boundaries this way.
	local caller_frame = current_frame().parent
	local scopes       = caller_frame.scopes

	-- Walk from innermost to outermost. If `name` is already defined
	-- somewhere, rebind it in that scope and stop.
	for i = 1, #scopes do
		if scopes[i][name] ~= nil then
			scopes[i][name] = value
			return value
		end
	end

	-- Not defined anywhere in the chain. Fresh binding — add it to the
	-- outermost scope (the last entry in the chain).
	scopes[#scopes][name] = value

	return value
end
~~~

## Notes

- **Reaches across the frame boundary to bind in the caller's scope.** assign runs in its own frame (per walking-skeleton discipline), but the binding has to land in the CALLER's scope chain — that's where `$x` lives semantically. This is engine-internal access; Caspian code can't reach out this way.
- **Rebinding walks the whole chain.** If `name` is already defined in some enclosing scope, `$x = 5` rebinds it AT THAT SCOPE — it doesn't shadow with a new innermost binding. Same variable, same slot; the write is visible everywhere `$x` was already reachable.
- **Fresh bindings land in the outermost (last) scope.** If `name` isn't defined anywhere in the chain, `assign` creates it in `scopes[#scopes]` — function-level, not block-level. `$x = 5` inside a nested block, if `$x` was previously undefined, hoists to function scope. (Similar to JavaScript `var`, not `let`.)
- **Returns the bound value.** Chained assignment (`$x = $y = 5`) works because the inner assign returns 5, and the outer assign receives that as its `$value` arg.
- **Scope chain convention.** `scopes[1]` is the innermost (current block); `scopes[#scopes]` is the outermost (function-level). The `for i = 1, #scopes` walk is innermost-first — matches how var LOOKUP works.
