~~~vibecode
{"doc": "sprint-index", "sprint": "gc-atomicity",
	"role": "Codex review finding #1694. Points out that the four gc-cycle invariants presume the engine issues stmt_idx and gc=1 as a single atomic UPDATE. If the engine splits it into two statements, or a transaction is interrupted mid-cycle, the schema catches the FIRST violation (advance-without-gc fails loudly) but relies on Lua-side correctness for the surrounding contract. There is also a specific hole: the current `frames_advance_requires_gc` trigger does not reject advancing stmt_idx while gc is already 1 (only checks new.gc = 1, not old.gc = null). Source: issue #1694.",
	"status": "active — one identified hole; broader question about atomicity trust boundary"}
~~~

# gc-atomicity

Issue #1694. The gc-cycle triggers form a state machine:

- `frames_advance_requires_gc` — advancing stmt_idx requires gc=1 in the same UPDATE.
- `frames_gc_set_requires_advance` — setting gc=1 requires stmt_idx to advance in the same UPDATE.
- `frames_child_delete_requires_parent_gc` — child-frame delete requires parent.gc=1.
- `frames_gc_reset_requires_no_children` — resetting gc to null requires no child frames.

## Identified hole (from the follow-up discussion)

The current `frames_advance_requires_gc` WHEN clause:

~~~sql
when new.stmt_idx is not old.stmt_idx and new.gc is not 1
~~~

only checks `new.gc = 1` at the END of the UPDATE. It does NOT check that `old.gc` was null at the START. So an UPDATE that advances stmt_idx while gc is already 1 (skipping the reset step) isn't rejected:

| old.gc | new.gc | advances? | current | intended |
|---|---|---|---|---|
| null | 1    | yes | accepted | accepted (canonical) |
| null | null | yes | rejected | rejected |
| 1    | 1    | yes | **accepted** | **rejected** |
| 1    | null | yes | rejected | rejected |

Fix — tighten the WHEN clause:

~~~sql
when new.stmt_idx is not old.stmt_idx
    and (old.gc is not null or new.gc is not 1)
~~~

Only the canonical (null → 1) transition is accepted.

## Broader question (from Codex)

Even with the above tighten, the schema can't fully verify the engine is using the state machine correctly across a full cycle. Codex suggested three options: a detection column, a deferred check, or documentation. Prefer documentation — the per-trigger rules already catch each specific misuse loudly; what they can't catch is "engine forgot to complete a cycle before starting another," which is a bug the engine's own tests should catch.

## Status

**Active.** Trigger tighten is well-scoped; broader documentation still open.
