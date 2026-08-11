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

- **Frame 0** — the shape of the initial frame pushed onto the stack. Does it have a callable? What class dispatches it? What locals does it start with?
- **First-dispatch mechanics** — how the engine transitions from "CVM has CaspM" to "the first statement executed."
- **The invocation shape** — explicit `engine:run()`, implicit on first use, coroutine-based, event-loop-driven — all open.
- **Runtime state initialization for the running program** — creating a `processes` row, populating `current_process`, seeding whatever else needs to exist before frame 0 executes.

This page is a placeholder until those decisions land. Details will migrate here as the design settles.
