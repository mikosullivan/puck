# Set up frame 0

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage_set_up_frame_0",
	"role": "canonical spec for the second and final sub-step of Stage — inserting the process cap and frame 0 as objects rows (control='f') with the CaspM in frame 0's frame_ast column, so the current process has a stack of one frame under its cap ready to walk when execution begins. Under frames-as-objects, one INSERT for the cap plus one INSERT for frame 0 covers both 'create the process' and 'install the CaspM and push the frame' — those acts are all row inserts on `objects`.",
	"status": "V1 spec"
}}
~~~

The second and final sub-step of [Stage](https://www.puck.uno/requirements/bootstrap/stage/). After [Transpile](https://www.puck.uno/requirements/bootstrap/stage/transpile/) has produced the CaspM, this sub-step lands the process — a process cap (an `objects` row with `control = 'f'` and `frame_process_cap = 1`) plus frame 0 chained under it (`control = 'f'`, CaspM in its `frame_ast` column, `frame_parent = <cap pk>`). Two INSERTs write both.

## The inserts

~~~sql
-- process cap: the process anchor. No parent, empty frame_ast.
insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role)
values ('o', 'f', 1, '[]', 0, <user_pk>);

-- frame 0: chained under the cap. Carries the loaded CaspM.
insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role)
values ('o', 'f', <caspm_json>, 0, <cap_pk>, <user_pk>);
~~~

Column by column (frame 0):

- `base = 'o'`, `control = 'f'` — this row is a frame. The `frame_ast` column is biconditional with `control = 'f'`; every frame row carries the code it's executing.
- `frame_ast` — the CaspM tree produced by Transpile, serialized as JSON text (see [ast-storage](https://www.puck.uno/requirements/cvm/sqlite/ast-storage)).
- `frame_stmt_idx = 0` — dispatch position within `frame_ast`. Frame 0 is about to execute the first top-level statement.
- `frame_parent = <cap_pk>` — chains frame 0 under the cap. Sub-frames (frames 1, 2, …) later chain from frame 0 via `frame_parent` in the same way.
- `owner_role` — the user seed's pk. Frame 0 runs as the user role.

The cap's `object_pk` IS the process identity — there is no separate `processes` table row. See [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle) for how the cap participates in the walker.

## Fresh vs revival

Two entry paths land in this sub-step:

- **Fresh run.** No process yet exists. Set up frame 0 creates a fresh cap and then inserts frame 0 under it. Both writes wrap in a savepoint so a mid-flight crash can't leave a cap with no frame under it.
- **Revival run.** The caller already has a cap pk (from a paused earlier session, from a coordinator, from a revive-a-specific-process signal). Set up frame 0 finds the process's deepest live frame instead of creating a new one — the walk starts at the cap and follows `frame_parent`-inverse links down to the deepest.

The engine reads `engine.process_pk` to distinguish: nil means fresh, non-nil means revival. Same sub-step, two branches.

## This is where transpilation happens

The Caspian source → CaspM conversion is architecturally attached to **this exact sub-step** — the moment the engine reads the CaspM value that becomes frame 0's `frame_ast`. The [Transpile](https://puck.uno/requirements/bootstrap/stage/transpile/) sub-step describes the logical transformation (source in, CaspM out); this sub-step is where it physically fires in the engine's execution.

Concretely: the engine reads `engine.caspm` here. Whatever populates that slot — eager transpile at `engine:load()`, JIT transpile at the moment of this read, a caller who handed in ready CaspM directly — must have run by the time execution reaches this point. Anything earlier is speculative; anything later is too late.

The transpiler that runs is the one in the engine's `transpiler` slot — a pluggable seam so alternate Caspian syntaxes (Python-shaped, Lisp-shaped, whatever) can substitute their own frontend. All such frontends converge on this single point: one code location the engine consults to get CaspM, regardless of which frontend produced it.

When this sub-step's implementation lands, its function-level docstring carries a markdown comment at the exact line where the CaspM is consumed, restating this rule.

## No bucket, no locals — yet

The frame's bucket, and any locals hash inside it, are created lazily on first write. A program that never touches a local variable never triggers those inserts.

## No caller — this is the root

Frame 0 has no caller in the call stack — the cap above it is a process anchor, not a caller. The mechanism that will eventually point child frames back at their pusher (a frame-caller pointer, or an equivalent capture link for closures) is deferred to the closure-design slice — see [CVM § Deferred: closure capture reconciliation](https://www.puck.uno/requirements/cvm/sqlite/#deferred-closure-capture-reconciliation) for the open questions this connects to.

## What's next

After this sub-step returns, the CVM holds:

- The seeded runtime state store (Initialize VM's output).
- A process cap and frame 0 under it, with the loaded program in frame 0's `frame_ast`.

Bootstrap is done. The next step is execution: the engine walks frame 0's `frame_ast`, dispatches its first statement, and continues from there.
