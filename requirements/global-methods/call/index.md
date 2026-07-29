# `%call`
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_call",
	"role": "spec for %call — the global method that returns the current call object. Holds the caller's role, exposes early-exit, the callable-value array of blocks the caller passed, and the class the currently-executing method was defined on (%call.method_class — used by the engine's private-method access check and available to user code for the same class-based gating). Yielding to a block is calling the block (no separate primitive) — the `yield` bwc desugars to `%call.blocks[0].call`. Configured calls (DSL wiring, reusable param setup) go through caller objects instead. Distinct from %chain — %call lives on its own, not as a chain entry. The call object is a first-class value: passing it out or stashing it in %chain lets deeply nested code return from the owning function without any intermediate function opting in — that's Caspian's general access rule (if you can see an object, you can call its methods) applied to the call primitive.",
	"settled": "owned by the caller's role; the caller's role is reachable as %call.role; the current method's defining class is reachable as %call.method_class (null when not in a method body); early exit via %call.return; blocks are callable values in %call.blocks; yield bwc = %call.blocks[0].call; DSL wiring lives on caller objects, not on %call; the call object is a first-class value — passing it out or stashing in %chain lets any downstream code call .return on it and unwind to the owning frame",
	"audience": "anyone writing a function or closure body that needs to inspect, return from, or invoke a passed block"
}}
~~~

`%call` is a global method available inside any function or closure body. It returns the **call object** — a first-class object representing the in-progress call. The call object carries the metadata about the call (who made it, what blocks they passed) and provides the primitives for ending the call (`%call.return`).

`%call` is **not** a `%chain` entry. It's its own global, alongside `%chain`, `%engine`, `%import`, etc. It needs no grant — every function body has its own `%call` for the duration of that frame.

## Class identity

`%call` returns an instance of the **Call class** at `caspian.uno/call`. `%call.object.isa?(%('caspian.uno/call'))` is `true`. Direct construction of Call objects by user code is TBD — for V1 the only path to a Call object is `%call` inside a live frame; a constructor-side surface for testing / mocking is a post-V1 question.

## Owned by the caller

The call object is owned by **the caller's role** — not the function's role, not the class's role. Reading `%call` from inside a function body is a cross-role access into the caller's role: what the function sees is the caller's view of the call, not the function-owner's view.

This is intentional. A function call is initiated by the caller; the call object represents the call as the caller initiated it; ending the call (`%call.return`) hands control back to the caller. The role of the call object matches the role of the party the call belongs to.

Consequences:

- `%call.role` is the caller's role.
- `%call.return` exits the call from the caller's side — the caller resumes immediately.
- Anything attached to `%call` (the passed blocks) is caller-side state.

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

## Passing the call object out — return-from-a-distance

The call object returned by `%call` is a **first-class value**. It can be passed as an argument, assigned to a variable, stored in a hash, stashed in `%chain`, or handed off in any other way ordinary values move. Whoever eventually holds it can call `.return $value` on it — and the exception unwinds all the way to the frame the call object represents, not to the caller of the code that fired `.return`.

This follows Caspian's general access rule:

> If you can see an object, you can call its methods.

There's no lexical-scope wall around who's allowed to end a call. If code has a reference to a call object, `.return` works — whether the reference came in through an arg, was pulled from `%chain`, or was fished out of a shared collection.

**Passing via argument.** The receiving function can return from the passing function without any further "returns" propagating up the stack:

~~~caspian
function &gup($foo, $bar)
	&foo %call, $bar     # hand gup's own call object to foo
end

function &foo($caller_call, $bar)
	&bar $caller_call
end

function &bar($caller_call)
	$caller_call.return 'x'   # unwinds directly to gup's boundary
end

puts &gup($foo, $bar)         # prints "x"
~~~

`bar`'s `.return` raises the [`ReturnException`](https://puck.uno/requirements/exceptions/#returnexception) targeted at **gup's** frame. The exception passes through bar's boundary and foo's boundary without stopping — they don't own that call object, so their implicit return-catches don't match — and lands at gup's implicit catch, which unpacks `'x'` as gup's return.

**Stashing via `%chain`.** The same mechanism works without threading the reference through arguments — put it in `%chain` and any downstream code can reach it:

<!-- STALE: ambient-hash-slot moving to %amber -->
~~~caspian
function &gup($foo, $bar)
	%chain['call'] = %call
	&foo $bar
end

function &foo($bar)
	&bar
end

function &bar()
	%chain['call'].return 'x'    # unwinds to gup's boundary
end

puts &gup($foo, $bar)            # prints "x"
~~~

Same end result — bar reads gup's call object out of `%chain` and calls `.return` on it. Neither foo nor bar carries the call object in their signatures; the coupling is invisible at the call sites of foo and bar. That's the trade-off of the `%chain`-based version: less argument clutter, less local readability of "who can return from whom."

