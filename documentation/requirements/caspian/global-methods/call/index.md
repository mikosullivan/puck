# `%call`
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_call",
	"role": "spec for %call — the global method that returns the current call object. Holds the caller's role, exposes early-exit, yield-to-block, dispatcher, and the blocks passed to the current call. Distinct from %chain — %call lives on its own, not as a chain entry.",
	"settled": "owned by the caller's role; the caller's role is reachable as %call.role; early exit via %call.return; yield and dispatcher for DSL-style block usage",
	"audience": "anyone writing a function or closure body that needs to inspect, return from, or yield back to the current call"
}}
~~~

`%call` is a global method available inside any function or closure body. It returns the **call object** — a first-class object representing the in-progress call. The call object carries the metadata about the call (who made it, what blocks they passed, the dispatcher for DSL-style block use) and provides the primitives for ending the call (`return`, `yield`).

`%call` is **not** a `%chain` entry. It's its own global, alongside `%chain`, `%engine`, `%puck`, etc. It needs no grant — every function body has its own `%call` for the duration of that frame.

## Owned by the caller

The call object is owned by **the caller's role** — not the function's role, not the class's role. Reading `%call` from inside a function body is a cross-role access into the caller's role: what the function sees is the caller's view of the call, not the function-owner's view.

This is intentional. A function call is initiated by the caller; the call object represents the call as the caller initiated it; ending the call (`%call.return`) hands control back to the caller. The role of the call object matches the role of the party the call belongs to.

Consequences:

- `%call.role` is the caller's role.
- `%call.return` exits the call from the caller's side — the caller resumes immediately.
- Anything attached to `%call` (passed blocks, dispatcher state) is caller-side state.

## `%call.return`

Exits the current call — function or closure — with a return value. Inside a closure, it exits the closure without affecting the enclosing function. Distinct from the bare-word `return`, which exits the calling function (propagating through closure boundaries).

~~~caspian
function &foo()
	&bar do
		%call.return 'gup'   # exits the closure; foo continues
	end

	return 'bear'            # exits foo
end
~~~

The distinction:

| Form | What it exits |
|---|---|
| `return value` | The calling function; propagates through closures. |
| `%call.return value` | The current call only — closure if inside a closure, function if inside a function. |

Use `%call.return` when you specifically want to end **this** call regardless of whether it's a function or closure. Use `return` when you want to end the calling function the way a bare-word `return` does in most languages.

## `%call.yield`

Yields control back to the caller's first passed block. The block runs to completion; control returns to the function with the block's return value.

~~~caspian
function &logger()
	%call.yield 'starting'   # caller's block sees 'starting' as the do-block arg
	...
end

&logger do ($msg)
	# $msg = 'starting'
end
~~~

`%call.yield` defaults to the first block (index 0) that the caller passed. For multiple blocks or more complex DSL setup, construct a dispatcher with `%call.dispatcher.new`.

## `%call.dispatcher.new`

Constructs a **dispatcher** — a first-class object that backs DSL-style block configuration. A function uses a dispatcher to register bare-word commands on the `dsl` hash before yielding, so the block can use those commands as if they were keywords. `%call.dispatcher.new(n)` targets the nth passed block; the default targets block 0.

Dispatchers are explicit: bare `yield` (the tier-3 bwc for `%call.yield`) doesn't need one. Construct a dispatcher only when DSL setup is needed.

Full mechanism, examples, and the four-tier token model: [`call/dsl`](https://puck.uno/documentation/requirements/caspian/global-methods/call/dsl).

## `%call.blocks`

An array of all `do...end` blocks the caller passed, in order. Useful when a function accepts a small, fixed set of blocks; for anything beyond a handful, use named-block parameters instead.

~~~caspian
function &branch()
	$blocks = %call.blocks      # array of the passed blocks
	...
end
~~~

The array exposes the blocks themselves; calling them goes through the dispatcher mechanism above. Most code reaches for `%call.dispatcher.new(N)` directly rather than the raw `%call.blocks` array.

## `%call.role`

The role of the calling frame. Available unconditionally inside any function or closure body — no grant required, no chain plumbing.

~~~caspian
function &foo()
	$caller = %call.role
	...
end
~~~

This is the primitive Caspian provides for "who's calling me?" — useful for self-gating, audit, and any code that needs to behave differently based on caller identity.

### Why this works — the role split

Putting the call object on the caller's side (rather than the function's side) is what makes `%call.role` answerable from inside the function. If the call object were function-owned, then asking "who called me?" from inside the function would be asking the function about itself — circular. By making the call object caller-owned, the function gets a handle into the caller's identity that the function can read but cannot forge.

