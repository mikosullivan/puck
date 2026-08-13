# Execution

~~~vibecode
{"vibecode": {
	"doc": "requirements_execution",
	"role": "landing page for Caspian's execution phase — the operational phase that follows bootstrap. Starts the moment `engine:run()` is called on a fully-bootstrapped engine, ends when the program terminates. Distinct from bootstrap (which prepares the engine to run); this area covers running.",
	"status": "placeholder — spec deferred pending design work on frame 0, first-dispatch mechanics, and the run() invocation shape"
}}
~~~

Execution is the operational phase — everything that happens after [bootstrap](https://www.puck.uno/requirements/bootstrap/) hands over a fully-prepared engine. Bootstrap gets the CVM open, seeded, and loaded with a CaspM tree; execution walks that tree and dispatches. The first user statement runs; the last user statement returns; anything in between is execution.

The name `engine:run()` (or whatever the invocation ends up being called) is a boundary: the call is bootstrap's last act as the host wiring the engine, and the first act of the execution phase.

## What is known

- After bootstrap returns, the CVM holds a loaded program (CaspM tree) alongside a seeded runtime state store.
- The engine walks that CaspM and dispatches each statement.
- Dispatch reaches the first line of the loaded program.

## What is deferred

Almost everything else about this phase is open design work:

- **Frame 0** — settled at the schema level by [frames-as-objects](https://www.puck.uno/requirements/cvm/): it's an `objects` row with `primitive = 'f'` and the CaspM in its `ast` column, populated by [Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/). What remains open at the runtime level is how the frame ADVANCES — see the "First-dispatch mechanics" bullet below. Closure-lifetime questions live in the closure-design slice, not here.
- **First-dispatch mechanics** — how the engine transitions from "CVM has CaspM" to "the first statement executed."
- **The invocation shape** — explicit `engine:run()`, implicit on first use, coroutine-based, event-loop-driven — all open.

This page is a placeholder until those decisions land. Details will migrate here as the design settles.
