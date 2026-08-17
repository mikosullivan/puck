~~~vibecode
{"doc": "sprint-index", "sprint": "stmt-idx-upper-bound",
	"role": "Split from the retired close-schema-holes sprint (hole #3). Adds two triggers that cap a frame's stmt_idx at max(json_array_length(ast), 1): one BEFORE INSERT, one BEFORE UPDATE OF stmt_idx. Sources: issue #1665 (from ChatGPT critique § 4).",
	"status": "pre-integration — sprint schema + tests complete; shipping untouched"}
~~~

# stmt-idx-upper-bound

Hole #3 from the ChatGPT critique. `stmt_idx >= 0 and primitive = 'f'` was the only bound in shipping — nothing prevented a frame from advancing its `stmt_idx` past the end of its ast. Downstream logic (walker's dispatch, terminal-state check, cap-frame lifecycle) all assume `stmt_idx <= max(json_array_length(ast), 1)`.

## Fix

Two triggers, same error id:

- **`frames_stmt_idx_within_ast_bounds`** — BEFORE INSERT on `objects` when `primitive = 'f' and stmt_idx > max(json_array_length(ast), 1)`.
- **`frames_stmt_idx_within_ast_bounds_on_update`** — BEFORE UPDATE OF stmt_idx on `objects` with the same condition.

The two shapes:

- Non-empty ast (length N): valid range `{0..N}`. 0..N-1 is a position within the ast; N is one past the last statement (terminal for an ordinary frame).
- Empty ast (length 0): valid range `{0, 1}`. 0 is the born state; 1 is the cap's terminal transition (advanced past nothing).

## Status

**Pre-integration.** Sprint schema at [sprints/stmt-idx-upper-bound/src/schema.sql](https://puck.uno/sprints/stmt-idx-upper-bound/src/schema.sql); tests at [sprints/stmt-idx-upper-bound/tests/test_stmt_idx_bounds.lua](https://puck.uno/sprints/stmt-idx-upper-bound/tests/test_stmt_idx_bounds.lua). Shipping untouched.

## Integration

Two-trigger add to shipping's `src/engine/cvm/schema.sql` right after the gc-cycle preamble, alongside `frames_stmt_idx_advances_by_one`. No column changes.
