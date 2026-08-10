# Initialize VM

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm",
	"role": "canonical spec for the Initialize VM step in Caspian's bootstrap sequence — the engine's setup of its runtime state store (the MVM, Drinian in V1). Diagram plus brief sections per sub-step, each linking to its own main page.",
	"status": "V1 spec — most details deferred while the step's design lands"
}}
~~~

The fourth step in the bootstrap sequence. The engine brings up its own runtime state — the pieces that must exist before any Caspian code can execute, but that live entirely on the engine side and don't need host input.

![Initialize VM sub-process, top to bottom: open the DB, install infrastructure, initialize the process record, create per-connection state, return the MVM handle.](./init-process.svg)

## Open the DB

`sqlite.open(path)` returns a live SQLite handle; `pragma foreign_keys = on` enables FK enforcement on the connection. Path defaults to `:memory:`.

See [Open the DB](https://www.puck.uno/requirements/bootstrap/initialize-vm/open-db/) for the full sub-step.

## Install infrastructure

`db:exec(schema)` executes the schema text. Creates every table, trigger, index, and view; seeds the user row. Gated on the `drinian` marker table — skipped on already-installed DBs.

See [Install infrastructure](https://www.puck.uno/requirements/bootstrap/initialize-vm/install-infrastructure/) for the full sub-step.

## Initialize the process record

Insert a row into `processes` — persistent, autoincrement pk. Engine holds the fresh pk in a local variable for the next sub-step to write into `current_process`.

See [Initialize the process record](https://www.puck.uno/requirements/bootstrap/initialize-vm/initialize-process-record/) for the full sub-step.

## Create per-connection state

Create the `current_process` TEMP table and write the process pk from the previous sub-step into it. TEMP because the table is per-connection.

See [Create per-connection state](https://www.puck.uno/requirements/bootstrap/initialize-vm/create-per-connection-state/) for the full sub-step.

## Return the MVM handle

`drinian.open()` returns the SQLite handle; the engine stashes it as `engine.mvm`. Everything downstream reads and writes runtime state through that handle.

See [Return the MVM handle](https://www.puck.uno/requirements/bootstrap/initialize-vm/return-mvm-handle/) for the full sub-step.
