~~~vibecode
{"doc": "sprint-index", "sprint": "runner",
	"role": "Concept-capture sprint. Asserts that there will be a base class for Runners. A Runner is a process that instantiates an engine, passes the necessary information into it, and calls `run`. Specs TBD — not implementing yet, just noting the shape so downstream design can reference it.",
	"status": "concept noted; specs TBD; not implementing yet"}
~~~

# runner

## Goal

**There will be a base class for Runners.** A **Runner** is a process that:

1. Instantiates an engine.
2. Passes the necessary information to it (source, capabilities, process pk for revival, whatever the run needs).
3. Calls `run`.

Different runners specialize for different contexts (CLI, HTTP request, test harness, REPL, cron, etc.); the base class captures what they have in common.

## Specs

**TBD.** Not designing the base class's shape here — just asserting it will exist.

## Status

**Concept noted. Not implementing yet.**
