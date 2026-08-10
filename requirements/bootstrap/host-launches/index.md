# Host launches

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_host_launches",
	"role": "canonical spec for the first step in Caspian's bootstrap sequence — how a Lua host process comes up and prepares to load the engine. Covers the host's responsibilities (VM boot, argv acquisition, source acquisition) and what's specifically NOT the engine's problem at this stage.",
	"status": "V1 spec"
}}
~~~

The first step in the bootstrap sequence. A Lua host process starts, the Lua VM initializes, `arg` gets populated with the command-line arguments, and the host figures out which source file to load. This step is entirely the host's concern — the engine hasn't been loaded into memory yet, and Caspian isn't involved.

## What the host does

Different hosts do this differently:

- A **CLI** reads a source file off disk based on argv (`caspian myprogram.casp`).
- An **embedded host** (test runner, Ruby-wrapped Caspian, serverless function) takes source from wherever it already has it — a test fixture, a database blob, an incoming HTTP body.
- A **REPL** starts with no source and accumulates statements interactively.

The output of this step is: a Lua VM is up, and the host has the Caspian source string (or a way to get it) that will eventually be handed to the engine. From here the host proceeds to [Load](https://www.puck.uno/requirements/bootstrap/load/).

## What the engine does

Nothing. The engine module hasn't been loaded yet — [Load](https://www.puck.uno/requirements/bootstrap/load/) is the step where the engine table first exists in memory.

## The CLI is one host

The Caspian CLI is one canonical host that does host-launches + all subsequent bootstrap steps in a specific way. See [bootstrap § The CLI as a host](https://www.puck.uno/requirements/bootstrap/#the-cli-as-a-host) for the CLI's full walkthrough — argv parsing, source reading, capability wiring, exit-code handling.
