# Return the CVM handle

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_return_cvm_handle",
	"role": "canonical spec for the third and final sub-step of Initialize VM — handing the fully-set-up SQLite handle back to the engine.",
	"status": "V1 spec — brief"
}}
~~~

The third and final sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). `cvm.open()` returns the live SQLite handle; the engine stashes it as `engine.cvm` — the field the rest of the engine reads and writes runtime state through.

At this point:

- Foreign keys and recursive triggers are enabled on the connection.
- The full CVM schema is in place, including the seed user row.
- No `processes` row exists yet — process creation is per-run, in [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/)'s fresh branch, or handed in by the caller for revival.
- The CVM is ready for the [Stage](https://www.puck.uno/requirements/bootstrap/stage/) step to write CaspM into it.

Anything downstream that needs runtime state — Stage, Run, and every method dispatch after that — reads and writes through `engine.cvm`.
