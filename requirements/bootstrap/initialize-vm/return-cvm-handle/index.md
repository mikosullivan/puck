# Return the CVM handle

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_return_mvm_handle",
	"role": "canonical spec for the fifth and final sub-step of Initialize VM — handing the fully-set-up SQLite handle back to the engine.",
	"status": "V1 spec — brief"
}}
~~~

The fifth and final sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). `cvm.open()` returns the live SQLite handle. The engine stashes it as `engine.cvm` — the field the rest of the engine reads and writes runtime state through.

At this point:

- Foreign keys are enforced on the connection.
- The full CVM schema is in place, including the seed user row.
- A fresh `processes` row exists, its pk recorded in the `current_process` TEMP table.
- The CVM is ready for the [Stage](https://www.puck.uno/requirements/bootstrap/stage/) step to write CaspM into it.

Anything downstream that needs runtime state — Stage, Run, and every method dispatch after that — reads and writes through `engine.cvm`.
