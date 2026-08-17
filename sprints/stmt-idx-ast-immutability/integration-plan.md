~~~vibecode
{"doc": "sprint-note", "sprint": "stmt-idx-ast-immutability",
	"role": "Full integration plan: promote the sprint's redesigned gc cycle into shipping. Explicitly acknowledges that many existing tests will fail post-integration — the sprint changes the meaning of gc=1 and the walker's advance shape, both of which the current engine and tests depend on. Post-integration cleanup handles the failures one at a time."}
~~~

# Integration plan

The sprint's schema at [sprints/stmt-idx-ast-immutability/src/schema.sql](sprints/stmt-idx-ast-immutability/src/schema.sql) and its 29 tests across four files are ready. Shipping untouched.

## Expected breakage

**Post-integration, many existing tests WILL fail.** This is by design:

- **Semantic flip on gc=1.** Under the old design, gc=1 meant "post-dispatch cleanup phase." Under the new design, gc=1 means "ready to advance." Anywhere in the engine or tests that reads gc=1 as the old semantic is now wrong.
- **Advance shape flip.** Old canonical advance: `SET stmt_idx = N+1, gc = 1` from `(N, null)`. New canonical advance: `SET stmt_idx = N+1` (bare) from `(N, 1)`, auto-set moves gc to null.
- **No cascade-delete-children.** Old design's `frames_gc_set_deletes_children` swept children when gc went null→1. New design uses rule 3 (child delete SETS parent's gc) instead — no cascade in the sweep direction.
- **Marker-push obsolete.** Leaf dispatchers used to push a marker child so a subsequent advance would cascade-sweep it. Under new rules, `set_local_to_scalar` and similar can just `SET gc = 1` directly on the current frame — the marker is unnecessary.

Post-integration, the failing tests get walked through one at a time to migrate their setup and assertions to the new state machine.

## Phase 1 — Requirements

Docs describing the gc cycle need updating BEFORE the schema lands (spec-first rule).

### 1.1 `requirements/cvm/frame-lifecycle.md`

