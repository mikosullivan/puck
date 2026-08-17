# Initialize the process record

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_initialize_process_record",
	"role": "moved: this sub-step no longer runs at Initialize VM time. Process creation is now per-run, in Set up frame 0's fresh branch. This doc is retained for historical context and cross-reference.",
	"status": "moved — see Set up frame 0"
}}
~~~

**This sub-step has moved.** Process creation no longer happens at Initialize VM time. Under the frames-as-objects design, process rows are created per-run:

- **Fresh runs** create their process via [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/)'s fresh branch — one INSERT into `processes` inside the same savepoint that pushes frame 0, so a mid-flight crash can't leave a process row with no frame.
- **Revival runs** are handed a process pk by the caller; Set up frame 0 finds the process's deepest live frame instead of creating a new one.

Auto-creating a process at open time would allocate one nobody asked for and force one-process-per-open assumptions on the caller. Deferring creation to Set up frame 0 lets the same engine `open` support both fresh and revival flows uniformly.

`processes` is a persistent table — rows survive across engine restarts. That's what enables pause / resume: when an engine reopens a CVM file, it can either allocate a fresh `processes` row (fresh run) or look up the pk of a previously-suspended process and revive it. This sub-step's original responsibility has moved to Set up frame 0; see there for the current spec.
