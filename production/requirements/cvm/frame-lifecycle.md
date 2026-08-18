~~~vibecode
{"doc": "requirements_cvm_frame_lifecycle",
	"role": "The lifecycle of a process from seed to terminal. A process is a cap frame (`primitive='f'`, `process=1`, `ast='[]'`) at the top of a call stack; frame 0 sits under the cap as a nested frame. The walker dispatches each frame's statement, then advances stmt_idx. Advancing requires gc=1 to consume and auto-sets gc back to null. When a frame reaches its terminal position it auto-deletes; the cap is excluded and stays alive as the terminal signal.",
	"key_concepts": ["cap_as_frame", "gc_ready_to_advance", "auto_delete_at_terminal", "rule_3_child_delete_cascade", "resume_safety"]}
~~~

# Frame lifecycle

Step-by-step CVM state through the lifecycle of a process. Uses the assignment `$x = 1` as the driving example — one statement, one dispatch, one cycle. A longer program adds more advance cycles but no shape changes.

Every state below is a valid resume state. If the database crashes at any moment (and it's persistent), the process can be resumed cleanly.

## The concept: cap-as-frame

A process is not a separate table row — a process is a **cap frame**: an `objects` row with `primitive = 'f'`, `process_cap = 1`, `ast = '[]'`, and no parent. The cap's `object_pk` IS the process identity.

Frame 0 — the top of the user's call stack — sits directly under the cap as a nested frame (`parent_frame = cap_pk`, `process = null`). Sub-frames chain further down from frame 0 via `parent_frame`.

The cap participates in the same lifecycle machinery as any frame — same `stmt_idx` field, same `gc` state, same advance rules. Its ast is empty (`'[]'`) so it has no statements to dispatch; it's the terminal-alive anchor that lets the walker cascade cleanup uniformly.

**Why a cap.** A process needs a top-of-stack anchor so the walker can cascade-signal up from frame 0 with the same trigger machinery it uses everywhere else. Rather than special-case "sweep frame 0" logic, the cap gives frame 0 a parent that participates in the same lifecycle.

## What gc means

The `gc` column is a two-state flag on each frame:

- **`gc = null`** — ready to dispatch the command at `stmt_idx`.
- **`gc = 1`** — ready to advance to the next `stmt_idx`.

A frame born fresh is `(stmt_idx = 0, gc = null)`. Between commands, the frame moves from ready-to-dispatch through some in-flight state (dispatch spawns a child, or the leaf command sets `gc = 1` directly), and eventually reaches ready-to-advance. The walker then advances, taking `stmt_idx` up by one and `gc` back to null — ready for the next command.

## The rules

The state machine is enforced by nine rules (all triggers or CHECKs on `objects`; names below match the trigger names in `src/engine/cvm/schema.sql`):

1. **In-progress = has child OR gc=1.** A frame with no children AND gc=null is at rest — walker's next action is to dispatch the command at stmt_idx.
2. **INSERT never sets gc=1** (`frames_gc_starts_null`). Fresh frames are born at gc=null.
3. **Child delete auto-sets parent's gc=1** (`frames_child_delete_sets_parent_gc`). When a child frame is deleted, the parent's gc is set to 1 as a side effect — the signal that the parent's dispatch is done.
4. **gc cannot change while there is a child** (`frames_gc_change_requires_no_child`). Bidirectional. At most one child per frame (`objects_one_child_per_frame` unique index).
5. **Advancing stmt_idx requires gc=1** (`frames_advance_requires_gc`). Only accepted when `old.gc = 1`.
6. **Advancing stmt_idx auto-sets gc to null** (`frames_advance_sets_gc_null` + `frames_advance_rejects_non_null_gc`). The caller writes just `SET stmt_idx = stmt_idx + 1` — the AFTER trigger sets gc back to null. Explicit `gc = null` in the SET is redundant but accepted; explicit `gc = 1` is rejected loudly (engine-bug catch).
7. **Cannot set gc=1 in the terminal state** (`frames_gc_set_rejects_at_terminal`). Terminal frames stay terminal; a done frame can't be reactivated.
8. **Terminal is an at-rest state.** A non-cap frame that reaches its terminal position stays there — no auto-delete. The engine reaps the frame explicitly (see `run_frame` in engine.lua) after its ast is exhausted. Reaping triggers rule 3 on the parent (cap-exempt); the parent's walker continues from there. Caps are process anchors and never advance; they sit at their birth position for the process's lifetime.
9. **Frame cannot be deleted while it has a child** (`frames_delete_requires_no_child`). Backed by the parent_frame FK; specific error id.

Plus `frames_no_child_under_terminal_parent` — reject inserting a child under a terminal parent.

## The canonical cycle

For a non-leaf command (one that spawns a nested frame):

~~~text
executing         →   ready to advance   →   executing (next stmt)
(stmt_idx = N,        (stmt_idx = N,          (stmt_idx = N+1,
 gc = null,            gc = 1,                 gc = null,
 has children)         no children)            has/hasn't children)

    ↑                     ↑                        ↑
    ┃                     ┃                        ┃
    ┃  dispatch spawns    ┃  last child            ┃  UPDATE frame
    ┃  a child frame;     ┃  deleted → rule 3      ┃    SET stmt_idx
    ┃  rule 4 pins gc     ┃  fires → parent's      ┃    += 1
    ┃  = null while       ┃  gc auto-sets to 1     ┃  (auto-set
    ┃  the child exists   ┃                        ┃   nulls gc)
~~~

For a leaf command (one that spawns nothing — e.g., `$x = 1`), the dispatcher can skip the child dance entirely: do the work, then `UPDATE frame SET gc = 1`. No marker frame needed. The walker then advances.

## Terminal state

A frame is in **terminal state** when `stmt_idx >= json_array_length(ast)`. The column CHECK on `stmt_idx` bounds it at `<= json_array_length(ast)`. Empty ast means terminal at `stmt_idx = 0` — the frame is born terminal.

When a non-cap frame reaches terminal, it stays there until the engine reaps it (typically at the tail of `run_frame`). Reaping fires rule 3 on the parent → parent's gc goes to 1 → parent's walker continues. If the parent's advance also lands it at terminal, the parent is reaped in turn.

The **cap** is born terminal (empty ast, stmt_idx = 0) and stays there for the process's lifetime — cap-exempt from the child-delete cascade, so a non-cap child's reap doesn't touch the cap's gc. The cap's row is the "program is done" signal.

## Step-by-step example: `$x = 1`

Each state below is at-rest — a valid state to persist to disk.

### After frame 0 is loaded

Cap seeded, frame 0 seeded under it. Nothing has run yet.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>core_role</th><th>owner_role</th><th>ast</th><th>stmt_idx</th><th>parent_frame</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>eae0b9fb-…</code></td><td><code>r</code></td><td><code>u</code></td><td><code>eae0b9fb-…</code></td><td>null</td><td>null</td><td>null</td><td class="col-comment">user role</td></tr>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td><code>eae0b9fb-…</code></td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td class="col-comment">cap — <code>process = 1</code>, process root</td></tr>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td><code>eae0b9fb-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td><code>0c72f81a-…</code></td><td class="col-comment">frame 0 — under the cap</td></tr>
</tbody>
</table>

### After frame 0's statement dispatches

The handler for `{in='as'}` ran `frame:set_local_to_scalar('x', 'n', 1)` in a single savepoint: materialize the scalar, ensure the bucket → scopes → scopes[0] chain, bind `x`, then `UPDATE frame SET gc = 1`. Frame 0 is now at `(stmt_idx=0, gc=1, no children)` — ready to advance. See [scopes](./scopes) for the bucket/scopes chain shape.

### After frame 0's advance

Walker's advance on frame 0: `UPDATE frame SET stmt_idx = 1`. The auto-set trigger fires, taking gc to null. Frame 0 is now at `(stmt_idx=1, gc=null, no children)` — its terminal position, but still alive.

### After the engine reaps frame 0

`run_frame` finishes its loop and issues `DELETE FROM objects WHERE object_pk = <frame 0>`. That delete fires rule 3 on the parent — the cap — but the cap is exempt from the cascade, so cap.gc stays null. Cap is now at `(stmt_idx=0, gc=null, no children)` — the "program is done" state.

**This is the "program is done" state.** The cap itself still sits — no `complete` flag anywhere, because "cap at its birth position with no children" IS the completion signal.

### After the engine reaps the cap

At the caller's discretion, the engine can DELETE the cap (rule 9 permits — no children). That delete cascades the cap's outgoing refs; the standard mark trigger inserts each ex-child into the `needs_trace` table (scoped to the current process); the trace routine walks reachability and sweeps orphans until the queue is dry. DB back to just the seed rows.

## Resume safety

Every state above is a valid state to crash-and-resume from. The walker's per-statement work is a small number of atomic UPDATEs, and every intermediate state at rest is legal per the nine rules. There is no in-memory bookkeeping the engine needs to reconstruct; every fact about a frame's progress lives on its `stmt_idx` and `gc` columns.

Frame 0 as a nested frame (not a special row) means resume machinery treats it exactly like any other frame — no special "frame 0 handling" branch in the walker.
