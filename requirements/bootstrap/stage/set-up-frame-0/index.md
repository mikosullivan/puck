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
insert into objects (primitive, ast, process, idx, stmt_idx, owner_role)
values ('f', <caspm_json>, <bootstrap_process_pk>, 0, 0, <user_pk>);
~~~

Column by column:

- `primitive = 'f'` — this row is a frame. The `ast` column is biconditional with this primitive; every frame row carries the code it's executing.
- `ast` — the CaspM tree produced by Transpile, serialized as JSON text (see [ast-storage](https://www.puck.uno/requirements/cvm/ast-storage)).
- `process` — the bootstrap process's pk. Populated during [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/); held by the engine in Lua-side state.
- `idx = 0` — stack position. This is the outermost frame; the stack starts here.
- `stmt_idx = 0` — dispatch position within `ast`. Frame 0 is about to execute the first top-level statement.
- `owner_role` — the user seed's pk. Frame 0 runs as the user role.

## No bucket, no locals — yet

The frame's bucket, and any locals hash inside it, are created lazily on first write. A program that never touches a local variable never triggers those inserts. See the [first-variable walkthrough](https://www.puck.uno/ideas/frames-as-objects/examples/first-variable/) for what the first `$x = 1` assignment does.

## No caller — this is the root

Frame 0 has no caller in the call stack. The mechanism that will eventually point child frames back at their pusher (a frame-caller pointer, or an equivalent capture link for closures) is deferred to the closure-design slice — see [CVM § Deferred: closure capture reconciliation](https://www.puck.uno/requirements/cvm/#deferred-closure-capture-reconciliation) for the open questions this connects to.

## What's next

After this sub-step returns, the CVM holds:

- The seeded runtime state store (Initialize VM's output).
- Frame 0 with the loaded program in its `ast`.

Bootstrap is done. The next step is execution: the engine walks frame 0's `ast`, dispatches its first statement, and continues from there.
