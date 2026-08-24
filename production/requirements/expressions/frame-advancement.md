~~~vibecode
{"doc": "requirements_expressions_frame_advancement", "role": "Brief reference for the state machine every frame follows. Three state variables (frame_stmt_idx, frame_gc, has-child); three at-rest states for leaves plus one more for non-leaves; nine numbered advancement rules with their schema trigger names for grep. Written as a quick-look for anyone writing a handler, extending the walker, or debugging why a frame won't advance. Detailed prose lives at [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle); this doc is the tight summary."}
~~~

# Frame advancement — summary

Three state variables, four at-rest states, and nine rules that govern transitions.

## State variables

- **`frame_stmt_idx`** — 0-based index into `frame_ast`. Starts at 0 (frames born there). Advances monotonically by +1. Terminal when `frame_stmt_idx >= json_array_length(frame_ast)`.
- **`frame_gc`** — two-state flag: **null** ("ready to dispatch the command at stmt_idx") or **1** ("ready to advance to next stmt_idx"). Fresh frames born at null.
- **has-child** — derived: at most one `objects` row with `frame_parent = this frame's pk` (schema-enforced by `objects_one_child_per_frame` unique index).

## At-rest states

Every state below is a valid resume point. The DB fully describes what happens next.

- **About to dispatch** — no child, gc=null, not terminal. Walker's next action: run `frame_ast[stmt_idx]`.
- **Ready to advance** — no child, gc=1. Walker's next action: drain `needs_trace`, then advance stmt_idx by +1.
- **At terminal** — no child, gc=null, stmt_idx = `json_array_length(frame_ast)`. Walker's next action: reap this frame.
- **Waiting for child** (non-leaf only) — has child, gc=null. Frame is paused; child is running.

## Advancement rules

Numbered by their schema trigger names for grep.

1. **Fresh frames born at `stmt_idx=0`, `gc=null`.** `frames_stmt_idx_starts_at_zero`; `frames_gc_starts_null`.
2. **`gc` cannot change while has-child.** Bidirectional. `frames_gc_change_requires_no_child`.
3. **Child DELETE flips parent's `gc` to 1** — the ONLY way parent's gc changes while it's "waiting for child." `frames_child_delete_sets_parent_gc`. Cap-exempt.
4. **Advance requires `gc=1`** — if gc is null, the advance UPDATE fails. `frames_advance_requires_gc`.
5. **Advance auto-nulls `gc`** — walker's UPDATE just changes stmt_idx; the trigger nulls gc atomically. `frames_advance_sets_gc_null` + `frames_advance_rejects_non_null_gc`.
6. **`stmt_idx` advances by +1 only** — no backward jumps, no skips. `frames_stmt_idx_advances_by_one`.
7. **`gc` can't be set to 1 at terminal** — done frames stay done. `frames_gc_set_rejects_at_terminal`.
8. **Frame cannot be deleted while has-child.** `frames_delete_requires_no_child`.
9. **No child insert under a terminal parent.** `frames_no_child_under_terminal_parent`.

## Consequences

- **Every walker tick is one atomic UPDATE (or one DELETE for reap).** The triggers do the rest; the walker itself is small.
- **Handlers that spawn a child** don't need to set gc. Spawning pins gc at null (rule 2); the child's later DELETE flips gc to 1 (rule 3); the walker's next tick advances.
- **Handlers running inline** (no child spawn) must set `gc=1` explicitly before returning — via `engine.data:mark_frame_gc(frame_pk)`. The walker's advance needs gc=1 (rule 4); if the handler didn't spawn a child, nothing else will flip it.
- **Loops don't rewind `stmt_idx`** (forbidden by rule 6). Loop constructs (`engine.while`, etc.) live in the primitive that runs the body — it invokes the body-closure as many times as it wants; each of those invocations is its own frame with its own stmt_idx that only ever goes forward.
- **The walker's "what to do next" is a lookup, not a decision.** Read the frame's (stmt_idx, gc, has-child, terminal?) tuple; the four at-rest states map to exactly four next actions. No branching to reason about.

## Related

- [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle) — full prose spec.
- [evaluation-model](./evaluation-model) — how this state machine fits into the sprint's overall command evaluation design.
- [primitives/if](./primitives/if), [primitives/while](./primitives/while) — primitives that spawn child frames and rely on rule 3 for the return-to-parent signal.
