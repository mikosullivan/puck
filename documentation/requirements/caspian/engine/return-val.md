# `%engine.return_val`
<!--index: 11 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_return_val",
	"role": "spec for %engine.return_val — the settable engine slot that holds the Caspian program's return value. Whatever the program assigns here is what engine.run() hands back to the host; if the program never assigns, the host receives null. The assigned value must be JSON-serializable so any host can marshal it cleanly.",
	"audience": "developers writing programs whose result the host actually consumes (tests, embedded scripting, anything where the host expects an answer)"
}}
~~~

`%engine.return_val` is a **settable slot** that holds the Caspian program's return value. Whatever the program assigns to it becomes what the host receives from `engine.run()`. If the program never assigns to it, the host receives null.

This is the only way to return a meaningful value from a Caspian program. Last-statement-value semantics don't apply — the host receives null unless the program explicitly assigns.

~~~caspian
%engine.return_val = 'hello'
~~~

After the program completes, `engine.run()` returns the value `'hello'` to the host. JS/Python embeddings get it as a native string; Lua hosts get it as a Lua string; etc.

## JSON-serializable

The assigned value must be JSON-serializable: strings, numbers, booleans, null, arrays of any of those, hashes of string keys to any of those. The constraint exists because hosts in different languages need to marshal the return value across a language boundary, and JSON is the lowest-common-denominator shape that every host can handle without custom converters.

Assigning a non-serializable value raises (`puck.uno/error/engine/return-val/not-serializable` or similar — exact UNS TBD).

## User-only

Like every `%engine` slot, `%engine.return_val` is reachable only from `user`-role code. Non-user code assigning to it raises by the blanket `%engine` gate. Libraries can't set the program's return value; only the user-written program can.

## Multiple assignments

Successive assignments overwrite. The value at program exit is what the host receives.

~~~caspian
%engine.return_val = 'first'
%engine.return_val = 'second'
# ... program continues
%engine.return_val = 'final answer'
~~~

`engine.run()` returns `'final answer'`. The intermediate values are forgotten.

This is a deliberate "last assignment wins" model rather than "must be set exactly once" — it lets a program decide its return value progressively as it computes, without needing to defer the assignment until the very end.

## Use cases

- **Tests** assign a structured result the test runner can assert against.
- **Embedded scripting** (Caspian as a logic layer inside a Python/JS/Ruby host) assigns the computed answer the host wanted from running the script.
- **CLIs that signal a value upward** can assign before exiting, though most CLIs care about stdout and exit codes more than the return value.

If a program doesn't have a meaningful answer to return, omitting `%engine.return_val` and letting `engine.run()` return null is the right shape.
