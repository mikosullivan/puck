~~~vibecode
{"doc": "sprint-stop-restart", "sprint": "stop",
	"role": "Step-by-step walkthrough of what happens when a halted process restarts. Traces the DB state at each phase: halt-time, restart() call, the reap of the stop frame, the propagate-rv trigger firing, the parent's advance, and re-entry into the walker. Two variants: bare restart (no value injected) and restart-with-value (a Lua value materialized as a scalar becomes the stop frame's rv, propagates up to the parent's rv, eventually to the cap)."}
~~~

# Restart walkthrough

What actually happens under `StopLarry:restart(value?)`.

Two programs — bare and value-carrying:

~~~caspian
%process.stop
~~~

Halt state, then plain restart, then the process completes. Cap ends up terminal with no rv.

Or:

~~~caspian
$response = %process.stop
~~~

## State at halt

After `larry:load("%process.stop"); larry:run()` returns `{stopped=1, cap_pk=...}`:

~~~text
objects:
  <role rows: engine, cache, user>            (base='o' control='r')
  cap                                          (base='o' control='f' frame_process_cap=1 frame_ast='[]' frame_stmt_idx=0)
  frame_0                                      (base='o' control='f' frame_parent=cap frame_ast='[[fc, {fn:"stop", rc:{sys:"process"}}]]' frame_stmt_idx=0)
  stop_frame                                   (base='o' control='f' engine_class='stop' frame_parent=frame_0 frame_ast='[]' frame_stmt_idx=0)

refs: (empty — no scopes were built)
~~~

Three frames stacked. `frame_0` is at `stmt_idx=0` (paused mid-dispatch of `%process.stop`). `stop_frame` is terminal-at-create (empty ast, stmt_idx=0). `frame_gc` is null on every frame.

## restart()

### optional: setting the return value

If the caller passed a value into `restart(value)`, walk to the leaf frame and set its rv to a scalar of that value (three writes — scalar, bucket, rv ref — wrapped in a savepoint so a partial injection can't leave the halt state inconsistent).

### restart_frame(top-of-stack)

The rest of the work happens inside `restart_frame`, a method parallel to `run_frame`. `restart_frame` walks the same ast + reap logic as `run_frame` — and it doesn't duplicate that code, it delegates to `run_frame` for it. What it adds is a pre-step: if this frame has a child, `restart_frame` the child first, then drain and advance past the halted statement, THEN delegate to `run_frame`.

`restart()` kicks off the recursion by calling `restart_frame` on the top of the call stack (the cap's only child). Everything below unfolds:

- The recursion drills down through any paused sub-frames.
- The bottom frame — a childless leaf, terminal-at-create under the sprint's halt model — reaches its `run_frame` delegation. `run_frame` walks the empty ast (immediate break) and reaps. The reap fires the schema's two triggers on the parent: `frames_child_delete_propagates_rv` (parent's rv gets the leaf's rv, whatever was injected or null) and `frames_child_delete_sets_parent_gc` (parent.gc → 1).
- The recursion unwinds one level. The parent's `restart_frame` frame drains, advances past the halted statement (necessary — the parent's stmt_idx is still on the `%process.stop`, and if we don't advance we'd re-dispatch and re-halt), then delegates to `run_frame`. `run_frame` walks the remaining statements and reaps at frame end.
- The reap fires the same triggers on the grandparent. And so on up the chain.

**Why parallel methods, not a modified `run_frame`.** The child-check + drain + advance work is only needed on restart. Putting it in `run_frame` would tax every dispatch (every fresh-frame walk pays for a SELECT-and-branch that's only relevant to the rare restart path). Splitting into `run_frame` (untouched, no tax) + `restart_frame` (adds the prelude, delegates) keeps normal dispatch fast and confines the restart machinery to the restart path.

**No walker duplication.** `restart_frame` doesn't re-implement the ast loop or the reap. Both methods use exactly one implementation of that work — production's `run_frame`.

## Related

- [sprints/stop/index.md](./) — sprint index; the informal design walk.
- [sprints/stop/src/stop_larry.lua](./src/stop_larry.lua) — `restart()` implementation.
- [sprints/stop/src/process_stop.lua](./src/process_stop.lua) — handler that inserts the stop frame + raises HALT.
- [production/src/engine/cvm/sqlite/frame-lifecycle](https://puck.uno/production/requirements/cvm/sqlite/frame-lifecycle) — the frame state machine + rv slot mechanics.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `frames_child_delete_propagates_rv`, `frames_child_delete_sets_parent_gc`, `frames_advance_requires_gc`, `frames_gc_reset_requires_empty_needs_trace`.
