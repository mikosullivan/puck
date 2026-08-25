--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass that swaps in the sprint's process_stop handler and wraps :run() in an xpcall that catches the HALT sentinel. Inherits everything else from production's Larry (which itself inherits from Engine). Named `stop_larry` (not `larry`) to avoid shadowing production's Larry in package.path — this module requires production's `larry` module, so a same-name collision would recurse.",
	"exports": {
		"new":    "(opts?) -> StopLarry — same signature as Larry.new; also swaps the stock ProcessStop handler for the sprint's version",
		"run":    "() -> result table — overrides Engine:run to catch the HALT sentinel; returns {stopped=1, cap_pk=...} on halt, {complete=1, cap_pk=...} on normal completion",
		"restart": "(value?) -> result table — restarts a halted process. Walks the frame chain from the process cap down to the leaf frame; if only the cap remains, raises `stop_larry_restart_process_complete`. If `value` is given, materializes a scalar of that Lua value on the leaf frame's rv so it propagates up on reap; otherwise the leaf frame reaps with a null rv. Then advances the parent past whatever it was doing when it halted, and continues walking. Returns the same result-hash shape as run()."
	},
	"depends_on": ["larry (production)", "engine (production)", "halt", "process_stop"]
}
]]

--[=[
# `larry` (sprint-scoped)

Sprint-scoped Larry subclass for the stop sprint.

**Three additions:**

1. `StopLarry.new(opts)` — calls production's `Larry.new`, then
   walks `self.row_handlers` and replaces production's ProcessStop
   handler with the sprint's version. Everything else stays wired
   as production configured it.

2. `StopLarry:run()` — wraps the parent's `Engine.run(self)` in
   `xpcall`. If the caught error is our HALT sentinel, returns a
   stopped-result hash. Anything else re-raises via `error(err, 0)`.

3. `StopLarry:restart(value?)` — restarts a halted process. Optionally
   injects a rv onto the stop frame first, then reaps the stop frame
   (triggers propagate-rv + sets_parent_gc), advances the parent
   past the %process.stop statement, and re-enters the walker to
   continue execution.
]=]

local Larry               = require('larry')
local Engine              = require('engine')
local halt                = require('halt')
local SprintProcessStop   = require('process_stop')
local ProductionProcessStop = require('handlers.process-stop')


local StopLarry = setmetatable({}, {__index = Larry})
StopLarry.__index = StopLarry


--[[
## `StopLarry.new`

Constructs a sprint-scoped Larry. Delegates to `Larry.new(opts)` for
the base setup, then rewraps the metatable and swaps the stock
ProcessStop handler.
]]
function StopLarry.new(opts)
	local instance = Larry.new(opts)
	setmetatable(instance, StopLarry)

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

Restarts a halted process. Optionally injects a value onto the stop
frame's rv slot; then reaps the stop frame and continues walking
the parent frame from just past the %process.stop statement.

Steps:

1. **Find the stop frame** — the single row with
   `engine_class='stop'`. Raises `stop_larry_restart_no_stop` if
   absent (nothing to restart).
2. **Optional rv injection** — if `value` is given, materialize a
   scalar via `engine.data:add_scalar`, ensure the stop frame has a
   bucket, and upsert the `rv` ref pointing at the scalar.
3. **Reap the stop frame.** DELETE. Two triggers fire on the parent:
   `frames_child_delete_propagates_rv` copies the stop frame's rv
   up (whatever it holds — the injected value, or null); and
   `frames_child_delete_sets_parent_gc` sets the parent's frame_gc
   to 1 (cap-exempt, but the parent here is always a nested frame
   since %process.stop can't be called from the cap).
4. **Advance the parent** past the %process.stop statement. The
   parent's frame_gc is now 1 (from step 3) so the advance is
   valid; the advance auto-nulls gc back to null via
   `frames_advance_sets_gc_null`.
5. **Drain needs_trace** to clean up any refs the reap orphaned
   before the walker's next tick.
6. **Re-enter the walker** on the parent via `Engine.run_frame`,
   wrapped in the same xpcall + halt-catch pattern as `:run()`.
   run_frame walks the remaining statements, reaps the parent
   naturally at completion, and returns.

Returns `{complete = 1, cap_pk = ...}` on normal completion of the
restarted program, `{stopped = 1, cap_pk = ...}` if the restarted
program hits another %process.stop.

Value injection uses `engine.data:add_scalar(value, owner_role)`
which is polymorphic on Lua's `type(value)` — string, number,
boolean, and nil all route to the right scalar_* column.
]]
function StopLarry:restart(value)
	local db = self.cvm

	-- 1. Walk the frame chain from the cap down to the leaf frame.
	-- Under the current design the bottom is always a stop frame
	-- (the only thing that halts a process), but this walk doesn't
	-- assume that — any leaf frame is a valid restart anchor. The
	-- chain is linear (unique(frame_parent) constraint), so a plain
	-- loop suffices.
	local leaf_pk = self.cap_pk

	while true do
		local next_pk

		for row in db:nrows(
			"select object_pk from objects where frame_parent = '" .. leaf_pk .. "'"
		) do
			next_pk = row.object_pk
		end

		if not next_pk then break end

		leaf_pk = next_pk
	end

	if leaf_pk == self.cap_pk then
		error("stop_larry_restart_process_complete: no non-cap frames present; nothing to restart")
	end

	-- Look up the parent (the frame the leaf frame's under) and its owner_role.
	local parent_pk
	local owner_role

	for row in db:nrows(
		"select frame_parent, owner_role from objects where object_pk = '" .. leaf_pk .. "'"
	) do
		parent_pk = row.frame_parent
		owner_role = row.owner_role
	end

	-- 2. Optional rv injection onto the leaf frame. The three writes
	-- (scalar row, bucket row, rv ref) land inside one savepoint so
	-- either all three commit or none of them do — a partial injection
	-- would leave a bucket without an rv (or a bucket ref to nothing)
	-- and the halt state would go inconsistent.
	if value ~= nil then
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

	-- 3. Reap the leaf frame. Triggers fire against the parent.
	local rc = db:exec(
		"delete from objects where object_pk = '" .. leaf_pk .. "'"
	)

	if rc ~= 0 then
		error("stop_larry_restart_reap_failed: " .. tostring(db:errmsg()))
	end

	-- 4. Drain the needs_trace worklist the reap populated. Must happen
	-- BEFORE the advance — the advance's auto-null-gc trigger
	-- (`frames_gc_reset_requires_empty_needs_trace`) refuses to reset
	-- gc while the current process has outstanding marks. Mirrors the
	-- ordering production's run_frame uses per statement.
	self.data:drain_needs_trace(self.cap_pk)

	-- 5. Advance parent past the %process.stop statement.
	local current_idx

	for row in db:nrows(
		"select frame_stmt_idx from objects where object_pk = '" .. parent_pk .. "'"
	) do
		current_idx = row.frame_stmt_idx
	end

	self.stmts.advance:bind_values(current_idx + 1, parent_pk)
	self.stmts.advance:step()
	self.stmts.advance:reset()

	-- 6. Re-enter the walker on the parent. Same halt-catch pattern
	-- as :run() — a nested %process.stop inside the remainder halts
	-- the same way.
	local ok, result_or_err = xpcall(
		function() return self:run_frame(parent_pk) end,
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
