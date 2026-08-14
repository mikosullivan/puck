~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "end-to-end",
	"role": "Plan for promoting the sprint's schema changes, StmtWalker rewrite, and end-to-end tests into shipping. Sprint scope: process-goes-to-completion, stmt_idx-driven walk, atomic per-statement and per-frame transitions via SQL triggers.",
	"trigger": "requires 'proceed with the integration' / 'proceed with the assimilation'"}
~~~

# Integration plan — end-to-end process completion

## Overview

The sprint moves shipping from "run drives one frame's rows via an in-memory Lua for-loop, then returns" to "run drives frame 0 via a `stmt_idx`-driven walk with atomic per-statement and shutdown transitions." When the empty case is done, `engine:run()` returns a hash carrying `complete` and `message` reaped from the process record, and (by default) the process record has been auto-deleted.

Under the sprint's design, every legal DB state is a valid resume state — either no frames, or the deepest frame at rest with `stmt_idx < ast.length`, or the deepest frame past its ast awaiting cleanup. Frames with children mark mid-execution; a single atomic INSERT of a child implicitly reclassifies the parent as in-flight.

## Concrete changes

### 1. Schema additions on `processes`

[src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql) — the `create table processes (...)` block:

- Add `complete integer not null default 0 check (complete in (0, 1))` — the completion flag.
- Add `message text default null` — the process's reaped output; free-form text (engine chooses the wire form).

### 2. `processes_no_update` trigger relaxed

Currently blocks every UPDATE. Change to block only changes to `process_pk`:

~~~sql
create trigger processes_no_update
before update on processes
when new.process_pk is not old.process_pk
begin
	select raise(abort, 'processes_pk_immutable: processes.process_pk is immutable');
end;
~~~

This is what lets the walker (and the `processes_complete_after_frame_0_delete` trigger) set `complete = 1` and `message = ...`.

### 3. New SQL triggers on `objects`

Land three new triggers in the `objects` section:

- **`objects_ast_valid_insert`** — BEFORE INSERT WHEN `new.primitive = 'f'`. Raises `ast_not_valid_json` or `ast_not_array` if `new.ast` isn't a JSON array. Validates at write time so the walker can trust the shape.
- **`objects_ast_immutable`** — BEFORE UPDATE OF ast WHEN `new.ast is not old.ast`. Raises `ast_immutable` on any attempt to change a frame's ast after insert. Flips the shipping schema's "Mutable" comment on the ast column to immutable — a frame's code is fixed at push; the engine only reads it during dispatch, never writes it back.
- **`frames_delete_children_after_stmt_idx_update`** — AFTER UPDATE OF stmt_idx WHEN `new.primitive = 'f'`. Deletes any child frame under `new.object_pk`. Bundles child-cleanup into the same UPDATE as the stmt_idx bump — the Lua side never has to issue a separate DELETE.
- **`processes_complete_after_frame_0_delete`** — AFTER DELETE WHEN `old.primitive = 'f' AND old.process IS NOT NULL`. Flips `processes.complete = 1` for `old.process`. Bundles process-completion into the frame-0 DELETE.

### 4. `Engine:run` rewrite (two-level walk)

Current `run` in [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua) drives one frame via an in-memory Lua `for _, row in ipairs(cjson.decode(ast_json)) do self:run_row(row) end`. Replace with the sprint's shape from [sprints/end-to-end/src/stmt_walker.lua](https://puck.uno/sprints/end-to-end/src/stmt_walker.lua):

- **`run`** — resolves `frame_pk` (fresh via `create_frame_0`, revival via `get_latest_frame`), calls `run_frame(frame_pk)`, reaps the process's `complete` + `message` into a return hash via the `reap_process` prepared statement, and (if `self.auto_delete_process`) deletes the process record.
- **`run_frame(frame_pk)`** — fetches + decodes the frame's ast (shape-checked as a JSON array), then loops on `while get_stmt_idx() < #ast`, dispatching each row through the row-handler chain and issuing one `advance_stmt_idx` UPDATE per successful dispatch. When the ast is exhausted, if the frame's `process` is set, deletes the frame (which fires the mark-complete trigger). Returns the process_pk (or nil for sub-frames).

