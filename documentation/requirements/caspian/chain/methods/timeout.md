# `%chain.timeout`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_timeout",
	"role": "spec for %chain.timeout — cap a block's wall-clock duration. Two independent thresholds: unwind (raises a catchable soft-timeout exception that unwinds the stack normally) and kill (raises a hard-timeout exception that abandons the block's frames without running ensure blocks or finalizers). At least one threshold must be given."
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.timeout` runs a block under a wall-clock budget. Both thresholds are keyword-only, both are given in seconds, and **at least one of them must be supplied**:

| Keyword | What happens when it fires |
|---|---|
| `unwind:` | Raises `puck.uno/error/soft_timeout` in the block's frame. The stack unwinds normally: ensure blocks run, finalizers execute, objects are cleaned up. Outer frames can catch the exception like any other. |
| `kill:` | Abandons the block's frames without unwinding — no ensure blocks, no finalizer runs, no orderly cleanup. Raises `puck.uno/error/hard_timeout` at the enclosing frame. Objects held only by the abandoned frames are dropped without their normal lifecycle events. |

The two are independent; you can specify either alone, or both together.

## Three idioms

~~~caspian
# Soft cutoff only — unwind is allowed to run as long as it needs.
# Caller is accepting that if a hung ensure block prevents unwind from
# completing, this call runs forever.
%chain.timeout(unwind: 3) do
    # work with cleanup that is trusted to finish quickly on unwind
end
~~~

~~~caspian
# Hard cutoff only — no cleanup, no ensure. For runaway/hung code you
# can't trust to unwind cleanly.
%chain.timeout(kill: 3) do
    # work that might loop forever or block indefinitely
end
~~~

~~~caspian
# Belt and suspenders: unwind first, then kill if unwind takes too long.
# The common shape for real code.
%chain.timeout(unwind: 3, kill: 5) do
    # normal work; unwind will attempt clean cleanup, but a hung
    # ensure block can't push past 5 seconds total.
end
~~~

## The two exception classes

Both thresholds fire by **raising an exception**. There is no silent-return case — if code past `%chain.timeout(...) do ... end` needs to run whether the block completed or not, the caller MUST catch the timeout exception. An uncaught soft-timeout or hard-timeout propagates upward like any other unhandled exception and terminates the process at the top frame.

- **`puck.uno/error/soft_timeout`** — raised at the `unwind:` deadline. Propagates as a normal exception; ensure blocks run as the stack unwinds; can be caught at any outer frame.
- **`puck.uno/error/hard_timeout`** — raised at the `kill:` deadline. Skips the abandoned frames entirely and appears at the enclosing frame outside the timeout block. Can still be caught, but any state in the abandoned frames is unrecoverable.

Both are ordinary exception classes. The exception system itself — how exceptions are raised, how they're caught, how ensure/finalizer chains attach — is a separate spec that will be filled in later. The rules here describe what `%chain.timeout` **produces**; how the surrounding code intercepts those exceptions will be defined when the exception spec lands.

## Timeout exceptions can't be caught inside the block

**A timeout's own exception is invisible to catch handlers inside its own block.** Code inside the block can't intercept the timeout that governs it — if it could, the block could neutralize its own deadline, which would defeat the point. Timeout exceptions pass through any inner catch machinery and surface only at frames OUTSIDE the `%chain.timeout(...) do ... end` block.

Ensure/finalizer runs INSIDE the block are unaffected — during a soft-timeout unwind, ensure blocks execute normally. The "can't catch" rule is specifically about catch handlers, not about the whole exception-propagation machinery.

The rule doesn't apply to a **nested** `%chain.timeout` inside another `%chain.timeout`. Each timeout is opaque only to its own exception: an inner timeout can catch its own inner-timeout exception; an outer timeout catches its own; they don't intercept each other.

## Validation

Rejected at call time (raises before the block starts):

- **Neither `unwind:` nor `kill:` given.** A `%chain.timeout` with no thresholds is meaningless; the call raises.
- **`kill:` ≤ `unwind:`.** If both are specified, `kill:` must be strictly greater than `unwind:` (otherwise the kill fires before or at the same time as the unwind and unwinding can't happen).
- **Zero or negative value.** Both thresholds must be positive.

## Granularity

The check happens at safe points inside the interpreter, not mid-instruction. Pure-CPU loops that never reach a safe point will overrun their threshold; in practice that's rare since virtually any Caspian operation reaches a safe point quickly. For code that DOES risk staying in a hot loop without hitting a safe point, `kill:` is the escape hatch — the engine's hard-timeout mechanism doesn't rely on the block cooperating.
