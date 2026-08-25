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

All the restart-specific work lives inside `restart()` — nothing added to `run_frame`. A normal (non-restart) dispatch pays no per-call tax; production's walker stays as-is.

### walk the frame chain

Start at the process cap. Walk `frame_parent` down to the frame that has no children — the leaf. That's where the process was paused. If the walk never moves off the cap, the process is already complete; raise.

### optional: setting the return value

If the caller passed a value into `restart(value)`, materialize it as a scalar and set the leaf frame's rv to it (three writes — scalar, bucket, rv ref — wrapped in a savepoint so a partial injection can't leave the halt state inconsistent).

### reap the leaf, then advance the parent

Delete the leaf frame. Two triggers fire on the leaf's parent: `frames_child_delete_propagates_rv` lifts the leaf's rv (whatever it holds — the injected value, or null) into the parent's rv slot, and `frames_child_delete_sets_parent_gc` sets the parent's `frame_gc = 1`.

Drain needs_trace (the reap's cascade populated it; the next step's auto-null-gc trigger won't reset gc while marks are outstanding).

Advance the parent past the halted statement. The parent's stmt_idx is still pointing at whatever caused the halt; without this step the walker would immediately re-dispatch and re-halt.

### run the parent

Call `Engine.run_frame` on the parent. Production's walker takes over from there — dispatches remaining statements, reaps at frame end, propagate-rv unwinds one level up (parent's parent), and so on until the cap.

Wrap the run_frame call in xpcall + halt-catch; a subsequent `%process.stop` inside the resumed program halts the same way.

## Related

- [sprints/stop/index.md](./) — sprint index; the informal design walk.
- [sprints/stop/src/stop_larry.lua](./src/stop_larry.lua) — `restart()` implementation.
- [sprints/stop/src/process_stop.lua](./src/process_stop.lua) — handler that inserts the stop frame + raises HALT.
- [production/src/engine/cvm/sqlite/frame-lifecycle](https://puck.uno/production/requirements/cvm/sqlite/frame-lifecycle) — the frame state machine + rv slot mechanics.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `frames_child_delete_propagates_rv`, `frames_child_delete_sets_parent_gc`, `frames_advance_requires_gc`, `frames_gc_reset_requires_empty_needs_trace`.
