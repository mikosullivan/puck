# Stage — `engine:load(source)`

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage",
	"role": "canonical page for the Stage step in Caspian's bootstrap sequence — how the engine takes the Caspian source string, produces the CaspM tree, writes it into the CVM, and sets up frame 0 so execution has a stack to walk. Diagram plus brief sections per sub-step, each linking to its own main page.",
	"status": "V1 spec in progress — SLATED FOR COMPLETE OVERWRITE when frames-as-objects promotes to requirements/; structure, sub-step count, and per-page content will all change"
}}
~~~

> **Overwrite pending.** This entire Stage section — this page and every sub-step under it — will be rewritten when [frames-as-objects](https://www.puck.uno/ideas/frames-as-objects/) promotes to `requirements/`. Structure, sub-step count, and per-page content are all expected to change (Install CaspM collapses into Set up frame 0; the frame lands as an `objects` row, not a `frames` row). Read anything below as pre-integration state.

The fifth step in the bootstrap sequence. `engine:load(source)` takes a Caspian source string and gets it ready for execution: parses, writes the resulting CaspM into the CVM, and sets up the top-level frame. After Stage returns, the stack has one frame waiting to be walked; bootstrap ends here.

![Stage sub-process, top to bottom: transpile Caspian to CaspM (implemented), install CaspM plus metadata into the CVM (not yet implemented), set up frame 0 (not yet implemented).](./stage-process.svg)

## Transpile — Caspian → CaspM

Parse the Caspian source string and produce the dispatch-ready CaspM tree. Two internal passes (transpile + normalize) treated as one conceptual step.

See [Transpile](https://www.puck.uno/requirements/bootstrap/stage/transpile/) for the full sub-step.

## Install CaspM into the CVM

Write CaspM plus metadata (origin, hash, transpiler-version tag) into the CVM so the engine can retrieve it during dispatch. Storage shape not yet settled — blob, decomposed rows, or object-graph.

See [Install CaspM into the CVM](https://www.puck.uno/requirements/bootstrap/stage/install-caspm/) for the full sub-step.

## Set up frame 0

Insert the top-level frame into the `frames` table so the stack has an entry ready to be walked. Frame 0's shape (with or without a callable) is open.

See [Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/) for the full sub-step.