This connects to the broader role-and-ownership model. Three different roles can coexist in one method body:

- The **running frame's role** — `%role`. For methods, this is the class's role; for free-standing functions and closures, the defining role.
- The **instance's role** — `%self.object.role`. Owned by whoever called `.new()`.
- The **caller's role** — `%call.role`. Owned by whoever made this specific call.

They're not interchangeable; `%call.role` is specifically the third one. See [roles/object-access § Class instantiation is not an exception](https://puck.uno/documentation/requirements/caspian/roles/object-access#class-instantiation-is-not-an-exception) for the broader breakdown.

### Self-gating example

Methods can use `%call.role` to restrict access from inside the body, since Caspian has no built-in method-level role gating:

~~~caspian
class &widget
	method &destroy()
		if %call.role != %self.object.role
			raise 'only the owner can destroy this widget'
		end

		...
	end
end
~~~

The method body runs in the class's role; `%call.role` is the caller's role; the comparison decides whether to proceed. The full rule for cross-role method access lives in [roles/object-access](https://puck.uno/documentation/requirements/caspian/roles/object-access#self-gating-from-inside-the-method).

## Catalog

| Surface | Returns | Purpose |
|---|---|---|
| `%call` | call object | The current call. Owned by the caller's role. |
| `%call.role` | role object | Caller's role. |
| `%call.return value` | exits the call | End this call (function or closure), returning `value`. |
| `%call.yield args...` | block return value | Yield to the caller's first block, passing `args...`. |
| `%call.dispatcher.new(n)` | dispatcher | Construct a new dispatcher targeting the nth passed block. Defaults to 0. Created only when DSL setup is needed; bare `yield` doesn't need one. |
| `%call.blocks` | array of blocks | All blocks the caller passed, in order. |

## Testing

- **`%call` reachable inside function body** — `function() return %call end; %call` returns a call object; no grant needed.
- **`%call` reachable inside closure body** — a closure body reading `%call` returns its own call object.
- **`%call` reachable inside method body** — a method body reading `%call` returns its own call object.
- **`%call.role` is the caller's role, not the function's role** — a method invoked cross-role reads `%call.role` as the caller.
- **`%call.role` inside top-level user script** — returns the user role.
- **`%call.return` exits function** — `function() %call.return 'x'; 'y' end` invoked returns `'x'`.
- **`%call.return` inside closure exits closure only** — `function() &foo do %call.return 'x' end; return 'y' end` returns `'y'`; the closure body's `%call.return 'x'` did not propagate.
- **Bare `return` inside closure exits enclosing function** — contrast to `%call.return`: bare `return` from a `do` block returns from the surrounding function.
- **`%call.yield` invokes first passed block** — `%call.yield 'x'` runs `%call.blocks[0]` with `'x'` as its argument.
- **`%call.yield` return value is the block's return value** — the receiver receives whatever the block returned.
- **`%call.yield` with no blocks raises** — a call passing no blocks whose receiver runs `%call.yield` errors.
- **`%call.blocks` is an array** — `.length`, `.push` (no — read-only?), indexed access all work as on any array read surface.
- **`%call.blocks` in call-site order** — blocks appear in the order they were written at the call site.
- **`%call.blocks[0]` is the first block** — a `do` block written first becomes index 0.
- **`%call.blocks` empty when no blocks passed** — `%call.blocks.length` is 0.
- **`%call.dispatcher.new` returns a fresh dispatcher** — two calls return two distinct dispatchers.
- **`%call.dispatcher.new(n)` targets the nth block** — see [`dsl.md` tests](dsl#testing) for full dispatcher behavior.
- **`%call` is not in `%chain`** — `%chain.entries` (or equivalent) does not include `%call`; `%call` is its own global.
- **Each invocation has its own `%call`** — recursive calls see their own frame's `%call`, not the enclosing frame's.
- **Passing a closure and reading `%call.blocks[0]`** — the receiver can inspect the block as a callable value.
- **Self-gating example works** — a method comparing `%call.role != %self.object.role` and raising blocks a cross-role call from a non-owner.
- **`%call.return` inside a bare block controller** — see [exceptions § ReturnException](https://puck.uno/documentation/requirements/caspian/exceptions/#returnexception) for the frame targeting.
