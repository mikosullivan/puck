~~~vibecode
{"doc": "requirements_cvm_frame_lifecycle",
	"role": "The lifecycle of a process from seed to terminal. A process is a cap frame (`primitive='f'`, `process=1`, `ast='[]'`) at the top of a call stack; frame 0 sits under the cap as a nested frame. The walker advances each frame's stmt_idx through its ast; every advance couples with `gc = 1` and cascade-sweeps children in one UPDATE. The process reaches terminal state when the cap hits `stmt_idx = 1, gc = null, no children`. Every state along the way is a valid resume state.",
	"key_concepts": ["cap_as_frame", "advance_with_gc", "cascade_cleanup", "terminal_state", "resume_safety"]}
~~~

# Frame lifecycle

Step-by-step CVM state through the lifecycle of a process. Uses the assignment `$x = 1` as the driving example — one statement, one dispatch, one cycle. A longer program adds more advance cycles but no shape changes.

Every state below is a valid resume state. If the database crashes at any moment (and it's persistent), the process can be resumed cleanly.

## The concept: cap-as-frame

A process is not a separate table row — a process is a **cap frame**: an `objects` row with `primitive = 'f'`, `process = 1`, `ast = '[]'`, and no parent. The cap's `object_pk` IS the process identity.

Frame 0 — the top of the user's call stack — sits directly under the cap as a nested frame (`parent_frame = cap_pk`, `process = null`). Sub-frames chain further down from frame 0 via `parent_frame`.

The cap participates in the same lifecycle machinery as any frame — same `stmt_idx` field, same `gc` state, same advance rules, same terminal check. Its ast is empty (`'[]'`) so its `stmt_idx = 0 → 1` transition doesn't dispatch anything; it's the mechanism the walker uses to sweep frame 0 when the program is done.

**Why a cap.** A process needs a top-of-stack anchor so the walker can cascade-clean frame 0 with the same trigger machinery it uses everywhere else. Rather than special-case "sweep frame 0" logic, the cap gives frame 0 a parent whose advance-with-gc cascade handles it uniformly.

## The mechanism: advance-with-gc

The walker's per-statement operation on a frame is **one UPDATE that increments `stmt_idx` and sets `gc = 1` together**:

~~~sql
update objects set stmt_idx = stmt_idx + 1, gc = 1
where object_pk = <frame_pk>;
~~~

The AFTER-UPDATE trigger on `gc` cascade-deletes child frames (including any marker the just-completed dispatch pushed). The engine then resets `gc = null` once no children remain.

Four invariants guard the cycle (all enforced by triggers on `objects`):

1. **`frames_advance_requires_gc`** — advancing `stmt_idx` requires `gc = 1` in the same UPDATE.
2. **`frames_gc_set_deletes_children`** — the AFTER-UPDATE cascade sweeps child frames.
3. **`frames_child_delete_requires_parent_gc`** — a child frame can only be deleted when its parent's `gc = 1` (i.e., only via the cascade, not by direct DELETE).
4. **`frames_gc_reset_requires_no_children`** — resetting `gc = null` requires no child frames.

Plus the delete rule: **`frames_delete_requires_gc_null`** — a frame can only be deleted when its own `gc is null` (mid-cleanup deletes rejected). Any `stmt_idx` is fine — early return via `%call.return` legitimately leaves a frame mid-ast with `gc = null`.

## Terminal state

A frame is in terminal state when `stmt_idx > max valid ast index AND gc is null AND no children`. Once terminal, the frame's `object_pk` is a safe delete candidate — it has completed its execution and its cleanup cycle.

For the cap specifically, `ast = '[]'` means max valid idx is -1. The cap is born past-max at `stmt_idx = 0`, but stays alive because nothing cascades into deleting it. The cap advancing to `stmt_idx = 1` (with `gc = 1`) is the mechanism that sweeps frame 0; when the cap's `gc` resets to `null`, the cap itself is terminal. That's the "program is done" signal.

## Step-by-step example: `$x = 1`

Each state below is at-rest — a valid state to persist to disk.

### After frame 0 is loaded

Cap seeded, frame 0 seeded under it. Nothing has run yet.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>user</th><th>owner_role</th><th>ast</th><th>stmt_idx</th><th>parent_frame</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>01111111-…</code></td><td><code>h</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td class="col-comment">cap — <code>process = 1</code>, process root</td></tr>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td><code>01111111-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td><code>0c72f81a-…</code></td><td class="col-comment">frame 0 — under the cap</td></tr>
</tbody>
</table>

### After frame 0's statement dispatches

The handler for `{in='as'}` ran `frame:set_local_to_scalar('x', 'n', 1)` in a single savepoint: materialize the scalar, ensure the bucket → scopes → scopes[0] chain, bind `x`, push a marker child. The marker signals "handler done; walker may advance."

Frame 0's `stmt_idx` still `0` (the walker hasn't advanced yet). See [scopes](./scopes) for the bucket/scopes chain shape.

### After frame 0's advance

Walker's advance on frame 0: `stmt_idx = 1, gc = 1`. Cascade sweeps the marker (marker's `gc` is null; frame 0's is 1; both delete rules pass). Engine resets frame 0's `gc = null`. Frame 0 is now terminal (past max ast idx, `gc = null`, no children).

### After the cap's advance

Walker's advance on the cap: `stmt_idx = 1, gc = 1`. Cascade sweeps frame 0 (frame 0's `gc` is null; cap's is 1). Frame 0's outgoing refs cascade too — the owner→bucket ref fires the standard mark trigger, leaving the bucket `needs_trace = 1`. Engine resets cap's `gc = null`. Cap is now at `stmt_idx = 1, gc = null, no children` — **terminal**.

**This is the "program is done" state.** The cap itself still sits — no `complete` flag anywhere, because terminal shape IS the completion signal. Anything reading process status looks at the cap's row.

### After the engine reaps the cap

Engine marks the cap `needs_trace = 1`. GC traces reachability from roots (roles, persistent objects, other live process caps). Nothing reaches the cap or the orphaned bucket / scopes / scalar. GC sweeps unreachable rows; each deletion cascades outgoing refs, marking their targets `needs_trace = 1`; the loop runs until the queue is dry. DB back to just the seed rows.

## Resume safety

Every state above is a valid state to crash-and-resume from. The walker's operations are per-statement atomic (one UPDATE = advance + cascade), and the shutdown is per-frame atomic (advance + cascade on the cap = the process closes). There is no in-memory bookkeeping the engine needs to reconstruct; every fact about the process's progress lives on the cap and frames' `stmt_idx` and `gc` columns.

Frame 0 as a nested frame (not a special row) means resume machinery treats it exactly like any other frame — no special "frame 0 handling" branch in the walker.
