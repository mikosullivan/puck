# Initialize the process record

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_initialize_process_record",
	"role": "canonical spec for the third sub-step of Initialize VM — inserting a fresh row into the persistent processes table and holding onto its pk.",
	"status": "V1 spec — brief; the fresh-vs-revival branch isn't yet spec'd"
}}
~~~

The third sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). `insert into processes default values` allocates a fresh `process_pk` (autoincrement). The engine holds that pk in a local variable for the next sub-step ([Create per-connection state](https://www.puck.uno/requirements/bootstrap/initialize-vm/create-per-connection-state/)) to write into the `current_process` TEMP table.

`processes` is a persistent table — rows survive across engine restarts. That's what enables pause / resume: when an engine reopens a MVM file, it can either allocate a fresh `processes` row (new run) or look up the pk of a previously-suspended process and revive it.

**Fresh vs revival.** Currently every engine allocates a fresh row. A revival path (find an existing process, reattach to it) isn't yet spec'd. Which one runs is a bootstrap-mode decision — open question.
