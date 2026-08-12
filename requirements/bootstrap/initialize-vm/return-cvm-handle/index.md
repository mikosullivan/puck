# Return the CVM handle

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_return_mvm_handle",
	"role": "canonical spec for the fourth and final sub-step of Initialize VM — handing the fully-set-up SQLite handle and the fresh process pk back to the engine.",
	"status": "V1 spec — brief"
}}
~~~

The fourth and final sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). `cvm.open()` returns two values: the live SQLite handle and the fresh process pk that [Initialize the process record](https://www.puck.uno/requirements/bootstrap/initialize-vm/initialize-process-record/) allocated. The engine stashes the handle as `engine.cvm` — the field the rest of the engine reads and writes runtime state through — and holds the pk in its own state (bound into queries at the call site).

At this point:

- Foreign keys and recursive triggers are enabled on the connection.
- The full CVM schema is in place, including the seed user row.
- A fresh `processes` row exists; the engine knows its pk.
- The CVM is ready for the [Stage](https://www.puck.uno/requirements/bootstrap/stage/) step to write CaspM into it.

Anything downstream that needs runtime state — Stage, Run, and every method dispatch after that — reads and writes through `engine.cvm`.