The heaviest doc rewrite. Currently describes the four gc-cycle invariants under the old semantics (advance-couples-with-gc, gc-set-cascade-deletes-children, child-delete-requires-parent-gc, gc-reset-requires-no-children). Rewrite to describe the new nine-rule design (see the sprint's `index.md` for the rules list).

Key semantic shift to communicate:
- gc=null = "ready to dispatch"
- gc=1 = "ready to advance"
- Advance takes gc back to null (auto-set)
- Child delete triggers parent's next-advance-signal (rule 3)
- Reaching terminal auto-deletes the frame (rule 8), cap excluded

### 1.2 `requirements/cvm/index.md`

Small updates to the paragraph on cap-as-frame and to the ToC entry for frame-lifecycle if the wording drifted.

### 1.3 `requirements/cvm/garbage-collection/index.md`

Currently references `frames_gc_set_deletes_children` as the sweep mechanism. Rewrite: sweep now happens via rule 8 (auto-delete at terminal) + rule 3 (child-delete cascade). The GC substrate (needs_trace + trace routine) is unchanged; only the trigger that FIRES the sweep changes.

## Phase 2 — Shipping code

### 2.1 Schema promotion

Sprint's `src/schema.sql` → `src/engine/cvm/schema.sql`. Diff summary:

**New triggers (9):**
- `frames_gc_starts_null` (rule 2) — INSERT rejects gc=1.
- `frames_child_delete_sets_parent_gc` (rule 3) — AFTER DELETE cascades gc=1 to parent.
- `frames_gc_change_requires_no_child` (rule 4) — bidirectional block on gc change with children.
- `frames_advance_sets_gc_null` (rule 6 auto) — AFTER UPDATE OF stmt_idx sets gc=null.
- `frames_advance_rejects_non_null_gc` (rule 6 loud-catch) — reject advance UPDATE that includes gc=1 in the SET clause.
- `frames_gc_set_rejects_at_terminal` (rule 7) — reject gc=1 when stmt_idx = max.
- `frames_auto_delete_at_terminal` (rule 8) — AFTER UPDATE OF stmt_idx deletes non-cap frame at terminal.
- `frames_delete_requires_no_child` (rule 9) — specific error id backing the parent_frame FK.
- `frames_no_child_under_terminal_parent` — reject inserting a child under a terminal parent.

**Modified triggers (1):**
- `frames_advance_requires_gc` — WHEN clause flipped from `old.gc null AND new.gc 1` to `old.gc 1`. Only enforces "must have gc=1 to advance." The old "must set gc=1" side becomes "must NOT include gc except as null" via the loud-catch above.

**Removed triggers (5):**
- `frames_gc_set_requires_advance` — gc=1 is unrestricted under new rules.
- `frames_gc_set_deletes_children` — no more cascade sweep; rule 3 handles it inverted.
- `frames_child_delete_requires_parent_gc` — old design required parent.gc=1 BEFORE child delete; new design has delete SET parent's gc=1 (rule 3).
- `frames_gc_reset_requires_no_children` — superseded by rule 4 (bidirectional).
- `frames_delete_requires_gc_null` — dropped per Miko's call; a frame can be deleted at any gc state, subject to rule 9.

### 2.2 Engine code — expect changes needed

The engine currently uses the old advance shape and the marker-push pattern. Post-schema-promotion:

- **`src/engine/cvm/frame.lua`**: `set_local_to_scalar` currently pushes a marker child, then relies on the walker's next advance to sweep it. Under new rules, this should collapse to two writes: `add_scalar` + `add_ref` + `UPDATE frame SET gc = 1`. No marker push, no savepoint gymnastics.
- **`src/engine/engine.lua`**: the walker's per-statement advance uses the old shape. Needs to update to bare-advance form (`SET stmt_idx = stmt_idx + 1`) — the auto-set trigger handles gc.
- **Other row handlers**: any handler that dispatches a leaf command via the marker pattern needs the same simplification.

**Do NOT attempt to update the engine during the schema promotion.** The point of the sprint's approach is: land the schema, let the engine's tests break, then walk through each failure with fresh eyes. The failures ARE the todo list for engine work.

### 2.3 Test suite — expected failures

Shipping tests that WILL break after schema promotion:

- **`test_schema.lua`**: extensive gc-cycle tests using old advance shape and marker semantics. Every test that references `frames_gc_set_deletes_children`, `frames_gc_set_requires_advance`, `frames_child_delete_requires_parent_gc`, `frames_gc_reset_requires_no_children`, or `frames_delete_requires_gc_null` will break. Every test that uses the old canonical advance `SET stmt_idx = N+1, gc = 1` will break (rejected by the new `frames_advance_rejects_non_null_gc`).
- **`test_cvm.lua`**: uses the engine's public API but its assertions may reference gc state at moments that don't match under the new semantics.
- **`test_end_to_end.lua`**: runs real programs through the engine. Fails until the engine is updated to the new shape.
- **`test_dispatch.lua`, `test_sequence.lua`**: similar — engine-driven, breaks with engine.

Sprint-scoped tests migrate in as a new section of `test_schema.lua` (or as their own files).

## Phase 3 — Cleanup

- Archive `sprints/stmt-idx-ast-immutability/`. Git history preserves it.
- Once engine work is done and tests are green, drop any residual comments in the shipping schema that reference the old design.

## Ordering summary

1. Phase 1: rewrite the three requirements docs (frame-lifecycle, index, garbage-collection).
2. Phase 2.1: promote sprint schema to `src/engine/cvm/schema.sql`.
3. Phase 2.2 + 2.3: do NOT attempt to fix engine code or tests during this step. Just land the schema.
4. Confirm: sprint's 29 tests pass against the schema in shipping. Everything else fails.
5. Post-integration cleanup: walk through failures one at a time. Migrate each to the new semantics. This is a series of small commits, not a single migration.
6. Phase 3: archive sprint dir when all failures are addressed.

## Post-integration triage — recommended order

When walking through failures:

1. **Engine walker's advance shape** — fix `engine.lua`'s advance UPDATE first. Cascades to fix many test failures.
2. **Frame handlers** — `set_local_to_scalar` and any siblings. Simplify the savepoint + marker pattern to the new direct-set pattern.
3. **test_schema.lua** — migrate gc-cycle tests one at a time. Each becomes simpler under the new design.
4. **test_cvm.lua** — update assertions that read gc state at specific moments.
5. **test_end_to_end.lua** — should pass once engine is updated.
