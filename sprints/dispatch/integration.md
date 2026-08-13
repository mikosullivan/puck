~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "dispatch",
	"role": "Integration plan for the dispatch sprint. Promotes the Handler base class and the dispatch function into shipping, and moves the test-support subclasses out of the shipping handler.lua into test-support territory. Whether integration also touches `M:run_row` is an open decision documented in the Engine wiring section.",
	"status": "plan in progress; one open decision on wiring shape",
	"trigger_word": "integration"}
~~~

# dispatch integration plan

Written up so integration is a checklist rather than a design exercise. Nothing here has landed in shipping — the whole sprint still lives under `sprints/dispatch/`.

## What promotes

| Sprint path | Shipping destination | Notes |
|---|---|---|
| [`sprints/dispatch/src/handler.lua`](./src/handler.lua) | `src/engine/handler.lua` | Base class only. Test-support subclasses split out — see [Splitting the test-support subclasses](#splitting-the-test-support-subclasses). |
| [`sprints/dispatch/src/dispatch.lua`](./src/dispatch.lua) | `src/engine/dispatch.lua` | Pure move. |
| [`sprints/dispatch/tests/test_dispatch.lua`](./tests/test_dispatch.lua) | `tests/main/lua/engine/test_dispatch.lua` | Retarget package paths; convert to the shared runner format (`h.test` from `helpers`). |

## Splitting the test-support subclasses

`Handler.AlwaysTrue`, `Handler.AlwaysFalse`, `Handler.AlwaysRaise` are baked into the sprint's `handler.lua` for now. Shipping shouldn't carry test-support code alongside production classes. Two clean landing spots — pick one at integration:

- **Inline into `tests/main/lua/engine/test_dispatch.lua`** — define the three subclasses as locals at the top of the test file. Simplest; keeps them close to their only user.
- **New file `tests/main/lua/engine/handlers_for_testing.lua`** — if other test files end up needing the same subclasses, this is where they'd go. Overkill for now (only test_dispatch uses them).

Recommend inline unless a second test file materializes with the same need.

## Engine wiring

The current dispatch surface in `src/engine/engine.lua` is a hodgepodge: three different patterns for three separate concerns. Integration replaces the row-head dispatch cleanly with the sprint's chain mechanism, removes the machinery that only existed to serve it, and leaves the value-atom dispatcher alone as an unrelated concern for a later sprint.

Concrete before-and-after in `src/engine/engine.lua`:

### Removed

- **`local bwc_handlers = {}`** (currently around line 84) — the empty keyed-lookup table used by `run_bwc`. No consumers after `run_bwc` is removed.
- **The comment block above `bwc_handlers`** (currently ~lines 60-83) — describes a mechanism that no longer exists.
- **`M:run_bwc(name, row)`** method (currently ~lines 307-317) — no callers after `M:run_row` is replaced. The keyed-lookup dispatch pattern goes with it.
- **The docstring block above `M:run_bwc`** (`## Dispatching a bwc`) — describes the removed method.
- **The `head.bwc` if-branch inside `M:run_row`** and its fallback raise — replaced entirely by a `dispatch` call.
- **The `dispatch_contract` field** in the module JSON header — currently lists three `unrecognized_*` raise sites; only two survive (`unrecognized_row_head` becomes dispatch's, `unrecognized_atom_kind` stays with `eval`; `unrecognized_bwc` goes).
- **`debug_log` entries with `reason = 'unrecognized_bwc'`** — no code path emits this anymore.

### Replaced

- **`M:run_row(row)`** — entire body replaced with:
  ~~~lua
  function M:run_row(row)
      dispatch(self.row_handlers, self, row)
  end
  ~~~
  Docstring rewritten to describe the chain mechanism and point at `handler.lua` (interface) + `dispatch.lua` (function).
- **`M.new()`'s return table** — gains a new slot: `row_handlers = {}`. Empty at construction; the sprint's own tests use direct `table.insert`; a future sprint (first-variable) will register real handlers here.
- **Top of file** — new `require` lines: `require('handler')`, `require('dispatch')`.
- **Module JSON header's `role` field** — the "iteratively extended one construct at a time: any atom kind / bwc / row-head shape..." language updated to remove the bwc-specific bit (`row-head shape` becomes "handler in the row-handlers chain"; `atom kind` stays as-is since `eval` is untouched).

### Kept (out of scope for this sprint)

- **`M:eval(atom)`** — value-atom evaluator, currently hardcoded if/elseif on atom keys (`atom.v` for literals). Different dispatch surface: takes one atom, not a row. Could get its own chain treatment in a later sprint, but not here — the sprint's mechanism is designed for row heads. Leaving it alone keeps this integration scoped.
- **`atom_keys` helper** — still used by `M:eval`'s raise message (`unrecognized_atom_kind: ...`). Not removed even though `M:run_row` stops using it.
- **`M:load`, `M:run`, `M.new`'s other slots, the debugger contract, everything else** — unrelated to dispatch; untouched.

### Net behavior change

Zero, in practice. What actually happens on the paths this affects:

- Any row previously landing in `run_row` — before: `{bwc: name}` routed through `run_bwc` (which found no handler in the empty `bwc_handlers` and raised `unrecognized_bwc`); everything else raised `unrecognized_row_head`. After: everything hits (empty) `dispatch` and raises `unrecognized_row_head`. Different raise for the bwc case, same raise for everything else. No test exercises this (verified: zero test hits on `run_row`, `run_bwc`, `unrecognized_*`).
- Load, boot, CVM operations, wire operations, the frame-0 machinery — all unaffected.

The `unrecognized_bwc` raise disappears from the codebase entirely. That's the cleanup — one less pattern, one less error id.

## Test suite retarget

Sprint test uses a standalone runner + local `pcall`-based assertions. Shipping tests use `helpers.h.test` from `tests/main/lua/engine/helpers.lua`. Conversion:

- Replace `test(name, fn)` → `h.test(name, fn)`.
- Replace `assert_eq(a, b, msg)` → `h.assert_eq(a, b, msg)`.
- Replace `assert_raises_matching(...)` — no direct equivalent in `helpers`; either add one there (helps future tests) or inline `pcall` + `string.find` in each test that uses it.
- Drop the standalone runner block (`pass_count` / `fail_count` / `os.exit`) — the shared runner handles that.
- Replace `package.path` prefix line with the shared-runner-provided require path.

Verify against the shared runner: `lua5.4 tests/main/lua/engine/run.lua` picks up the file automatically.

## Order of operations

1. **Move `handler.lua`** — `git mv sprints/dispatch/src/handler.lua src/engine/handler.lua`. Strip the three test-support subclasses (they land somewhere else per step 2). Update the JSON header's `status` and remove the "test-support subclasses baked in" language from the module docstring.
2. **Land the test-support subclasses** — inline into what will become `tests/main/lua/engine/test_dispatch.lua` (recommended), OR create `tests/main/lua/engine/handlers_for_testing.lua` if you'd rather split.
3. **Move `dispatch.lua`** — `git mv sprints/dispatch/src/dispatch.lua src/engine/dispatch.lua`. Pure move; nothing to change in the file.
4. **Edit `src/engine/engine.lua` per [Engine wiring](#engine-wiring)** — remove the machinery listed under Removed; apply the changes under Replaced; leave the code under Kept alone. Order within this step: add the two new `require` lines first, then delete removed code, then rewrite `M:run_row`, then add the `row_handlers` slot to `M.new()`, then update the module JSON header's `role` and `dispatch_contract` fields.
5. **Move + convert the test file** — `git mv sprints/dispatch/tests/test_dispatch.lua tests/main/lua/engine/test_dispatch.lua`; convert to the shared runner format per [Test suite retarget](#test-suite-retarget).
6. **Run the full shipping test suite** — 138 pre-integration engine tests + 9 dispatch tests. Should be 147 total, zero regressions.
7. **Delete `sprints/dispatch/`** — the sprint's whole dir. `sprints/.gitkeep` stays (per boundary discipline).
8. **Commit as one unit** with a message referencing this plan and summarizing what promoted.

## Risks and open questions

- **`unrecognized_row_head` message** — the sprint's dispatch says `"unrecognized_row_head: no handler in the chain recognized the input"`. Shipping's current `M:run_row` message includes the atom-key set of the row's head: `"unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {...}"`. The atom-keys detail helps debugging when the walking-skeleton hits an unhandled shape. Either dispatch grows a way to shape its raise message (a callback, or an extension arg), or the `M:run_row` call-site wraps `dispatch(...)` in a `pcall`, catches the raise, and re-raises with the atom-keys appended. Preference: the second — keeps dispatch simple, adds one small block to `M:run_row`.
- **`assert_raises_matching`** — helper isn't in the shared `helpers.lua`. Either add it there (helps future tests) or inline `pcall` + `string.find` in the dispatch tests. Preference: add to helpers, since raise-with-substring checks come up often.

## Status

**Plan captured. No artifacts touched.**
