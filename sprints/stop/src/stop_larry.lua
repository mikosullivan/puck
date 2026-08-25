--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass that swaps in the sprint's process_stop handler, catches the HALT sentinel from :run(), and adds a :restart(value?) method for continuing a halted process. `run_frame` is NOT overridden — production's version stays untaxed. The restart-specific descent + reap + advance work all lives inside restart() itself, so a normal run pays no feature tax for the rare restart case. Named `stop_larry` (not `larry`) to avoid shadowing production's Larry in package.path. All SQL uses prepared statements bound with parameter values.",
	"exports": {
		"new":       "(opts?) -> StopLarry — same signature as Larry.new; also swaps the stock ProcessStop handler for the sprint's version and prepares sprint-scoped SQL under self.stmts",
		"run":       "() -> result table — overrides Engine:run to catch the HALT sentinel; returns {stopped=1, cap_pk=...} on halt, {complete=1, cap_pk=...} on normal completion",
		"restart":   "(value?) -> result table — restarts a halted process. Walks the frame chain to find the leaf; if optional `value` is given, materializes a scalar on the leaf's rv (three writes wrapped in a savepoint). Then reaps the leaf (fires propagate-rv on the parent), drains, advances the parent past the halted statement, and re-enters the walker on the parent via run_frame."
	},
	"prepared_statements_added_to_self.stmts": {
		"stop_find_child_of":      "select object_pk from objects where frame_parent = ?",
		"stop_get_owner_role":     "select owner_role from objects where object_pk = ?",
		"stop_get_frame_parent":   "select frame_parent from objects where object_pk = ?",
		"stop_delete_object":      "delete from objects where object_pk = ?",
		"stop_insert_stop_frame":  "insert into objects (base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) select 'o', 'f', 'stop', '[]', 0, ?1, owner_role from objects where object_pk = ?1"
	},
	"depends_on": ["larry (production)", "engine (production)", "halt", "process_stop", "lsqlite3 (for SQLITE_ROW)"]
}
]]

