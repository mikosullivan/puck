# Open the DB

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_open_db",
	"role": "canonical spec for the first sub-step of Initialize VM — two ordered actions on the same handle: get the handle back from sqlite.open, then set pragma foreign_keys = on on that handle.",
	"status": "V1 spec — brief"
}}
~~~

The first sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). Two ordered actions on the same handle:

1. **Get the handle.** `sqlite.open(path)` returns a live SQLite handle. Path defaults to `:memory:` — a fresh in-memory database that vanishes when the connection closes. Callers pass a file path for persistence (needed for pause / resume).

2. **Configure the handle.** `db:exec('pragma foreign_keys = on')` enables FK enforcement on that connection. FKs are **off by default in SQLite**, and the pragma is per-connection, not per-database — every open pays this cost, no exceptions. The schema leans hard on FK cascades (role tree cleanup, frame pops, bucket / stack deletion), so this pragma isn't optional; leaving it off would silently strand child rows on parent delete.

Order matters within this sub-step: the pragma has no meaning without a handle to set it on. Both must complete before [Install infrastructure](https://www.puck.uno/requirements/bootstrap/initialize-vm/install-infrastructure/), because the DDL declares FK-referencing tables with cascade clauses that assume enforcement is live.
