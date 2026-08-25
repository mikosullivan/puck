~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "stop",
	"role": "Ordered plan for landing the stop sprint into production. One pass: absorb StopLarry's overrides (run, run_frame, process_stop, restart_frame) into production's Engine class, promote halt.lua, drop the reap_frame cap-skip into production, migrate the sprint's tests. After the pass, sprints/stop/ is deleted — nothing sprint-scoped survives. Substantial parts of the sprint already landed during design (schema changes, CVM changes, engine current_frame_pk/role_pk, %process.stop as system primitive, handler refactor); this doc lists those explicitly under 'What's already in production' so the remaining work is clear. Post-integration section notes optional followups that don't gate the integration."}
~~~

# stop-sprint integration plan

## What's landing

The sprint delivered one primary thing: **halt-and-restart mechanics for `%process.stop`**. `%process.stop` halts a running process via a Lua-side sentinel exception; a subsequent call to `run()` resumes the halted process, optionally injecting a reply value that becomes the halted expression's result. Same `run` entry point serves both first-time execution and continuation-after-halt.

At the class level, the sprint's `StopLarry` overrides four Engine methods (`run`, `run_frame`, `process_stop`, plus adds `restart_frame`), depends on a sprint-scoped `halt.lua` sentinel module, and adds a handful of sprint-scoped prepared statements and helper functions. Integration is straightforward: absorb all of that into production's `Engine` class, promote `halt.lua` to production, and delete the sprint directory.

## What's already in production

Most of the sprint's supporting design has already landed during the sprint's design conversations — Miko and Claude drove production edits directly rather than staging them for a separate integration. Recap:

