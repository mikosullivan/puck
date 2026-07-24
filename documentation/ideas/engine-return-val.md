# `%engine.return_val` — return value from the engine

*Post-V1 idea. A settable engine slot that would let a Caspian program signal a value back to the host (test result, embedded-scripting answer, etc.). Removed from V1 because the mechanics weren't clear enough to commit to; captured here so the design work isn't lost.*

~~~vibecode
{"vibecode": {
	"doc": "idea_engine_return_val",
	"role": "captures the deferred `%engine.return_val` design — a user-role-only settable engine slot for a Caspian program to signal an answer back to the host via engine.run()'s return value. Sketched during V1 spec work but pulled before landing because the details weren't clear enough. Reserved for post-V1 revisit.",
	"status": "idea_captured_deferred_until_after_v1",
	"deferred_because": "the mechanics — where the slot lives, what it means for streaming/long-running programs, how it interacts with fork/agent-yield/etc. — weren't clear enough to commit to for V1. V1 hosts get no return value from engine.run(); if a program needs to signal something to the host, use stdout, an explicit callback wired into the engine, or wait for post-V1.",
	"related": ["requirements/bootstrap/initialization (V1 bootstrap sequence — no return value in it now)", "requirements/bootstrap/startup-scenarios (V1 scenarios don't consume a return value)"]
}}
~~~

## The concept

`%engine.return_val` would be a **settable slot** on `%engine` that holds the Caspian program's return value. Whatever the program assigns to it becomes what the host receives from `engine.run()`. If the program never assigns to it, the host receives null.

The only way to return a meaningful value from a Caspian program. Last-statement-value semantics don't apply — the host receives null unless the program explicitly assigns.

~~~caspian
%engine.return_val = 'hello'
~~~

After the program completes, `engine.run()` returns `'hello'` to the host. JS/Python embeddings get it as a native string; Lua hosts get it as a Lua string; etc.

## Sub-decisions that were sketched

### JSON-serializable

The assigned value would have to be JSON-serializable: strings, numbers, booleans, null, arrays of any of those, hashes of string keys to any of those. Constraint exists because hosts in different languages need to marshal the return value across a language boundary, and JSON is the lowest-common-denominator shape every host can handle without custom converters.

Assigning a non-serializable value would raise. The exception class's identity would depend on the naming scheme for engine-emitted error classes.

### User-only

Like every `%engine` slot, `%engine.return_val` would be reachable only from `user`-role code. Non-user code assigning to it would raise by the blanket `%engine` gate. Non-user code can't set the program's return value; only the user-written program can.

### Multiple assignments — last wins

Successive assignments overwrite. The value at program exit is what the host receives:

~~~caspian
%engine.return_val = 'first'
%engine.return_val = 'second'
# ... program continues
%engine.return_val = 'final answer'
~~~

`engine.run()` would return `'final answer'`. Deliberate "last assignment wins" model rather than "must be set exactly once" — a program can decide its return value progressively as it computes, without needing to defer the assignment until the very end.

## Use cases

- **Tests** would assign a structured result the test runner can assert against.
- **Embedded scripting** (Caspian as a logic layer inside a Python/JS/Ruby host) would assign the computed answer the host wanted from running the script.
- **CLIs that signal a value upward** could assign before exiting, though most CLIs care about stdout and exit codes more than the return value.

If a program didn't have a meaningful answer to return, omitting `%engine.return_val` and letting `engine.run()` return null would be the right shape.

## Why deferred

The core reason: the mechanics weren't clear enough to commit to. Concrete concerns:

- **Interaction with streaming / long-running programs.** For a program that runs indefinitely (a server, a `%chain.timer`-driven loop), when is the "final value" delivered to the host? The `engine.run()` return-when-program-exits model works for batch programs; less clear for long-running ones.
- **Interaction with `fork` and `%agent.yield`.** If a forked branch or a yielded-to agent produces a value, does it flow into `%engine.return_val` somehow? Or is that only reachable from the main branch?
- **Interaction with exceptions.** If the program raises mid-run and the host catches, does the last assignment survive as the "return value" or is it forfeit?
- **Interaction with the `user`-role gate on `%engine`.** The user-role restriction on assignment is a natural consequence of the blanket `%engine` gate, but that means non-user-role frames can't participate in producing the return value — which for embedded scripting is often the whole point (the "user" is the host, and the running code is really faucet-role trusted-scripting).

None of these are unsolvable, but each needs a call and V1 was already committing to enough new mechanics.

## V1 alternative

If a V1 program needs to signal something to the host, options:

- **Stdout.** Write structured JSON to `%stdout`; the host parses it. Not elegant but it works.
- **Explicit callback.** The host wires a function into the engine (e.g., `engine.on_result = function(value) ... end`), and the program calls a global that invokes it. Similar to how `engine.stdout` gets wired.
- **Wait for post-V1.** The `%engine.return_val` design revisits this properly once the interaction questions above have answers.

## Draft testing (from the pulled V1 spec)

If this design lands post-V1, these are the tests it should have — preserved from the V1 spec before removal:

- **A program that never assigns `%engine.return_val` yields null to the host** — `engine.run()` returns null.
- **Assigning a string produces that string on the host side** — `%engine.return_val = 'hello'`; host receives `'hello'`.
- **Assigning a number produces that number** — `%engine.return_val = 42`; host receives `42`.
- **Assigning a float produces that float** — `%engine.return_val = 3.14`; host receives `3.14`.
- **Assigning a boolean produces that boolean** — `%engine.return_val = true`; host receives `true`.
- **Assigning `null` explicitly produces null** — different from not assigning; both yield null.
- **Assigning an empty array succeeds** — `%engine.return_val = []` produces `[]` on the host side.
- **Assigning an empty hash succeeds** — `%engine.return_val = {}` produces `{}` on the host side.
- **Assigning an array of JSON-native scalars succeeds** — `[1, 'a', true, null]` round-trips.
- **Assigning a hash of string keys to JSON-native values succeeds** — `{a: 1, b: 'two'}` round-trips.
- **Assigning a deeply-nested JSON-native structure succeeds** — arrays of hashes of arrays of scalars round-trip.
- **Assigning a symbol raises** — symbols are not JSON-native; `%engine.return_val = :sym` raises.
- **Assigning a class instance raises** — user-defined instances are not JSON-serializable in the general case.
- **Assigning a hash with non-string keys raises** — `%engine.return_val = {1: 'a'}` raises.
- **Assigning a function object raises** — functions are not JSON-serializable.
- **Assigning a closure raises** — same reasoning.
- **Assigning a role reference raises** — role objects are not JSON-serializable.
- **Assigning a value with circular references raises** — the cycle can't serialize.
- **Assigning unicode strings round-trips as UTF-8** — `%engine.return_val = 'Zoë'`; host receives `'Zoë'`.
- **Later assignment overwrites earlier** — `'first'` then `'second'`; host receives `'second'`.
- **Non-user role assigning `%engine.return_val` raises** — the blanket `%engine` gate.
- **Reading `%engine.return_val` before writing yields null** — initial slot value.
- **Reading `%engine.return_val` after writing returns the written value** — the slot is round-trippable.
- **Reassigning to the same value is a no-op** — `%engine.return_val = %engine.return_val` doesn't change anything.
- **The slot is a settable slot, not a method call** — `%engine.return_val = X` is assignment; `%engine.return_val(X)` is a different syntax and does not set the slot.
- **Non-user code cannot assign even through a captured reference** — capture doesn't bypass the gate.