**Consequences.** Nested code that can see a call object — through any path — can return from the function that owns the object without any intermediate function opting in. This is the mechanism that makes patterns like "install a handler that can bail out of the whole thing" work with no special syntax; it's also the reason to reason carefully about who you hand a call object to and what you drop into `%chain`.

**Stale call objects.** If the call the object represents has already returned, invoking `.return` on it raises. The specific error surface — and whether it's the same or a different exception class from the normal-path `ReturnException` — is TBD; the guarantee is that a stale `.return` never silently no-ops and never accidentally returns from a newer frame.

## `%call.blocks`

A plain `Array` of all `do...end` and `dofunc...end` blocks the caller passed, in order. Each element is a **callable value** — a closure (from `do`) or a bare function (from `dofunc`), per [calling § do and dofunc blocks](tag:calling#do-and-dofunc-blocks). Calling a block is the same as calling any function: `.call args...` on the block value. Standard array-read surface (`.length`, `.each`, indexed access) applies exactly as on any other array.

~~~caspian
function &branch()
	$blocks = %call.blocks       # array of the passed blocks
	%call.blocks[0].call 'x'     # invoke block 0 with 'x'
end
~~~

**The `yield` bwc.** `yield args...` is a tier-3 bare-word command that desugars to `%call.blocks[0].call args...`. Yielding isn't a separate primitive; it's calling block 0.

~~~caspian
function &logger()
	yield 'starting'             # sugar for %call.blocks[0].call 'starting'
end

&logger do ($msg)
	# $msg = 'starting'
end
~~~

**Multi-block calls.** For blocks beyond index 0, address them directly on the array — `%call.blocks[N].call args...`. There is no dedicated "target block N" primitive; `.call` on the array element is the whole story.

**Configured calls (with DSLs or reusable param setups).** For yielding with a DSL active — or any call that needs configuration before firing — reach for the caller-object surface. See [caller](tag:caller) for the full spec:

~~~caspian
$caller = %call.blocks[0].caller.new
$caller.dsl $log_handler, :info, :warn, :error
$caller.call
~~~

**No-block errors.** `%call.blocks[0]` when no blocks were passed is an out-of-bounds array read — same rule as any other array access. `yield` with no blocks raises for the same reason.

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

They're not interchangeable; `%call.role` is specifically the third one. See [roles/object-access § Class instantiation is not an exception](https://puck.uno/requirements/roles/object-access#class-instantiation-is-not-an-exception) for the broader breakdown.

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

The method body runs in the class's role; `%call.role` is the caller's role; the comparison decides whether to proceed. The full rule for cross-role method access lives in [roles/object-access](https://puck.uno/requirements/roles/object-access#self-gating-from-inside-the-method).

## `%call.method_class`

The class the currently-executing method was defined on, or `null` when the current frame isn't inside a method (a bare function, a closure with no enclosing method, a top-level call).

~~~caspian
class # widget
	method &describe()
		return %call.method_class    # the widget class itself
	end
end
~~~

Parallel to [`%call.role`](#call-role): where `%call.role` gives class-based code a handle on **who called it**, `%call.method_class` gives code inspecting a dispatch a handle on **what class context the current call is running inside**. Both are per-frame properties the engine already tracks (the class context is needed for `super()` and for private-method access checks); `%call.method_class` exposes it as a first-class value.

### Private-method access uses this

The engine's private-method access check reads `%call.method_class` at dispatch time. When code calls a method marked `.private = true` on some receiver, the check is: **is `%call.method_class` a class that defines the method?** If yes, dispatch. If no, raise.

Consequence: a sibling method calling `%self.private_helper()` from inside the class body succeeds because its frame's `%call.method_class` is the class that carries `.private_helper`. Outside code calling `$foo.private_helper()` raises because the outside frame's `%call.method_class` is either some other class (or `null`). References to the object don't carry any special access — the check is always against the current frame at dispatch time.

See [classes/definition § Private methods](https://puck.uno/requirements/classes/definition/#private-methods) for the full private-method spec and [functions/method § Calling sibling methods](https://puck.uno/requirements/functions/method#calling-sibling-methods) for the sibling-call surface.

### Self-gating via method class

User code can gate access the same way the engine does:

~~~caspian
class # widget
	method &internal_op()
		if %call.method_class != %self.object.classes.first
			raise 'internal_op is same-class-only'
		end
		# ...
	end
end
~~~

Same shape as the `%call.role` self-gating example; different axis of gating.

## Catalog

| Surface | Returns | Purpose |
|---|---|---|
| `%call` | call object | The current call. Owned by the caller's role. |
| `%call.role` | role object | Caller's role. |
| `%call.method_class` | class object or null | Class the currently-executing method was defined on; `null` when the frame isn't a method body. Used by the engine's private-method access check and available to user code for the same class-based gating. |
| `%call.return value` | exits the call | End this call (function or closure), returning `value`. |
| `%call.blocks` | plain Array of callables | All blocks the caller passed, in order. Each element is a callable value (closure or bare function). Standard array-read surface (`.length`, `.each`, `[N]`) applies. |
| `%call.blocks[N].call args...` | block return value | Invoke block N with `args...`. The `yield` bwc desugars to `%call.blocks[0].call`. |

## Testing

- **`%call` reachable inside function body** — `function() return %call end; %call` returns a call object; no grant needed.
- **`%call` reachable inside closure body** — a closure body reading `%call` returns its own call object.
- **`%call` reachable inside method body** — a method body reading `%call` returns its own call object.
- **`%call.role` is the caller's role, not the function's role** — a method invoked cross-role reads `%call.role` as the caller.
- **`%call.role` inside top-level user script** — returns the user role.
- **`%call.return` exits function** — `function() %call.return 'x'; 'y' end` invoked returns `'x'`.
- **`%call.return` inside closure exits closure only** — `function() &foo do %call.return 'x' end; return 'y' end` returns `'y'`; the closure body's `%call.return 'x'` did not propagate.
- **Bare `return` inside closure exits enclosing function** — contrast to `%call.return`: bare `return` from a `do` block returns from the surrounding function.
- **`%call.blocks` is an array** — `.length` and indexed access work as on any array read surface.
- **`%call.blocks` in call-site order** — blocks appear in the order they were written at the call site.
- **`%call.blocks[0]` is the first block** — a `do` block written first becomes index 0.
- **`%call.blocks` empty when no blocks passed** — `%call.blocks.length` is 0.
- **`%call.blocks[N].call` invokes block N** — `%call.blocks[0].call 'x'` runs the first block with `'x'` as its argument.
- **`yield` bwc desugars to `%call.blocks[0].call`** — `yield 'x'` and `%call.blocks[0].call 'x'` produce identical behavior.
- **`yield` with no blocks raises** — evaluating `yield` inside a receiver whose caller passed no blocks is an out-of-bounds read on `%call.blocks[0]` and raises.
- **`yield` can be called multiple times** — a function body with `yield 'a'; yield 'b'` invokes the block twice; the block runs to completion each time. The block sees `'a'` on the first call and `'b'` on the second.
- **`yield` can be called zero times** — a function that decides not to invoke `%call.blocks[0].call` runs to completion without touching the block; the block's body never runs.
- **Block invocation return value** — the receiver receives whatever the block returned.
- **`%call` is not in `%chain`** — `%chain.entries` (or equivalent) does not include `%call`; `%call` is its own global. <!-- STALE: %chain.X syntax being reworked -->
- **Each invocation has its own `%call`** — recursive calls see their own frame's `%call`, not the enclosing frame's.
- **Passing a closure and reading `%call.blocks[0]`** — the receiver can inspect the block as a callable value.
- **Self-gating example works** — a method comparing `%call.role != %self.object.role` and raising blocks a cross-role call from a non-owner.
- **`%call.return` inside a bare block controller** — see [exceptions § ReturnException](https://puck.uno/requirements/exceptions/#returnexception) for the frame targeting.
- **Call object passed as an argument returns from the passing frame** — `function &gup() &foo %call end; function &foo($c) $c.return 'x' end; &gup` returns `'x'`; foo's `.return` on gup's call object unwinds through foo's boundary and lands at gup's implicit catch.
- **Call object stashed in `%chain` returns from the stashing frame** — `function &gup() %chain['c'] = %call; &foo end; function &foo() %chain['c'].return 'x' end; &gup` returns `'x'`; the chain read gives foo the same target-gup capability without an argument. <!-- STALE: ambient-hash-slot moving to %amber -->
- **Deep nesting is transparent** — a return-from-a-distance unwinds through any number of intermediate frames without their catches firing; the exception's target frame is the one owning the call object, not the closest enclosing frame.
- **Stale call object raises** — invoking `.return` on a call object whose owning frame has already returned raises (exact class TBD); no silent no-op, no accidental unwind of a newer frame.
- **`%call.method_class` inside a method body** — returns the class the method was defined on. Inside `class # foo; method &m() return %call.method_class end; end`, `$foo.new.m` returns the `foo` class value.
- **`%call.method_class` inside a bare function body** — returns `null`; bare functions have no method-class context.
- **`%call.method_class` inside a closure body** — returns `null` when the closure is defined outside a method; returns the enclosing method's class when the closure is defined inside a method (matching how `%self` inherits from an enclosing method's frame).
- **`%call.method_class` at top level** — returns `null`.
- **Private-method dispatch consults `%call.method_class`** — a call to `$foo.private_helper()` from outside the class raises because the outside frame's `%call.method_class` doesn't match the class carrying `.private_helper`; a call from a sibling method of the same class succeeds because the sibling's `%call.method_class` matches.
- **Captured `%self` does not carry access** — `method &me() return %self end; $obj = $foo.me; $obj.private_helper()` raises when the second call is made from outside the class body; the outside frame's `%call.method_class` is not the private helper's class, regardless of where `$obj` came from.
