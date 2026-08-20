# Set up frame 0

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage_set_up_frame_0",
	"role": "canonical spec for the second and final sub-step of Stage — inserting frame 0 as an objects row with primitive='f' and the CaspM in its ast column, so the current process has a stack of one frame ready to walk when execution begins. Under frames-as-objects this single INSERT covers both 'install the CaspM' and 'push the frame' — those two acts are the same row.",
	"status": "V1 spec"
}}
~~~

The second and final sub-step of [Stage](https://www.puck.uno/requirements/bootstrap/stage/). After [Transpile](https://www.puck.uno/requirements/bootstrap/stage/transpile/) has produced the CaspM, this sub-step lands frame 0 — an `objects` row with `primitive = 'f'` (the frame primitive) and the CaspM in its `ast` column. One INSERT writes both.

## The insert

~~~sql
insert into objects (primitive, ast, process, stmt_idx, owner_role)
values ('f', <caspm_json>, <bootstrap_process_pk>, 0, <user_pk>);
~~~

Column by column:

- `primitive = 'f'` — this row is a frame. The `ast` column is biconditional with this primitive; every frame row carries the code it's executing.
- `ast` — the CaspM tree produced by Transpile, serialized as JSON text (see [ast-storage](https://www.puck.uno/requirements/cvm/sqlite/ast-storage)).
- `process` — the fresh process's pk, created by this sub-step (see [Fresh vs revival](#fresh-vs-revival) below). Only frame 0 binds to `processes` via this column; sub-frames (frames 1, 2, ...) chain via `parent_frame` and leave `process` null. Under the fan-in-friendly design, this leaves the door open for multiple processes to share the tail of a call chain.
- `stmt_idx = 0` — dispatch position within `ast`. Frame 0 is about to execute the first top-level statement.
- `owner_role` — the user seed's pk. Frame 0 runs as the user role.

## Fresh vs revival

Two entry paths land in this sub-step:

- **Fresh run.** No process yet exists. Set up frame 0 creates one (via `initialize_process`) and then inserts frame 0 as above. Both writes wrap in a savepoint so a mid-flight crash can't leave a process row with no frame.
- **Revival run.** The caller already has a process pk (from a paused earlier session, from a coordinator, from a revive-a-specific-process signal). Set up frame 0 finds the process's deepest live frame instead of creating a new one — the walk starts at frame 0 (the one with `process` set) and follows `parent_frame`-inverse links down to the deepest.

The engine reads `engine.process_pk` to distinguish: nil means fresh, non-nil means revival. Same sub-step, two branches.

## This is where transpilation happens

The Caspian source → CaspM conversion is architecturally attached to **this exact sub-step** — the moment the engine reads the CaspM value that becomes frame 0's `ast`. The [Transpile](https://puck.uno/requirements/bootstrap/stage/transpile/) sub-step describes the logical transformation (source in, CaspM out); this sub-step is where it physically fires in the engine's execution.

Concretely: the engine reads `engine.caspm` here. Whatever populates that slot — eager transpile at `engine:load()`, JIT transpile at the moment of this read, a caller who handed in ready CaspM directly — must have run by the time execution reaches this point. Anything earlier is speculative; anything later is too late.

The transpiler that runs is the one in the engine's `transpiler` slot — a pluggable seam so alternate Caspian syntaxes (Python-shaped, Lisp-shaped, whatever) can substitute their own frontend. All such frontends converge on this single point: one code location the engine consults to get CaspM, regardless of which frontend produced it.

When this sub-step's implementation lands, its function-level docstring carries a markdown comment at the exact line where the CaspM is consumed, restating this rule.

## No bucket, no locals — yet

The frame's bucket, and any locals hash inside it, are created lazily on first write. A program that never touches a local variable never triggers those inserts.

## No caller — this is the root

Frame 0 has no caller in the call stack. The mechanism that will eventually point child frames back at their pusher (a frame-caller pointer, or an equivalent capture link for closures) is deferred to the closure-design slice — see [CVM § Deferred: closure capture reconciliation](https://www.puck.uno/requirements/cvm/sqlite/#deferred-closure-capture-reconciliation) for the open questions this connects to.

## What's next

After this sub-step returns, the CVM holds:

- The seeded runtime state store (Initialize VM's output).
- Frame 0 with the loaded program in its `ast`.

Bootstrap is done. The next step is execution: the engine walks frame 0's `ast`, dispatches its first statement, and continues from there.
