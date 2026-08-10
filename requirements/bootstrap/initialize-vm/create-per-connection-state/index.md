# Create per-connection state

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_create_per_connection_state",
	"role": "canonical spec for the fourth sub-step of Initialize VM — creating the current_process TEMP table and populating it with the process pk from the previous sub-step.",
	"status": "V1 spec — brief"
}}
~~~

The fourth sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). Creates the `current_process` TEMP table (schema per [drinian.sql § current_process](https://www.puck.uno/src/engine/drinian.sql#current-process-per-connection-runtime-state)) and writes `('current_process_pk', <pk>)` into it — where `<pk>` is the process pk that [Initialize the process record](https://www.puck.uno/requirements/bootstrap/initialize-vm/initialize-process-record/) allocated.

**Why TEMP.** SQLite TEMP tables are per-connection: created fresh with each connection open, gone when the connection closes. That matches "one running process per connection" — pause = close the connection = `current_process` vanishes; revive = new connection = fresh `current_process` populated from persistent state in `main`.

**Why it can't be in the main schema.** The `create table` statements in `drinian.sql` run once at DB creation. A TEMP table has to be created every connection open, so it lives in `drinian.lua`'s open path instead.
