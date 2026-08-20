# Stage — `engine:load(source)`

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage",
	"role": "canonical page for the Stage step in Caspian's bootstrap sequence — how the engine takes the Caspian source string, produces the CaspM tree, and sets up frame 0 with the CaspM attached so execution has a stack to walk. Diagram plus brief sections per sub-step, each linking to its own main page.",
	"status": "V1 spec"
}}
~~~

The fifth step in the bootstrap sequence. `engine:load(source)` takes a Caspian source string and gets it ready for execution: parses to CaspM, then inserts frame 0 as an `objects` row with the CaspM in its `ast` column. After Stage returns, the current process's stack has one frame waiting to be walked; bootstrap ends here.

Two sub-steps — under [frames-as-objects](https://www.puck.uno/requirements/cvm/sqlite/) a single INSERT lands both the frame and the CaspM together, so writing the CaspM isn't a separate sub-step of its own.

![Stage sub-process, top to bottom: transpile Caspian to CaspM, then set up frame 0 (an objects row with primitive='f' and the CaspM in its ast column).](./stage-process.svg)

## Transpile — Caspian → CaspM

Parse the Caspian source string and produce the dispatch-ready CaspM tree. Two internal passes (transpile + normalize) treated as one conceptual step.

See [Transpile](https://www.puck.uno/requirements/bootstrap/stage/transpile/) for the full sub-step.

## Set up frame 0

Insert frame 0 as an `objects` row with `primitive = 'f'`, `ast` holding the CaspM directly, `stmt_idx = 0`, `process = <fresh process pk>`, `owner_role = <user pk>`. One INSERT covers both "install the CaspM" and "push the frame" — under frames-as-objects those are the same act. Fresh runs create the process here inside the same savepoint that pushes frame 0; revival runs are handed a process pk by the caller and find its deepest live frame instead.

See [Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/) for the full sub-step.
