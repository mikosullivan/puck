~~~vibecode
{"doc": "sprint-index", "sprint": "dispatch-cutover",
	"role": "Move the clean dispatch structure built in the dispatch sprint into shipping. Rip out the current hodgepodge in `src/engine/engine.lua` (hardcoded if/elseif in `M:run_row`, keyed lookup in `M:run_bwc`, empty `bwc_handlers` table) and replace with a single `dispatch(self.row_handlers, self, row)` call reading an empty handler chain. No new tests. No handler registrations. Post-cutover, the runtime is consistently in an 'empty chain' state — any program raises `unrecognized_row_head`. First-variable is the next sprint after this one; it registers the first handler and adds the end-to-end test that proves execution works.",
	"status": "kicked off",
	"depends_on": ["dispatch"],
	"blocks": ["first-variable"],
	"trigger_word": "integration"}
~~~

# dispatch-cutover

Sidesprint that follows the [dispatch](../dispatch/) sprint. Purpose: move the clean structure into production use. Then observe.

## Goal

**Replace the current dispatch machinery in `src/engine/engine.lua` with the mechanism the dispatch sprint built.** Result: one dispatch pattern, empty handler chain, all rows raise `unrecognized_row_head` cleanly.

No new tests. No handler registrations. The `first-variable` sprint (planned as next) handles registration + coverage.

## What actually happens in engine.lua

The [dispatch integration plan](../dispatch/integration#engine-wiring) already spelled this out. Summary here:

**Removed** — `bwc_handlers` local table, `M:run_bwc` method, the `head.bwc` if-branch in `M:run_row`, `unrecognized_bwc` raises and debug entries, the `bwc` mention in the module's `dispatch_contract` and `role` fields.

**Replaced** — `M:run_row(row)` body becomes a single `dispatch(self.row_handlers, self, row)` call. `M.new()` gains a `row_handlers = {}` slot. Top of file gets `require('handler')` + `require('dispatch')`. Module JSON header text updated.

**Kept** — `M:eval(atom)` (value-atom dispatcher; different concern, later sprint). `atom_keys` helper (still used by `eval`'s raise). Everything else.

## Expected outcome

- **The 138 shipping engine tests still pass.** Verified pre-cutover: zero tests exercise `run_row` / `run_bwc` / `eval` / `run` / `unrecognized_*` messages.
- **The 9 dispatch tests (promoted from the sprint) still pass.**
- **The runtime consistently can't execute a program.** Any `engine:run()` call would raise `unrecognized_row_head` on the first row it tries to dispatch. This is the same "can't run programs" state as before, just via one clean pattern instead of a hodgepodge.

Zero-tests-break here is a diagnostic, not a green light. It reveals the current test suite doesn't exercise the runtime's execution path — a coverage gap that first-variable fills.

## Then observe

Sprint doesn't try to guess what else needs cleaning up. After cutover, the engine is in a well-defined state (empty dispatch chain, everything else working). What comes next is deliberate — probably first-variable, but we look at what we have first.

## Concrete steps

1. **Confirm the sprint's own tests still pass** — `lua5.4 sprints/dispatch/tests/test_dispatch.lua` → 9 passed. (They're the source of the modules we're about to move.)
2. **Move the files** —
   - `git mv sprints/dispatch/src/handler.lua src/engine/handler.lua` — strip the three test-support subclasses at the same time; they land inline in the promoted test file.
   - `git mv sprints/dispatch/src/dispatch.lua src/engine/dispatch.lua` — pure move.
3. **Edit `src/engine/engine.lua`** per the removed/replaced/kept breakdown. Order within: add `require` lines, delete removed code, rewrite `M:run_row`, add `row_handlers` slot to `M.new()`, update module JSON header text.
4. **Move + convert the test file** — `git mv sprints/dispatch/tests/test_dispatch.lua tests/main/lua/engine/test_dispatch.lua`; convert to shared-runner format (`h.test` / `h.assert_eq`; drop the standalone runner block; adjust package.path). Inline the three test-support subclasses at the top of the file.
5. **Run the shipping test suite** — 138 + 9 = 147 total. Expected: all pass.
6. **Delete `sprints/dispatch/`** — the source sprint's directory. Its purpose is spent.
7. **Delete `sprints/dispatch-cutover/`** — this sprint's own dir, once the work is done.
8. **Commit as one unit** — "dispatch cutover: replace engine.lua's hodgepodge with the chain-of-responsibility mechanism; empty handler chain; 147 tests passing."

## Deferred, not addressed

- **Coverage of the runtime execution path** — deliberately no new tests in this sprint. First-variable adds the end-to-end test that proves `engine:run()` on `$x = 1` actually executes.
- **`M:eval` cleanup** — value-atom dispatch stays as-is. Different concern, its own sprint eventually.
- **`unrecognized_row_head` message shape** — sprint's dispatch raises with a generic message ("no handler in the chain recognized the input"); shipping's current message includes atom-keys. Preference: `M:run_row` wraps `dispatch(...)` in `pcall` and re-raises with atom-keys appended. Called out in the dispatch integration plan; still valid here.

## Status

**Kicked off.** Waiting on the integration trigger.