--[=[
# `stop_larry` (sprint-scoped)

Sprint-scoped Larry subclass for the stop sprint.

**Three additions:**

1. `StopLarry.new(opts)` — calls production's `Larry.new`, prepares
   sprint-scoped SQL under `self.stmts`, then swaps the stock
   ProcessStop handler for the sprint's version.

2. `StopLarry:run()` — wraps the parent's `Engine.run(self)` in
   `xpcall`. If the caught error is our HALT sentinel, returns a
   stopped-result hash. Anything else re-raises via `error(err, 0)`.

3. `StopLarry:restart(value?)` — the restart action. Walks to the
   leaf, optionally injects a value on its rv, reaps the leaf,
   drains, advances the parent past the halted statement, and
   re-enters the walker on the parent via `Engine.run_frame`.

**Feature-tax note.** `run_frame` is not overridden. Every non-restart
dispatch (the normal `run()` path, or any handler that eventually
calls `run_frame` on a child) uses production's implementation
directly. The restart-specific work is confined to `restart()`.
Deeper frame nesting would need `restart()` to unwind the chain
one level at a time; the sprint's one-level halt model doesn't
require it.

**SQL policy.** All queries use prepared statements bound with
parameter values. Sprint-scoped prepared statements are added to
`self.stmts` in `StopLarry.new` (prefixed `stop_` to keep them
distinct from production's stmts). No string-interpolation of pks
into SQL — that opens a SQL-injection hole.
]=]

local sqlite              = require('lsqlite3')
local Larry               = require('larry')
local Engine              = require('engine')
local halt                = require('halt')
local SprintProcessStop   = require('process_stop')
local ProductionProcessStop = require('handlers.process-stop')

-- Cached at module load; avoids a `sqlite.ROW` global lookup per step check.
local SQLITE_ROW  = sqlite.ROW
local SQLITE_DONE = sqlite.DONE


local StopLarry = setmetatable({}, {__index = Larry})
StopLarry.__index = StopLarry


--[[
## `StopLarry.new`

Constructs a sprint-scoped Larry. Delegates to `Larry.new(opts)` for
the base setup, rewraps the metatable, prepares sprint-scoped SQL
statements under `self.stmts`, and swaps production's stock
ProcessStop handler for the sprint's version.
]]
function StopLarry.new(opts)
	local instance = Larry.new(opts)
	setmetatable(instance, StopLarry)

	-- Sprint-scoped prepared statements. Prefixed `stop_` to avoid
	-- collision with production's stmts. Compile once here; every
	-- use below is bind_values + step/nrows + reset.
	instance.stmts.stop_find_child_of = instance.cvm:prepare(
		"select object_pk from objects where frame_parent = ?"
	)

	instance.stmts.stop_get_owner_role = instance.cvm:prepare(
		"select owner_role from objects where object_pk = ?"
	)

	instance.stmts.stop_get_frame_parent = instance.cvm:prepare(
		"select frame_parent from objects where object_pk = ?"
	)

	instance.stmts.stop_delete_object = instance.cvm:prepare(
		"delete from objects where object_pk = ?"
	)

	-- Insert the stop frame as a child of the current frame. Owner_role
	-- inherits from the current frame via the SELECT — one parameter,
	-- referenced twice via ?1. Called from the sprint's ProcessStop
	-- handler at %process.stop-dispatch time.
	instance.stmts.stop_insert_stop_frame = instance.cvm:prepare(
		"insert into objects "
		.. "(base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) "
		.. "select 'o', 'f', 'stop', '[]', 0, ?1, owner_role "
		.. "from objects where object_pk = ?1"
	)

	-- Swap production's ProcessStop for the sprint's. Identify by
	-- metatable-identity check (each Handler subclass sets its own
	-- metatable in .new()).
	for i, handler in ipairs(instance.row_handlers) do
		if getmetatable(handler) == ProductionProcessStop then
			instance.row_handlers[i] = SprintProcessStop.new()
			break
		end
	end

	return instance
end


--[[
## `find_child_of` — helper

Returns the object_pk of the given frame's single child (or nil if
none). Wraps the `stop_find_child_of` prepared statement.
]]
local function find_child_of(self, frame_pk)
	local stmt = self.stmts.stop_find_child_of
	stmt:bind_values(frame_pk)

	local child_pk

	if stmt:step() == SQLITE_ROW then
		child_pk = stmt:get_value(0)
	end

	stmt:reset()

	return child_pk
end


--[[
## `StopLarry:run`

Overrides `Engine:run` to catch the HALT sentinel. Wraps the
parent's run in `xpcall`; on catch, checks whether the error is our
sentinel and returns the appropriate result hash.

**Re-raise everything else.** Any error that isn't our HALT gets
re-raised via `error(err, 0)` — the caller (test, host program)
sees the original exception with its original stack trace.
]]
function StopLarry:run()
	local ok, result_or_err = xpcall(
		function() return Engine.run(self) end,
		function(err) return err end
	)

	if ok then
		return result_or_err
	end

	if halt.is_halt(result_or_err) then
		return {stopped = 1, cap_pk = self.cap_pk}
	end

	error(result_or_err, 0)
end


