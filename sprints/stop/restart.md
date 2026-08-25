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
%process.stop
~~~

Same source, but `restart('hello')` injects a string on the way in. Cap ends up terminal with `rv = scalar_string 'hello'`.

The mechanism is the same either way; only step 3 (value injection) differs.

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

Three frames stacked. `frame_0` is at `stmt_idx=0` (paused mid-dispatch of `%process.stop`). `stop_frame` is terminal-at-birth (empty ast, stmt_idx=0). `frame_gc` is null on every frame.

## restart() — the seven steps

### 1. Walk cap → leaf frame

The engine already has the process cap's pk (from `run()`'s earlier return). It traces from the cap down the `frame_parent` chain to the leaf — the frame at the bottom, where the process was paused. The chain is linear (schema's unique constraint on `frame_parent` allows at most one child per frame), so a plain loop suffices:

~~~lua
local leaf_pk = cap_pk
while true do
    local next_pk = <select object_pk from objects where frame_parent = leaf_pk>
    if not next_pk then break end
    leaf_pk = next_pk
end
~~~

If the walk never moves (cap has no children), the process is already complete — raise `stop_larry_restart_process_complete`.

Under the current design the leaf frame is always the stop frame (only `%process.stop` halts a process), but the walk doesn't assume that — any leaf frame is a valid restart anchor.

### 2. Look up parent + owner_role

~~~sql
select frame_parent, owner_role from objects where object_pk = <leaf_pk>
~~~

`frame_parent` is `frame_0`'s pk (the frame that called `%process.stop`). `owner_role` is inherited from `frame_0`, which inherited from `cap`, which inherited from user. Used for materializing the injected scalar (if any).

### 3. Optional value injection

Skipped when `value` is nil.

Otherwise, three writes — wrapped in a **savepoint** so they land atomically or roll back together. A partial injection (e.g., the scalar and bucket land but the rv ref fails) would leave the halt state inconsistent, so all-or-nothing is the rule:

~~~lua
db:exec('savepoint restart_inject_rv;')
local ok, err = pcall(function()
    scalar_pk = data:add_scalar(value, owner_role)  -- polymorphic: string/number/bool/nil
    bucket_pk = data:add_bucket(leaf_pk)             -- materializes stop frame's bucket
    data:upsert_ref(bucket_pk, 'rv', scalar_pk)     -- rv ref inside the bucket
end)
if not ok then
    db:exec('rollback to savepoint restart_inject_rv;')
    db:exec('release savepoint restart_inject_rv;')
    error(err, 0)
end
db:exec('release savepoint restart_inject_rv;')
~~~

The pcall re-raises anything it caught after cleaning up the savepoint — per the sprint's error-propagation discipline.

After these writes:

~~~text
objects: (same three frames as before, plus:)
  scalar    (base='o' scalar_string='hello')
  stop_bucket  (base='h')

refs:
  stop_frame → stop_bucket  key='b'
  stop_bucket → scalar      key='rv'
~~~

The scalar carries the value. The stop frame's rv slot is now populated.

### 4. Restart the process

The restart itself IS a single write — a DELETE against the leaf frame:

~~~sql
delete from objects where object_pk = <leaf_pk>
~~~

Everything meaningful about restart happens as a side effect of this delete. The leaf's rv (if any) propagates up to the parent, the parent's frame_gc flips to 1, and the process is one step away from resuming its dispatch loop. The remaining sections (drain, advance, re-enter walker) are the mechanical follow-through that makes the walker actually pick up where it left off, but the moment of restart — the point at which the halted process becomes an unhalted one — is this DELETE.

Two triggers fire on the parent (`frame_0`) BEFORE the row actually goes:

**`frames_child_delete_propagates_rv`** (BEFORE) — reads the stop frame's outgoing refs to find its bucket → rv, then writes to the parent's bucket → rv. If the parent had no bucket, materializes one first. Under value-injected restart, `frame_0` didn't have a bucket; the trigger creates it, links it via `key='b'`, and inserts the `rv` ref pointing at the same scalar the stop frame's rv pointed at.

**`frames_child_delete_sets_parent_gc`** (AFTER) — sets `frame_0.frame_gc = 1`. Cap-exempt guard applies but not triggered here since `frame_0` isn't a cap.

Then the DELETE proceeds. Stop frame's outgoing refs cascade (`refs.parent = leaf_pk` ON DELETE CASCADE): the `key='b'` ref to stop_bucket is dropped. Cascade fires `refs_mark_needs_trace_after_delete`, marking `stop_bucket` in `needs_trace`.

After step 4:

~~~text
objects: (stop_frame gone; new items:)
  scalar       (base='o' scalar_string='hello' — one incoming ref from frame_0_bucket)
  stop_bucket  (marked in needs_trace)
  frame_0_bucket  (base='h', materialized by propagate-rv)

refs:
  stop_bucket → scalar         key='rv'   (still there; parent stop_bucket not deleted)
  frame_0 → frame_0_bucket     key='b'    (created by propagate-rv 1a+1b)
  frame_0_bucket → scalar      key='rv'   (created by propagate-rv 2)

frame_0: stmt_idx=0, gc=1
~~~

### 5. Drain needs_trace

~~~lua
data:drain_needs_trace(cap_pk)
~~~

Must happen BEFORE the advance. The advance's AFTER trigger `frames_advance_sets_gc_null` refuses to reset gc while needs_trace has entries (per `frames_gc_reset_requires_empty_needs_trace`). Drain first.

Under the drain:

- `stop_bucket` in needs_trace. No incoming refs → reap. Outgoing `rv` ref cascades → drop `stop_bucket → scalar`. Mark trigger fires on `scalar`.
- `scalar` marked. One incoming ref remaining (from `frame_0_bucket → scalar`). Reachable → unmark, don't reap.

After the drain:

~~~text
objects: (stop_bucket also gone; scalar survives)
  scalar         (base='o' scalar_string='hello')
  frame_0_bucket (base='h')

refs:
  frame_0 → frame_0_bucket     key='b'
  frame_0_bucket → scalar      key='rv'

frame_0: stmt_idx=0, gc=1  (unchanged — drain doesn't touch frames)
needs_trace: empty
~~~

### 6. Advance parent

~~~lua
current_idx = <frame_0.frame_stmt_idx>       -- reads 0
stmts.advance:bind_values(current_idx + 1, parent_pk)
stmts.advance:step()
~~~

The advance is a bare `UPDATE frame SET frame_stmt_idx = 1 WHERE object_pk = frame_0`.

- BEFORE trigger `frames_advance_requires_gc` checks `old.frame_gc = 1`. Passes.
- The UPDATE fires. `stmt_idx` becomes 1.
- AFTER trigger `frames_advance_sets_gc_null` runs. Sets `gc = null`. Checks `frames_gc_reset_requires_empty_needs_trace` — passes (we drained in step 5).

After step 6:

~~~text
frame_0: stmt_idx=1, gc=null   (past the %process.stop statement, ready-to-advance-again if the loop continues)
~~~

### 7. Re-enter the walker

~~~lua
xpcall(function() self:run_frame(parent_pk) end, ...)
~~~

`run_frame(frame_0_pk)`:

- Reads `frame_0.frame_ast` (one statement — the `%process.stop`).
- Loops: `idx = get_stmt_idx()` returns 1. Check `idx >= #frame_ast` → `1 >= 1` → true, break.
- No dispatch happens (we're already past all statements).
- Reap `frame_0`.

The reap of `frame_0` fires the same two triggers:

- `propagate-rv` writes `frame_0.bucket.rv` up to `cap.bucket.rv`. Under value-injected restart, `frame_0` has an rv (the scalar); cap has no bucket. Trigger materializes `cap_bucket`, links via `key='b'`, inserts the rv ref pointing at the same scalar.
- `sets_parent_gc` on the cap — cap-exempt guard fires. Cap.gc stays null.

Then cascade: `frame_0`'s outgoing `key='b'` ref cascades. Mark trigger marks `frame_0_bucket` in needs_trace.

Tail drain (built into run_frame's exit):

- `frame_0_bucket` no incoming refs → reap. Outgoing `rv` cascades → drop `frame_0_bucket → scalar`. Mark scalar.
- Scalar has ONE remaining incoming ref: `cap_bucket → scalar` (created by propagate-rv). Reachable → unmark, don't reap.

Final state:

~~~text
objects:
  <role rows>
  cap        (base='o' control='f' frame_process_cap=1 frame_ast='[]' frame_stmt_idx=0 frame_gc=null)
  cap_bucket (base='h')
  scalar     (base='o' scalar_string='hello')

refs:
  cap → cap_bucket        key='b'
  cap_bucket → scalar     key='rv'

needs_trace: empty
~~~

Cap is at born-terminal, no children — the "program done" state. Its rv holds the value the host injected (or nothing under bare restart, in which case `cap_bucket` was never materialized because `propagate-rv` skips materialization when the child has no rv).

`restart()` returns `{complete = 1, cap_pk = <cap_pk>}`.

## What bare restart does differently

Skip step 3. Everything else is the same, except:

- The stop frame has no bucket (nothing was materialized on it).
- In step 4, `propagate-rv` statement 1a's `where exists (... child has rv ...)` guard fails — the stop frame has no rv-carrying bucket. So statement 1a doesn't materialize `frame_0`'s bucket. Statements 1b and 2 also skip (nothing to insert). Statement 3 fires if parent had a rv (deletes it), but parent has no bucket either — no-op.
- Frame_0.gc still gets set to 1 by `sets_parent_gc`.
- After drain + advance, run_frame reaps frame_0. Same propagate-rv skips again (frame_0 has no rv → skip materialize on cap). Cap ends terminal with no bucket, no rv.
- `restart()` returns `{complete = 1, cap_pk = <cap_pk>}` — same shape, cap just has no rv.

## What a restart-into-another-halt looks like

Program: `%process.stop; %process.stop`.

- `run()` halts at the first stop.
- `restart()` reaps stop_frame_1, drains, advances frame_0 to stmt_idx=1.
- run_frame(frame_0): loops, dispatches statement at idx=1 (the second `%process.stop`). Handler inserts stop_frame_2, raises HALT.
- Halt unwinds through `run_frame` → `restart()`'s xpcall catches → returns `{stopped=1, cap_pk=...}`.

The host can call `restart()` again to keep going. Halt-and-restart is idempotent — each halt leaves a fresh stop frame at the bottom; each restart reaps it and continues.

## Related

- [sprints/stop/index.md](./) — sprint index; the informal design walk.
- [sprints/stop/src/stop_larry.lua](./src/stop_larry.lua) — `restart()` implementation.
- [sprints/stop/src/process_stop.lua](./src/process_stop.lua) — handler that inserts the stop frame + raises HALT.
- [production/src/engine/cvm/sqlite/frame-lifecycle](https://puck.uno/production/requirements/cvm/sqlite/frame-lifecycle) — the frame state machine + rv slot mechanics.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `frames_child_delete_propagates_rv`, `frames_child_delete_sets_parent_gc`, `frames_advance_requires_gc`, `frames_gc_reset_requires_empty_needs_trace`.