`M:run_row` from shipping is folded into `run_frame` as an inline handler-chain walk; [src/engine/dispatch.lua](https://puck.uno/src/engine/dispatch.lua) becomes unused by the walker (see step 8 below).

### 5. Prepared statements

Every SQL statement the walker issues gets compiled once at engine construction and stashed on `engine.stmts`. Move the sprint's set into `engine.new`:

~~~lua
engine.stmts = {
	get_ast          = engine.cvm:prepare('select ast from objects where object_pk = ?'),
	get_stmt_idx     = engine.cvm:prepare('select stmt_idx from objects where object_pk = ?'),
	advance_stmt_idx = engine.cvm:prepare('update objects set stmt_idx = stmt_idx + 1 where object_pk = ?'),
	get_process      = engine.cvm:prepare('select process from objects where object_pk = ?'),
	delete_frame     = engine.cvm:prepare('delete from objects where object_pk = ?'),
	reap_process     = engine.cvm:prepare('select complete, message from processes where process_pk = ?'),
	delete_process   = engine.cvm:prepare('delete from processes where process_pk = ?'),
}
~~~

### 6. `auto_delete_process` slot with default `true`

New slot on Engine; default is on. Set in `engine.new()`:

~~~lua
engine.auto_delete_process = true
~~~

Documented as the opt-out for keep-alive callers (dashboards, manufacturing pipelines that enumerate finished processes, tests).

### 7. cjson mode: empty tables encode as JSON arrays

The sprint's walker sets `cjson.encode_empty_table_as_object(false)` at module load so `cvm.create_frame_0`'s `cjson.encode(caspm)` produces `[]` for empty programs instead of `{}`. At integration, this belongs somewhere shared — one obvious home is at the top of [src/engine/cvm/init.lua](https://puck.uno/src/engine/cvm/init.lua) (loaded whenever any CVM-touching code runs). The `objects_ast_valid_insert` trigger will reject a `{}`-shaped ast; the shared cjson mode is what keeps that from firing for empty programs.

### 8. `dispatch.lua`'s fate

The walker's inline handler-chain walk (`for _, handler in ipairs(self.row_handlers) do if handler:handle(...) then ... end end`) replaces the `dispatch` module's role. Two options:

- **(recommended)** Keep `dispatch.lua` as a separate module and have `run_frame` call it (like today's `M:run_row` does). Preserves the module boundary and the existing tests in [test_dispatch.lua](https://puck.uno/tests/main/lua/engine/test_dispatch.lua).
- **(alternative)** Inline the dispatch logic in `run_frame` as the sprint does; delete `dispatch.lua` and its tests. Fewer files but loses the separately-testable dispatch surface.

I'd stay with dispatch.lua as a module — the inlining was a sprint convenience, not an architectural improvement.

### 9. Rename `unrecognized_row_head` → `unrecognized_caspm`

The sprint's walker raises `unrecognized_caspm` when no handler claims a row. Shipping still uses `unrecognized_row_head` in:

- [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua) — raise site (`M:run_row`), 3 docstring mentions, module-header dispatch_contract
- [src/engine/dispatch.lua](https://puck.uno/src/engine/dispatch.lua) — raise site + 2 docstring mentions
- [src/engine/handlers/variable-scalar.lua](https://puck.uno/src/engine/handlers/variable-scalar.lua) — docstring mention
- [tests/main/lua/engine/test_dispatch.lua](https://puck.uno/tests/main/lua/engine/test_dispatch.lua) — 6 test-assertion strings and comments
- [sprints/first-variable/walkthrough.md](https://puck.uno/sprints/first-variable/walkthrough) — 1 prose mention
- [sprints/first-variable/index.md](https://puck.uno/sprints/first-variable/) — 1 prose mention

Sweep them all as part of integration.

## Test migration

The sprint's three tests move into `tests/main/lua/engine/`, adapted to the shared helpers convention (`helpers.test` / `h.assert_true` / `h.assert_eq` — no standalone runner):

- `sprints/end-to-end/tests/test_end_to_end.lua` → `tests/main/lua/engine/test_end_to_end.lua`. The flagship: empty array in → hash out.
- `sprints/end-to-end/tests/test_empty_end_to_end.lua` → `tests/main/lua/engine/test_end_to_end_state.lua` (renamed for clarity — this is the DB-state suite, not another end-to-end).
- `sprints/end-to-end/tests/test_ast_shape.lua` → `tests/main/lua/engine/test_ast_shape.lua`.

Convert each to use `helpers.test`, drop the standalone summary / os.exit, drop the manual package.path setup (the runner at [tests/main/lua/engine/run.lua](https://puck.uno/tests/main/lua/engine/run.lua) sets it).

Delete the sprint copies after the moves land and pass.

Also drop the leftover `sprints/end-to-end/tests/test_empty.lua` — that was an early diagnostic script, not a test, and its role is fully covered now.

## Existing test surgery

Several shipping tests need updating for the new Engine.run shape:

- [tests/main/lua/engine/test_basic.lua](https://puck.uno/tests/main/lua/engine/test_basic.lua) — the `engine:load(source)` tests still pass unchanged; if any test calls `engine:run()` on the base engine it will now hit the new shape. Audit.
- [tests/main/lua/engine/test_dispatch.lua](https://puck.uno/tests/main/lua/engine/test_dispatch.lua) — the 4 direct-mutation call sites already went through the row_handlers API integration. The 6 `unrecognized_row_head` references become `unrecognized_caspm`. If dispatch.lua stays, its tests are unaffected structurally.
- [tests/main/lua/engine/test_larry.lua](https://puck.uno/tests/main/lua/engine/test_larry.lua) — Larry is-a Engine tests still pass; if Larry starts using the new run shape, no additional changes needed.
- The shipping engine test suite should end up 175+ still-green tests plus the ~8 sprint tests promoted.

## Sprint doc: `trace.md`

[sprints/end-to-end/trace.md](https://puck.uno/sprints/end-to-end/trace) is a design doc showing the DB state at each step of a run. **Keeping it** (confirmed per issue #1633): promote to `documentation/requirements/cvm/frame-lifecycle.md` (or a similar location under `requirements/cvm/`) — this is settled spec now, worth having in requirements.

The file's absolute pk placeholders (`b56705d4-…`) stay as illustrative; the vibecode role updates to remove the sprint reference.

## Post-integration cleanup

- Delete `sprints/end-to-end/`.
- Any GitHub issues that referenced this sprint's design should get closed.

## Verification

After the moves, both suites must pass with no regressions:

~~~
lua5.4 tests/main/lua/engine/run.lua
~~~

Then run the empty-program end-to-end scenario against the shipping engine directly to confirm the walker shape works from `engine.new()`, not just from `StmtWalker.new()`:

~~~lua
local engine = require('engine').new()
engine:load('')
local returned = engine:run()
assert(returned.complete == 1)
assert(returned.message == nil)
~~~

## Sprint boundary

Every step above touches shipping — schema, engine.lua, tests. Requires the explicit trigger — "proceed with the integration" or "proceed with the assimilation" — before any of it lands outside the sprint dir.

## Deferred (out of scope for this integration)

Named here so nobody assumes they're covered:

- **Closure capture.** The frame-lifecycle model assumes no closure holds a frame; the design intent for closure-captured frames (frame row survives past pop) is deferred to a later sprint.
- **`unrecognized_caspm` diagnostic detail.** The shipping `run_row` reshapes the raise with the atom-keys detail appended; the sprint's inline walker doesn't. Preserve the reshape behavior at integration or explicitly drop it.
