~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "frame-0",
	"role": "Integration plan for the frame-0 sprint. Enumerates what promotes to shipping, in what order, with which artifacts touched. Not the implementation itself — this file is the checklist the actual integration follows. Written when the sprint's design and code are settled but the shipping wiring has not yet happened.",
	"status": "plan only; no artifacts touched",
	"trigger_word": "integration"}
~~~

# frame-0 integration plan

Written up so integration itself is a checklist rather than a design exercise. Nothing here has landed in shipping yet — the whole sprint still lives under `sprints/frame-0/`. Executing this plan is what closes the sprint.

## What promotes

Three Lua modules, one schema fork, three test files. Full inventory:

| Sprint path | Shipping destination | Notes |
|---|---|---|
| [`sprints/frame-0/src/schema.sql`](./src/schema.sql) | [`src/engine/cvm/schema.sql`](../../src/engine/cvm/schema.sql) | Delta merge, not overwrite — see [Schema migration](#schema-migration). |
| [`sprints/frame-0/src/initialize_process.lua`](./src/initialize_process.lua) | `src/engine/cvm/initialize_process.lua` | New file. No shipping equivalent today. |
| [`sprints/frame-0/src/get_latest_frame.lua`](./src/get_latest_frame.lua) | `src/engine/cvm/get_latest_frame.lua` | New file. |
| [`sprints/frame-0/src/create_frame_0.lua`](./src/create_frame_0.lua) | `src/engine/cvm/create_frame_0.lua` | New file. Requires `cjson` — see [Dependencies](#dependencies). |
| [`sprints/frame-0/tests/test_initialize_process.lua`](./tests/test_initialize_process.lua) | `tests/main/lua/engine/test_initialize_process.lua` | Also: drop the sprint-schema pointer, retarget to the shared runner's package.path setup. |
| [`sprints/frame-0/tests/test_get_latest_frame.lua`](./tests/test_get_latest_frame.lua) | `tests/main/lua/engine/test_get_latest_frame.lua` | Same retargeting. |
| [`sprints/frame-0/tests/test_create_frame_0.lua`](./tests/test_create_frame_0.lua) | `tests/main/lua/engine/test_create_frame_0.lua` | Same retargeting. |

## Schema migration

The sprint's schema differs from shipping's on three axes. Each needs to land in shipping:

1. **`objects.idx` dropped.** Sprint removed the column entirely. Shipping's `alter table objects add column idx integer` and its check constraint need to go. **Breaking for any existing DB that has data in `idx`** — but no shipping code currently reads it (verified during the sprint).
2. **`objects.frame_parent` added.** Text FK back to `objects.object_pk`, with a check constraint (`frame_parent is null or primitive = 'f'`) and a partial index (`objects_frame_by_parent`). New column; safe additive change to fresh DBs.
3. **`processes.process_pk` → text UUID.** Was `integer primary key autoincrement`; becomes `text primary key default (<randomblob-hex UUID expression>)`. **Breaking for any existing DB with a `processes` row** — the pk type changes and existing integer pks would need conversion. `objects.process` FK column changes from `integer` to `text` to match.

Migration approach for existing shipping DBs: **fresh DBs only for now.** V1 hasn't shipped; no user-owned CVM files exist that need migration. If the promotion happens after V1, we write a one-shot migration script; this plan doesn't try to design one prematurely.

## Dependencies

`create_frame_0` requires `cjson` for the CaspM → JSON encode step. `cjson` is already a bundled core dependency — see [core § External bundle](https://puck.uno/requirements/core/) (ships as `cjson.so` under `external/`, listed among the always-loaded C bindings). No fallback pattern needed; the hard `require("cjson")` in `create_frame_0.lua` is correct.

## Engine wiring

Shipping's `M:run` currently walks `self.caspm` directly with no frame push. After integration, it needs to invoke either `create_frame_0` (fresh case) or `get_latest_frame` (revival case) before dispatching.

**Fresh vs revival signal: slot on the engine.** Consistent with how the engine's other host wiring works.

~~~lua
engine.process_pk = 'some-uuid'
engine:run()                              -- revival (slot set)

-- or:
engine:run()                              -- fresh (slot nil / unset)
~~~

Matches the `stdout` / `debugger` / `transpiler` slot pattern — set a field on the engine, then call the method. Host state co-locates. `run()`'s signature stays no-arg. Rejected alternative was a parameter on `run()` — decision favored the slot for consistency.

**Slot has to be added to `M.new()`** alongside the existing slots so it exists nil-by-default on every fresh engine:

~~~lua
return setmetatable({
    cvm        = cvm.open(opts.cvm),
    stdout     = nil,
    debugger   = nil,
    transpiler = transpiler,
    process_pk = nil,     -- NEW: revival pk, or nil for fresh
    caspm      = nil,
}, M)
~~~

Plus a bullet in the constructor docstring describing what `process_pk` means (host sets before `run()` for revival; leaves nil for fresh).

Approximate shape of the reworked `M:run`:

~~~lua
function M:run()
    if not self.caspm then
        error("engine:run() called before engine:load(); no program to execute")
    end

    local result = {}

    -- Fresh vs revival. Set up frame 0's resume pk.
    local frame_pk

    if self.process_pk then
        frame_pk = get_latest_frame(self.cvm, self.process_pk)
    else
        frame_pk = create_frame_0(self.cvm, self)
    end

    -- If frame_pk is nil, the process is done — dispatch has nothing to
    -- walk. Naturally a no-op.
    if frame_pk then
        -- Fetch the frame's ast from the DB and dispatch from it.
        local ast_stmt = self.cvm:prepare(
            "select ast from objects where object_pk = ?"
        )
        ast_stmt:bind_values(frame_pk)

        local ast_json

        for row in ast_stmt:nrows() do
            ast_json = row.ast
        end

        ast_stmt:reset()

        for _, row in ipairs(cjson.decode(ast_json)) do
            self:run_row(row)
        end
    end

    -- Last chance to read from the database before the connection scope ends.

    return result
end
~~~

**Dispatch reads from the DB frame's `ast`, not `self.caspm`.** The pushed frame is now the source of truth for what gets executed. `self.caspm` still exists as the input-staging slot (the caller writes it via `load()`; `create_frame_0` reads it and JSON-encodes it into the frame's `ast`), but once the frame exists the DB is authoritative. This closes the walking-skeleton ambiguity where the frame push was a side effect the dispatch didn't consult.

## Requirements updates

- **[requirements/bootstrap/stage/set-up-frame-0/](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/)** — already carries the [transpilation-happens-here note](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/#this-is-where-transpilation-happens) from the alternate-transpiler sprint's promotion. Confirm the SQL in "The insert" section matches the sprint's final column list (verify no `idx = 0`, since sprint dropped `idx`).
- **[requirements/bootstrap/initialize-vm/initialize-process-record/](https://puck.uno/requirements/bootstrap/initialize-vm/initialize-process-record/)** — the sprint moved the process-record creation OUT of Initialize VM and INTO Create Frame 0's fresh branch. Requirements doc for that sub-step needs to reflect the move (either archived or reframed as "deferred to Set up frame 0's fresh branch — see there").
- **[requirements/bootstrap/initialize-vm/](https://puck.uno/requirements/bootstrap/initialize-vm/)** — drops from four sub-steps to three (Open the DB, Install infrastructure, Return the CVM handle).
- **[requirements/cvm/](https://puck.uno/requirements/cvm/)** — reflect the schema changes (idx dropped, frame_parent added, process_pk as text UUID).

## Test promotion

Sprint tests reference paths like `sprints/frame-0/src/?.lua` and `SCHEMA_PATH = "sprints/frame-0/src/schema.sql"`. On promotion:

- Change `package.path` prepending to match the shared runner's shape (`src/engine/?.lua` or via the runner's setup).
- Remove `SCHEMA_PATH` locals; the shared runner sets up schema application via `cvm.open()`.
- Convert standalone runners into modules the shared runner (`tests/main/lua/engine/run.lua`) picks up automatically via its `test_*.lua` discovery.

## Order of operations

1. Merge schema deltas into shipping schema. Fresh-DB-only migration policy for now.
2. Move the three Lua modules into `src/engine/cvm/`. `initialize_process.lua` and `get_latest_frame.lua` are pure file moves (no functional change). `create_frame_0.lua` needs two behavior fixes as part of the move:
   - **Switch from `begin;`/`commit;` to `savepoint`/`release savepoint`.** V1 ships user-facing transactions, so `create_frame_0` will get called inside a user's `begin;`/`commit;`. Naked `begin;` inside a user transaction either errors (nested begin refused) or is treated as a no-op, in which case the internal `commit;` prematurely commits the user's outer transaction — silent corruption of the user's atomicity. Savepoints compose in both directions.
   - **`pcall` wrap + `rollback to savepoint` on error.** So a raise in any step doesn't leave the savepoint open on the connection. Re-raise the original error after rollback so the caller still sees what happened.
3. Add the `process_pk` slot to shipping's `M.new()` (nil-by-default, docstring bullet).
4. Rework shipping's `M:run` to invoke `create_frame_0` / `get_latest_frame` per the fresh-vs-revival decision AND to dispatch from the DB frame's `ast` (fetch, JSON-decode, iterate) rather than `self.caspm`.
5. Move test files into `tests/main/lua/engine/`; retarget package paths and schema references. Existing engine tests that assert on dispatch behavior may need updating to reflect that dispatch source is now the DB frame — audit for tests that construct engines and call `run()` expecting dispatch over `self.caspm`.
6. Run the full shipping test suite. All 127 pre-integration tests + 22 sprint tests should pass — 149 total, zero regressions.
7. Update the requirements/ docs enumerated above.
8. Delete `sprints/frame-0/` (or archive if you want the paper trail).
9. Commit as a single unit ("frame-0 sprint integration") so the shipping change is traceable back to this plan.

## Status

**Plan captured. No artifacts touched.** Waiting on the integration trigger.
