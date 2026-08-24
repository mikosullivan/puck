~~~vibecode
{"doc": "sprint-index", "sprint": "stop",
	"role": "Fill out the spec for `%process.stop` — the primitive that halts execution in place, leaves the CVM as-is, and returns control to the Lua caller. Already partially implemented (a ProcessStop handler in production, no dedicated spec doc). Sprint's job is to write the spec: what shape it takes in Caspian source, what CaspM the transpiler produces, what state is preserved on halt, how resume works (or doesn't), how it interacts with the frame chain, rv slot, and GC, and what the intended usage patterns are.",
	"status": "seed — problem captured. Not being sprinted right now."}
~~~

# stop

Fill out how `%process.stop` works.

## What exists today

- **Handler** at [production/src/engine/handlers/process-stop.lua](https://puck.uno/production/src/engine/handlers/process-stop.lua) — recognizes the fc-shape row (head `{in='fc'}`, call atom with `fn='stop'` and `rc.sys='process'`), sets `engine.stopped = true`, returns. No schema writes, no cleanup.
- **Walker check** — the dispatch loop reads `engine.stopped` per iteration; when true, breaks out before advancing frame_stmt_idx.
- **Return shape** — `engine:run()` returns `{stopped = 1, cap_pk = <pk>}` when halted (versus `{complete = 1, cap_pk = <pk>}` on normal completion).
- **Two spec mentions** — the docstring in the handler file, and the walkthrough at [production/requirements/cvm/sqlite/x-equals-1](https://puck.uno/production/requirements/cvm/sqlite/x-equals-1) which uses `%process.stop` to freeze the state after `$x = 1` for inspection.

No dedicated spec doc for the construct itself.

## What the sprint fills in

Rough scope — details fill in as the sprint runs:

- **Source syntax.** `%process.stop` — the `%` sigil is [engine-system access](tag:engine-system-methods). No args in V1; possibly args later (a message, a numeric code).
- **CaspM shape.** The exact row shape the normalizer produces. Currently a bare fc with no args.
- **Semantics: what "halts in place" means.**
  - Frame the halt happens IN is left at its current stmt_idx.
  - Rv slot state depends on whether the halted frame had already set one — spec needs to spell out the observable state.
  - No frame reap, no GC pass, no cascade — the database is exactly what the last executed statement left it.
  - The dispatch loop breaks BEFORE advancing, so the halted frame is still at the pre-advance position.
- **Interaction with the frame chain.** In a nested-frame program, which frame is halted? The one currently dispatching? Its parent? All of them? Spec needs to be clear.
- **Return-to-caller contract.** `engine:run()` returns a result table with `stopped = 1`. What other fields? `cap_pk` is there today; anything else host code needs (e.g., which frame halted, the halt reason)?
- **Resume.** Does `%process.stop` support a subsequent `engine:run()` that picks up where it left off? Or is halt terminal for the run() call? The pause-resume design at [production/requirements/cvm/sqlite/pause-resume](https://puck.uno/production/requirements/cvm/sqlite/pause-resume) presumably has some overlap here.
- **Compared to other halts.** Distinct from `.destroy` on the process cap (which reaps everything), distinct from a raised uncaught exception (which propagates), distinct from normal completion. When to reach for which.
- **Testing use case.** The x-equals-1 doc's pattern — halt to inspect the mid-run state — is the primary user of this today. Spec should name it.

## What the sprint does NOT touch

- **The handler implementation itself.** Already works; spec first, adjust code later if the spec calls for something different.
- **Resume across process boundaries.** Cross-machine resume, checkpoint/restore, sending the DB to another engine — those are pause-resume territory, not %process.stop's job.
- **Any other `%process.*` methods.** Scope is `.stop` only.

## Related

- [production/src/engine/handlers/process-stop.lua](https://puck.uno/production/src/engine/handlers/process-stop.lua) — the implementation.
- [production/requirements/cvm/sqlite/x-equals-1](https://puck.uno/production/requirements/cvm/sqlite/x-equals-1) — current usage example.
- [production/requirements/cvm/sqlite/pause-resume](https://puck.uno/production/requirements/cvm/sqlite/pause-resume) — the broader pause-and-resume design; likely overlap on state-preservation semantics.
- [production/requirements/global-methods/](https://puck.uno/production/requirements/global-methods/) — where the final spec doc for `%process.stop` will probably live (or a sibling if `%process` gets its own section).
