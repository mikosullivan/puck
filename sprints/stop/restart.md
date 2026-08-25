~~~vibecode
{"doc": "sprint-stop-restart", "sprint": "stop",
	"role": "Step-by-step walkthrough of what happens when a halted or crashed process restarts. Traces the DB state at each phase: paused-frame state, restart() call, the reap of any child frame(s), the propagate-rv trigger firing, the parent's advance, and re-entry into the walker. Restart is a general resume mechanism — it works on any process that left its call stack in a valid paused state, whether via %process.stop or an unclean shutdown (crash, pulled plug). The algorithm operates on the graph structure (cap → frame_parent chain, frame_gc flags) — never on `engine_class = 'stop'` markers, because a crash leaves no explicit stop frame."}
~~~

# Restart walkthrough

What actually happens under `StopLarry:run(restart_value?)` when it's called a second time on an already-halted process. (`run` is the single entry point — first call starts the process, subsequent calls continue it; passing `restart_value` on a continuation call injects a reply for the `%process.stop` that halted it.)

## Restart is not just for `%process.stop`

The restart machinery is a **general resume mechanism** for any process whose call stack was left in a valid paused state. Two ways a process gets there:

- **Intentional halt.** `%process.stop` dispatches, inserts a stop frame under the current frame, raises HALT. The Lua exception unwinds cleanly. Result: cap + frame chain + a leaf stop frame, all frames at whatever stmt_idx they were at, `frame_gc = null` on every frame.
- **Unclean shutdown.** The process was mid-flight and something outside the runtime killed it — power loss, host `kill -9`, the process holding the SQLite handle got OOM'd, the container was evicted. The database file (or in-memory DB, if it was flushed to a snapshot) is left exactly as the last completed SQLite transaction left it. Every write inside the walker is transactional; the schema's constraints and triggers make sure that snapshot is a **valid paused state** — no frame is stuck partway between run-statement and run-gc without `frame_gc` reflecting it, no ref points at a non-existent object, no reachable graph is corrupt. A halt-chain that lands from a crash looks the same to `restart_frame` as one that lands from `%process.stop`: cap → some frames → a leaf that isn't done. No stop frame anywhere.

**The database is always in a valid state.** That's the invariant the schema is designed around and every trigger in `frame-lifecycle` is written to preserve. Restart doesn't need to distinguish "intentional halt" from "crash" because there is no observable difference at the row level.

**This is why `restart_frame` operates on the graph, not on markers.** The algorithm asks:

- Does this frame have a child? (query `frame_parent`)
- Is this frame in gc state? (query `frame_gc`)

Never:

- Is this frame a stop frame? (query `engine_class = 'stop'`)

A crash-restart won't find any `engine_class = 'stop'` because the crash killed the process before `%process.stop` ran. But cap → frame chain is still there, frame_gc is still null (because the crash was atomic from SQLite's POV — either the whole transaction committed or none of it did), and the recursion + gc-check + delegate cycle unwinds it exactly the same way. Restart doesn't care why the pause happened.

## Two example programs

Bare and value-carrying:

~~~caspian
%process.stop
~~~

Halt state, then plain restart, then the process completes. Cap ends up terminal with no rv.

Or:

~~~caspian
$response = %process.stop
~~~

## State at halt

Whether the process was intentionally halted via `%process.stop` or killed mid-flight by an unclean shutdown, the DB state that `restart()` operates on has the same shape: cap + frame chain + (in the `%process.stop` case) a stop frame at the leaf.

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

The rest of the work happens inside `restart_frame`, a method parallel to `run_frame`. `restart_frame` doesn't duplicate the ast-walk + reap logic in `run_frame`; it delegates to `run_frame` for that. What it adds is two independent pre-steps — descend into any child, and if the frame is in gc state run gc + advance — then hand off.

The algorithm:

~~~text
restart_frame(frame_pk):
    child_pk = find_child(frame_pk)

    if child_pk:
        restart_frame(child_pk)      # bottom-up recursion
    end

    if gc:
        run gc                        # child's cascade cleanup, or leaf's mark
        advance stmt_idx              # past the halted stmt; auto-nulls gc
    end

    run_frame(frame_pk)               # gc=null now, hand off to the fresh walker
~~~

`restart()` kicks off the recursion by calling `restart_frame` on the top of the call stack (the cap's only child). Everything below unfolds:

- **Descent.** The recursion drills through any paused sub-frames until it hits a childless one — the bottom of the halt chain.
- **Leaf reap.** The bottom frame — a childless leaf, terminal-at-create under the sprint's halt model — has no child (skip first branch) and no gc (skip second branch), so it delegates straight to `run_frame`. `run_frame` walks the empty ast (immediate break) and reaps. The reap fires the schema's two triggers on the parent: `frames_child_delete_propagates_rv` (parent's rv gets the leaf's rv, whatever was injected or null) and `frames_child_delete_sets_parent_gc` (parent's frame_gc → 1).
- **Parent unwinds.** The recursion returns one level. The parent's `restart_frame` frame is now past its `restart_frame(child_pk)` call. It reads its own gc, finds `= 1` (the reap just set it), runs gc (drains needs_trace — the child's cascade populated it), and advances stmt_idx past the halted statement. Without that advance the next dispatch would re-execute `%process.stop` and re-halt.
- **Delegate.** `run_frame` walks any remaining statements from the newly-advanced position and reaps at frame end. The reap fires the same triggers on the grandparent.
- **Repeat all the way up.** Each enclosing `restart_frame` call finds its gc flipped by the child's reap and repeats the pattern.

**Two independent pre-steps.** The child-check and the gc-check are separate conditions, not linked. A frame at the bottom of the chain (leaf) has no child and no gc — both skipped, straight delegate. A frame in the middle has a child (recurse) and, once the recursion returns, gc (run gc + advance). Splitting them keeps the algorithm honest about what each condition means.

**Why parallel methods, not a modified `run_frame`.** The child-check + gc-check work is only needed on restart. Putting it in `run_frame` would tax every dispatch (every fresh-frame walk pays for two SELECT-and-branch checks that are only relevant to the rare restart path). Splitting into `run_frame` (untouched, no tax) + `restart_frame` (adds the pre-steps, delegates) keeps normal dispatch fast and confines the restart machinery to the restart path.

**No walker duplication.** `restart_frame` doesn't re-implement the ast loop or the reap. Both methods use exactly one implementation of that work — production's `run_frame`.

## Related

- [sprints/stop/index.md](./) — sprint index; the informal design walk.
- [sprints/stop/src/stop_larry.lua](./src/stop_larry.lua) — `restart()` implementation.
- [sprints/stop/src/process_stop.lua](./src/process_stop.lua) — handler that inserts the stop frame + raises HALT.
- [production/src/engine/cvm/sqlite/frame-lifecycle](https://puck.uno/production/requirements/cvm/sqlite/frame-lifecycle) — the frame state machine + rv slot mechanics.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `frames_child_delete_propagates_rv`, `frames_child_delete_sets_parent_gc`, `frames_advance_requires_gc`, `frames_gc_reset_requires_empty_needs_trace`.
