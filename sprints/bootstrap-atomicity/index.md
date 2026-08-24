~~~vibecode
{"doc": "sprint-index", "sprint": "bootstrap-atomicity",
	"role": "Wrap the cap+frame-0 creation at the top of `engine:run()` in a single savepoint so the two INSERTs commit-or-rollback together. Fixes a spec/code drift — the bootstrap-stage spec at [set-up-frame-0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/) says 'both inside the same savepoint so a mid-flight crash can't leave a cap with no frame under it,' but the current [engine.lua](https://puck.uno/production/src/engine/engine.lua) runs the two INSERTs as separate auto-committed statements. If insert_frame_0 fails (e.g., the ast_valid_insert trigger rejects a non-array frame_ast, or any downstream INSERT trigger raises), an orphaned cap is left in the DB.",
	"status": "brainstorm — problem captured, fix identified, not yet implemented"}
~~~

# bootstrap-atomicity

Wrap the cap+frame-0 creation at the top of `engine:run()` in a single savepoint. Small change; closes a spec/code drift; prevents orphaned caps.

## The problem

The engine's boot sequence creates two objects rows to seed a process: the cap, then frame 0 underneath it. Under the current code these are two separate auto-committed statements:

- [engine.lua:277-280](https://puck.uno/production/src/engine/engine.lua) — `insert_cap`, auto-commits.
- [engine.lua:285-300](https://puck.uno/production/src/engine/engine.lua) — `insert_frame_0`, auto-commits.

Nothing between them. If `insert_frame_0` raises (or the SQLite connection dies mid-flight), the cap is already committed and stays behind — an orphaned cap with no frame under it. Not corrupt; just an unusable process row that nothing will ever collect.

## The spec

[production/requirements/bootstrap/stage/set-up-frame-0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/) — updated during the numbers sprint — already says the atomicity is required:

> Fresh runs create both inside the same savepoint so a mid-flight crash can't leave a cap with no frame under it.

Spec says savepoint-wrapped; code doesn't. Straightforward drift.

## Failure modes the fix prevents

- **`ast_valid_insert` trigger rejecting a non-array `frame_ast`.** If a caller passes garbage as CaspM (or a normalizer bug produces a non-array), the cap has already committed by the time the frame_0 INSERT fires. The rejection unwinds nothing; the cap stays.
- **Any other INSERT trigger raising** on frame_0's shape (owner_role FK to a deleted role, etc.).
- **Connection dying between the two INSERTs** — process crash, SQLite lock timeout, disk full mid-write. Cap committed; frame_0 never got there.

Under a savepoint wrap, all three cases roll back cleanly — no orphaned cap.

## The fix

Small change in `engine:run()`. Bracket the two INSERTs with SAVEPOINT / RELEASE, with a ROLLBACK on any error path:

~~~lua
self.cvm:exec('savepoint bootstrap')

local ok, err = pcall(function()
	-- existing insert_cap statement
	-- existing insert_frame_0 statement
end)

if not ok then
	self.cvm:exec('rollback to savepoint bootstrap')
	self.cvm:exec('release savepoint bootstrap')
	error(err)
end

self.cvm:exec('release savepoint bootstrap')
~~~

Same pattern already used at [frame.lua:168-188](https://puck.uno/production/src/engine/cvm/sqlite/frame.lua) for `set_local_to_scalar`. Copy the shape.

## Test approach

Force `insert_frame_0` to fail deterministically and verify the cap is not left behind. Two ways to force the failure:

- **Bad CaspM.** Load a program whose CaspM ends up as a non-array (e.g., a normalizer bug or a hand-crafted engine test that bypasses `load()` and sets `engine.caspm` to a hash). The `ast_valid_insert` trigger rejects the INSERT.
- **Broken trigger.** Install a test-only BEFORE INSERT trigger on `objects` that rejects any INSERT with `control='f' and frame_parent is not null` (i.e., rejects frame 0 but not the cap). Cleaner isolation of the intended failure.

Assertion after the failure: `select count(*) from objects where control='f' and frame_process_cap = 1` returns zero. No leftover cap.

## What this sprint doesn't touch

- The trigger table stays as-is; no schema changes.
- Handler behavior after boot is unchanged.
- Revival semantics (revival opens an existing DB and finds an existing cap) aren't affected — the atomicity concern is fresh-run-specific.

## Related

- [production/src/engine/engine.lua:260-300](https://puck.uno/production/src/engine/engine.lua) — the `run()` method that needs the wrap.
- [production/src/engine/cvm/sqlite/frame.lua:150-190](https://puck.uno/production/src/engine/cvm/sqlite/frame.lua) — existing savepoint pattern to mirror.
- [production/requirements/bootstrap/stage/set-up-frame-0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/) — spec that already requires the atomicity.
- [production/requirements/bootstrap/stage](https://puck.uno/requirements/bootstrap/stage/) — parent spec covering the whole bootstrap stage.