- **Schema changes** (`production/src/engine/cvm/sqlite/schema.sql`):
  - Cap now participates in the frame_gc cycle. `frames_child_delete_sets_parent_gc` no longer has a cap-exempt clause — cap.gc = 1 fires when its child (frame_0) reaps, same as any other parent.
  - Cap's ast changed from `'[]'` to `'[null]'` (length 1). Cap starts at stmt_idx=0 non-terminal, advances to stmt_idx=1 to reach terminal — matches how every other frame walks its cycle.
  - `frames_no_child_under_terminal_parent` no longer has a cap-exempt clause either (cap isn't terminal at boot anymore under the new ast, so no exemption needed).
- **CVM changes** (`production/src/engine/cvm/sqlite/init.lua`):
  - Renamed `drain_needs_trace` → `garbage_collect` (with all call sites in engine.lua updated).
  - Added `role_by_pk(pk)`, `get_ref_child_at_idx(parent, idx)`, `ensure_own_scope(frame_pk, role_pk)`.
- **Frame-wrapper changes** (`production/src/engine/cvm/sqlite/frame.lua`):
  - Deleted `set_local_to_scalar` (moved inline into the handler).
  - Deleted `own_scope` / `ensure_own_scope` / `_get_array_child_at` (moved to CVM).
  - Class is now an empty subclass of `object` — see [Post-integration](#post-integration).
- **Engine changes** (`production/src/engine/engine.lua`):
  - `Engine.new` initializes `current_frame_pk` + `current_role_pk` (replaces the wrapper-instance `current_frame` field).
  - `Engine.run_frame` publishes both fields (hoisted out of the loop; immutable per frame).
  - `Engine.run` advances the cap after `run_frame(frame_0)` returns — cap goes through its own run-gc + advance cycle to reach terminal.
  - `Engine:process_stop()` method added, called from `Engine:run_row` on `%process.stop` shape recognition. Default behavior: `self.stopped = true`.
- **Handler changes**:
  - `handlers/variable-scalar.lua` inlines the write path (savepoint + add_scalar + ensure_own_scope + upsert_ref + mark_frame_gc), no more wrapper-method delegate. Reads `engine.current_frame_pk` / `engine.current_role_pk`.
  - `handlers/process-stop.lua` deleted; `%process.stop` is now a system primitive dispatched by `Engine:run_row`, not a pluggable handler.
- **Test updates**: several production tests updated to reflect the new cap-terminal state (stmt_idx=1 not 0, gc=null via auto-null-after-advance not exempt), the cap-insert ast (`'[null]'` not `'[]'`), and the new field names (`current_frame_pk` / `current_role_pk`).

What remains sprint-scoped is the halt-and-restart mechanics itself — HALT sentinel, restart_frame recursion, the merged run/restart entry point, and the `%process.stop`-specific process_stop override that raises HALT instead of setting a flag.

## Preconditions

- Sprint tests green: `lua5.4 sprints/stop/tests/test_process_stop.lua` — 32/32.
- Production tests green: `lua5.4 production/tests/main/lua/engine/run.lua` — 343/343.
- Working tree clean of unrelated changes.
- Production locked (default). Unlock with `chmod -R u+w production/`.

## Integration steps

Numbered, sequential. Do them in this order and each intermediate state should keep production tests green.

### 1. Promote `halt.lua` to production

Copy [sprints/stop/src/halt.lua](./src/halt.lua) to `production/src/engine/halt.lua`. No content changes. Update the module docstring's `role` line to remove sprint-scoped framing ("sprint's `%process.stop` handler" → "the `%process.stop` primitive"; "sprint's Larry's overridden run()" → "Engine:run"), but the code stays byte-identical.

### 2. Change `Engine:process_stop` to raise HALT

Replace the default `self.stopped = true` body with the sprint's version: insert a stop frame under `self.current_frame_pk` (via a new `insert_stop_frame` prepared statement), then `halt.raise()`. Add `require('halt')` to the engine module. The prepared statement mirrors the sprint's `stop_insert_stop_frame`; add it in `Engine.new`'s `stmts` block. Delete the `self.stopped = false` initialization line — no longer needed.

### 3. Rewrite `Engine:run_frame` per the sprint's version

Three deltas:
- Drop the mid-loop `if self.stopped then break end`.
- Drop the pre-reap `if self.stopped then return end`.
- Change `if ast_json == nil then return end` to `error("run_frame_no_ast: …")`.
- Drop the tail `garbage_collect` after the reap (parent's run-gc step handles it).
- Add optional `role_pk` second parameter; hoisted current_frame_pk/role_pk publish uses `role_pk or self.data:role_by_pk(frame_pk)`.

### 4. Rewrite `Engine:run` per the sprint's version

Signature becomes `run(restart_value?)`. First-call bootstrap when `self.caspm` is set; continuation on subsequent calls. Optional value injection (with `engine_class='stop'` guard raising `run_inject_requires_stop_frame`). Delegates to `self:restart_frame(cap_pk)` inside `xpcall` + `halt.is_halt` catch. Returns `{complete=1, cap_pk}` or `{stopped=1, cap_pk}`. The old post-`run_frame(frame_0)` manual cap-advance goes away — cap's cycle happens inside restart_frame's recursion.

Drop the `run_before_load` error id naming clash by renaming to `engine_run_before_load` (or similar).

### 5. Add `Engine:restart_frame` + helpers

Port from the sprint verbatim, dropping the `stop_` prefix on prepared statements and helpers:
- `Engine:restart_frame(frame_pk)` — the two-pre-step + delegate method.
- Local helper `find_child_of(self, frame_pk)`.
- Local helper `get_frame_gc(self, frame_pk)`.
- Local helper `get_engine_class(self, object_pk)`.
- Local helper `advance_past_current(self, frame_pk)`.

Add the prepared statements to `Engine.new`'s stmts block (drop the `stop_` prefix):
- `find_child_of` → `select object_pk from objects where frame_parent = ?`
- `get_frame_gc` → `select frame_gc from objects where object_pk = ?`
- `get_engine_class` → `select engine_class from objects where object_pk = ?`
- `insert_stop_frame` → the sprint's stop-frame insert (renamed from step 2).

Note: `stop_get_owner_role` duplicates the existing `cvm:role_by_pk`. Use `role_by_pk` at all call sites instead of duplicating.

### 6. Change production's `reap_frame` to skip caps

Add `and frame_process_cap is null` to the prepared statement's WHERE clause. Under the new schema+run_frame path, cap goes through `run_frame`, hits terminal, and would try to reap itself. The cap-skip clause makes the reap a silent no-op on caps so cap survives as the process anchor. This was the sprint's `reap_frame` override; now becomes production's default.

### 7. Migrate sprint tests

Move sprint tests into production. Two paths worth considering:
- **Single file**: create `production/tests/main/lua/engine/sqlite/test_halt_and_restart.lua` from the sprint's `test_process_stop.lua`, updating requires + adjusting for the fact that `StopLarry` is now just `engine.new()`.
- **Split by concern**: some tests fit the existing `test_process_stop.lua` (halt shape, engine.stopped observation); the restart-and-injection tests warrant a new `test_restart.lua`.

Either works; the single-file path is less bookkeeping. Update the tests' requires (`stop_larry` → `engine`), drop the sprint-scoped `StopLarry.new()` calls in favor of `engine.new()`, adjust assertions that refer to sprint-scoped naming (`stop_larry_run_before_load` → whatever error id we settle on in step 4, `stop_larry_inject_requires_stop_frame` → likewise).

### 8. Update the production tests that referenced the old ProcessStop-flag model

`production/tests/main/lua/engine/sqlite/test_process_stop.lua` currently asserts `self.stopped` behavior — under the new design, `self.stopped` doesn't exist. Rewrite the assertions to check the HALT-caught result hash (`result.stopped == 1`) and that the stop frame exists in `objects` after the halt. Any other tests grepping `self.stopped` need similar updates.

### 9. Verify

Run production tests: `lua5.4 production/tests/main/lua/engine/run.lua`. Expected: full pass. If any test breaks, the failure is a signal about the integration, not a reason to work around — fix the underlying issue.

## Post-integration

Optional cleanups that don't gate the integration but are worth doing while the changes are fresh:

- **Empty frame wrapper class.** `production/src/engine/cvm/sqlite/frame.lua` is now an empty subclass of `object` — every method it used to expose (`set_local_to_scalar`, `own_scope`, `ensure_own_scope`) moved to CVM as plain functions taking pks. The class survives only so `object.new` has a dispatch target for `control='f'`. Worth considering whether to fold `frame` into `object` and drop the `control='f'` dispatch branch. If some future frame-specific wrapper behavior lands (memoization on frame identity, say), the class re-earns its keep and we'd un-fold. Not needed for this integration.
- **`role_pk` parameter usage.** `Engine:run_frame(frame_pk, role_pk?)` accepts an optional `role_pk` that skips the `role_by_pk` lookup when the caller already knows it. No current caller uses it; the hook is in place for the first handler that spawns a child frame and inherits the parent's role. When that handler lands, it should pass `role_pk` to save a lookup per spawn.
