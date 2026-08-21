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

Insert the process cap (an `objects` row with `control = 'f'`, `frame_process_cap = 1`, empty `frame_ast`, `frame_stmt_idx = 0`, no parent), then insert frame 0 under it (`control = 'f'`, `frame_ast` holding the CaspM directly, `frame_stmt_idx = 0`, `frame_parent = <cap pk>`, `owner_role = <user pk>`). Two INSERTs — one for the cap, one for frame 0 — cover both "create the process" and "install the CaspM and push the frame" under the frames-as-objects design. Fresh runs create both inside the same savepoint; revival runs are handed the cap's `object_pk` by the caller and find the process's deepest live frame by walking down from the cap via `frame_parent`.

See [Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/) for the full sub-step.
