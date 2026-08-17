~~~vibecode
{"doc": "sprint-index", "sprint": "stmt-idx-ast-immutability",
	"role": "Redesigns the gc cycle. New semantics for gc: 'ready to advance' rather than 'post-dispatch cleanup.' Advancing stmt_idx now requires gc=1 (was: sets gc=1). Adds auto-delete-at-terminal so a frame reaching its terminal state is removed automatically, which chains through rule 3 (child delete sets parent gc=1) all the way up the stack.",
	"status": "active — rules drafted; sprint schema copied; trigger + test work pending"}
~~~

# stmt-idx-ast-immutability

Sprint to rework the gc cycle. Under the new rules, gc=1 means "ready to advance" rather than "post-dispatch cleanup." The state machine flips direction: advancing stmt_idx now transitions gc from 1 back to null, and the reverse (something else sets gc to 1) is what signals dispatch is done.

## Rules

1. **In-progress = has child OR gc=1.** A frame with no children AND gc=null is at rest — walker's next action is to dispatch the command at stmt_idx.
2. **INSERT never sets gc=1.** Fresh frames are born at gc=null.
3. **Child delete → parent's gc auto-sets to 1.** Any child-frame deletion fires an AFTER-DELETE trigger that flips the parent's gc from null to 1.
4. **gc cannot change while there is a child.** UPDATE OF gc when the frame has a child is rejected. (One child per frame at most — enforced by the existing `objects_one_child_per_frame` unique index.)
5. **Advancing stmt_idx requires gc=1.** The `stmt_idx = stmt_idx + 1` UPDATE is only accepted when `old.gc = 1`.
6. **Advancing stmt_idx sets gc back to null.** Same UPDATE that advances flips gc from 1 → null. (Opposite of the current design, where the advance sets gc from null → 1.)
7. **Cannot set gc=1 in the terminal state.** Terminal frames stay terminal; rule 3's auto-set is blocked when the parent is already terminal, so a resurrection bug can't reactivate a done frame.
8. **Auto-delete at terminal.** An AFTER UPDATE trigger deletes any non-cap frame the moment it reaches its terminal state (stmt_idx past the last executable position). Chain reaction with rule 3: the auto-delete fires rule 3 on the parent, parent's walker advances, and if the parent's advance also reaches terminal, this trigger fires again. The whole call stack collapses upward to the cap. Cap is excluded (`process is not 1`) so the process anchor stays alive as the terminal signal.
9. **A frame cannot be deleted while it has a child.** Already enforced by the `parent_frame` FK (NO ACTION → RESTRICT-like). A `frames_delete_requires_no_child` trigger fires first with a specific error id for cleaner diagnostics.

## Dispatch shape under the new rules

A leaf command (e.g., `$x = 1` via `set_local_to_scalar`) no longer needs to push a marker frame. Two writes:

1. Do the work (add scalar, add ref to scope).
2. `UPDATE frame SET gc = 1`.

Then the walker advances: `UPDATE frame SET stmt_idx = stmt_idx + 1, gc = null`. When the advance reaches terminal, rule 8 auto-deletes the frame; rule 3 fires on the parent; the parent's cycle continues.

## Sprint work

- Sprint schema at `src/schema.sql` (copy of current shipping).
- Trigger rewrites: `frames_advance_requires_gc` (rule 5+6), `frames_gc_set_requires_advance` (drop or invert — new design has manual set-gc-to-1, not "gc=1 requires advance"), `frames_gc_set_deletes_children` (drop — no longer needed under the new cycle), `frames_gc_reset_requires_no_children` (drop — subsumed by rule 4), `frames_child_delete_requires_parent_gc` (drop — child delete triggers parent's gc change per rule 3, not requires it), etc.
- New triggers: rule 3 (child-delete → parent-gc=1), rule 4 (gc change requires no children), rule 7 (no set-gc=1 in the terminal state), rule 8 (auto-delete at terminal).
- INSERT-side: rule 2 (`frames_gc_starts_null` — reversal of earlier decision).

## Status

**Active.** Rules drafted; sprint schema seeded; trigger + test work pending.
