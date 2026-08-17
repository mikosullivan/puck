# Initialize VM

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm",
	"role": "canonical spec for the Initialize VM step in Caspian's bootstrap sequence — the engine's setup of its runtime state store (the CVM, CVM in V1). Diagram plus brief sections per sub-step, each linking to its own main page.",
	"status": "V1 spec — most details deferred while the step's design lands"
}}
~~~

The fourth step in the bootstrap sequence. The engine brings up its own runtime state — the pieces that must exist before any Caspian code can execute, but that live entirely on the engine side and don't need host input.

![Initialize VM sub-process, top to bottom: open the DB, install infrastructure, return the CVM handle.](./init-process.svg)

## Open the DB

`sqlite.open(path)` returns a live SQLite handle; `pragma foreign_keys = on` enables FK enforcement on the connection. Path defaults to `:memory:`.

See [Open the DB](https://www.puck.uno/requirements/bootstrap/initialize-vm/open-db/) for the full sub-step.

## Install infrastructure

`db:exec(schema)` executes the schema text. Creates every table, trigger, index, and view; seeds the user row. Gated on the `cvm` marker table — skipped on already-installed DBs.

See [Install infrastructure](https://www.puck.uno/requirements/bootstrap/initialize-vm/install-infrastructure/) for the full sub-step.

## Return the CVM handle

`cvm.open()` returns the SQLite handle; the engine stashes it as `engine.cvm`. Everything downstream reads and writes runtime state through that handle.

See [Return the CVM handle](https://www.puck.uno/requirements/bootstrap/initialize-vm/return-cvm-handle/) for the full sub-step.

## Deferred: process record creation

Earlier drafts had Initialize VM insert a fresh `processes` row here — one process per open. That's been moved out. Under the frames-as-objects design, process rows are created per-run by [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/)'s fresh branch, or handed in by the caller for revival runs. Auto-creating one at open time would allocate a process nobody asked for and force one-process-per-open assumptions on the caller. The old `initialize-process-record/` sub-step doc is retained for historical context but no longer runs at Initialize VM time.
