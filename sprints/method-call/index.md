~~~vibecode
{"doc": "sprint-index", "sprint": "method-call",
	"role": "Engine primitive that dispatches every Caspian call. Written in Lua; NOT expressible as Caspian code (calling method_call from Caspian would dispatch via method_call — infinite recursion). Takes a method name, a receiver, and args (already positioned by the walker per the callee's signature). Looks up the method on the receiver's class stack, invokes it. All Caspian syntax that involves calls — amp-calls `&foo`, dot-method-calls `$foo.bar`, operators (`+`, `<`, etc.) — collapses in CaspM to `fc` atoms; the engine dispatches each `fc` via method_call.",
	"status": "brainstorm — seed concept captured"}
~~~

# method-call

Engine primitive that dispatches every Caspian call. One atom shape at the CaspM level (`fc`); one primitive at the engine level (method_call). Everything else in the language (functions, control flow, operators) is Caspian code running via this dispatch.

## What it does

Given a method name, a receiver, and args, method_call:

1. Looks up the method by name on the receiver's class stack (top-of-stack first — shadow, then declared classes in stack order).
2. Invokes the method with the args.
3. Returns the value the method returned.

## Signature

Lua:

~~~lua
function method_call(method_name, receiver, args)
	-- method_name: string
	-- receiver:    Caspian object (with a class stack)
	-- args:        table of already-evaluated values (eager) and thunks (lazy),
	--              positioned per the callee's signature by the walker before
	--              this function is called
	-- returns:     the method's return value
end
~~~

The walker handles eager-vs-lazy dispatch BEFORE reaching this function. Eager arg positions have already been reduced to values; lazy arg positions carry unreduced thunks. method_call itself doesn't know or care about eager/lazy; it just invokes the method with whatever's in `args`.

## Why it's an engine primitive, not a Caspian function

If method_call were a Caspian function, calling it would dispatch via method_call — and calling THAT dispatch would dispatch via method_call — infinite recursion. The engine has to provide the base dispatch as a Lua function that sits below the Caspian layer.

Same reason `+` on Number and `.call` on function objects have to be engine primitives: they're the operations Caspian assumes exist, so they can't themselves be defined in Caspian.

## Relationship to other sprints

- **[expressions](https://puck.uno/sprints/expressions/)** — the walker's `fc` dispatch calls this primitive. Every `fc` node in a CaspM tree reduces by evaluating its receiver + eager args, packaging up lazy args as thunks, then invoking method_call.
- **[lazy-params](https://puck.uno/sprints/lazy-params/)** — provides the signature mechanism the walker consults to decide which arg positions are eager vs lazy. method_call itself doesn't touch signatures; the walker's `ready` predicate does that work upstream.