--[[
## `StopLarry:restart`

Restarts a halted process. All the work happens here so that a
non-restart dispatch pays no per-call tax.

Steps:

1. **Walk the frame chain from the cap down to the leaf** — the
   frame at the bottom, where the process was paused. If the walk
   never moves (cap has no children), the process is complete —
   raise `stop_larry_restart_process_complete`.

2. **Look up the leaf's parent + owner_role.** Parent is the frame
   the reap will propagate rv up to (and whose halted statement we
   need to advance past); owner_role is for the injected scalar.

3. **Optional value injection** onto the leaf. If `value` is given,
   materialize a scalar (polymorphic on Lua type), ensure the leaf's
   bucket, upsert the `rv` ref. Three writes wrapped in a
   savepoint — partial injection would leave the halt state
   inconsistent.

4. **Reap the leaf.** DELETE. Two triggers fire on the parent:
   - `frames_child_delete_propagates_rv` copies the leaf's rv up
     (whatever it holds — the injected value, or null).
   - `frames_child_delete_sets_parent_gc` sets the parent's
     frame_gc to 1 (cap-exempt, but the parent here is a nested
     frame since %process.stop can't be called from the cap).

5. **Drain needs_trace** before the advance. The advance's
   auto-null-gc trigger (`frames_gc_reset_requires_empty_needs_trace`)
   refuses to reset gc while marks are outstanding.

6. **Advance the parent** past the halted statement. Parent's gc=1
   from step 4 satisfies `frames_advance_requires_gc`; the AFTER
   trigger auto-nulls gc.

7. **Re-enter the walker** on the parent via `Engine.run_frame`,
   wrapped in the same xpcall + halt-catch pattern as `:run()`. From
   here production's walker takes over: dispatches remaining
   statements, reaps at frame end, propagate-rv unwinds up to the
   cap.

**Scope note.** This works for one level of frame nesting (the
current halt model — %process.stop creates a single stop frame
directly under its calling frame). Deeper nesting would require
step 4-6 to unwind more than one level; that's future work.
]]
function StopLarry:restart(value)
	local db = self.cvm

	-- 1. Walk to the leaf frame (or fail if the process is complete).
	local leaf_pk = self.cap_pk

	while true do
		local next_pk = find_child_of(self, leaf_pk)
		if not next_pk then break end
		leaf_pk = next_pk
	end

	if leaf_pk == self.cap_pk then
		error("stop_larry_restart_process_complete: no non-cap frames present; nothing to restart")
	end

	-- 2. Look up the parent (target of the reap's triggers) and the
	-- leaf's owner_role (for the injected scalar, if any).
	local get_parent = self.stmts.stop_get_frame_parent
	get_parent:bind_values(leaf_pk)

	local parent_pk

	if get_parent:step() == SQLITE_ROW then
		parent_pk = get_parent:get_value(0)
	end

	get_parent:reset()

	-- 3. Optional value injection onto the leaf frame.
	if value ~= nil then
		local get_owner = self.stmts.stop_get_owner_role
		get_owner:bind_values(leaf_pk)

		local owner_role

		if get_owner:step() == SQLITE_ROW then
			owner_role = get_owner:get_value(0)
		end

		get_owner:reset()

		assert(db:exec('savepoint restart_inject_rv;') == 0, db:errmsg())

		local ok, err = pcall(function()
			local scalar_pk = self.data:add_scalar(value, owner_role)
			local bucket_pk = self.data:add_bucket(leaf_pk)
			self.data:upsert_ref(bucket_pk, 'rv', scalar_pk)
		end)

		if not ok then
			db:exec('rollback to savepoint restart_inject_rv;')
			db:exec('release savepoint restart_inject_rv;')
			error(err, 0)
		end

		assert(db:exec('release savepoint restart_inject_rv;') == 0, db:errmsg())
	end

	-- 4. Reap the leaf. Triggers fire against the parent.
	local delete_stmt = self.stmts.stop_delete_object
	delete_stmt:bind_values(leaf_pk)

	local rc = delete_stmt:step()
	delete_stmt:reset()

	if rc ~= SQLITE_DONE then
		error("stop_larry_restart_reap_failed: " .. tostring(db:errmsg()))
	end

	-- 5. Drain before the advance so
	-- frames_gc_reset_requires_empty_needs_trace passes.
	self.data:drain_needs_trace(self.cap_pk)

	-- 6. Advance parent past the halted statement.
	local get_idx = self.stmts.get_stmt_idx
	get_idx:bind_values(parent_pk)

	local current_idx

	if get_idx:step() == SQLITE_ROW then
		current_idx = get_idx:get_value(0)
	end

	get_idx:reset()

	local advance = self.stmts.advance
	advance:bind_values(current_idx + 1, parent_pk)
	advance:step()
	advance:reset()

	-- 7. Re-enter the walker on the parent. Production's run_frame,
	-- unchanged. Same halt-catch pattern as :run() — a subsequent
	-- %process.stop halts the same way.
	local ok, result_or_err = xpcall(
		function() return Engine.run_frame(self, parent_pk) end,
		function(err) return err end
	)

	if ok then
		return {complete = 1, cap_pk = self.cap_pk}
	end

	if halt.is_halt(result_or_err) then
		return {stopped = 1, cap_pk = self.cap_pk}
	end

	error(result_or_err, 0)
end


return StopLarry
