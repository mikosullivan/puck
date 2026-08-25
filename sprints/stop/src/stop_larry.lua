--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass. Swaps in the sprint's process_stop handler, catches the HALT sentinel from :run(), adds a :restart_frame(frame_pk) method that recursively drills into any child before delegating to production's Engine.run_frame, and adds a :restart(value?) entry point that optionally injects a value and calls restart_frame on the top-of-stack frame. run_frame itself is NOT overridden — production's version stays untaxed. All the restart-specific behavior lives in restart_frame, and restart_frame doesn't duplicate the walker/reap loop; it delegates to Engine.run_frame for that. All SQL uses prepared statements bound with parameter values.",
	"exports": {
		"new":           "(opts?) -> StopLarry — Larry.new + sprint-scoped prepared statements + ProcessStop handler swap",
		"run":           "() -> result table — overrides Engine:run to catch the HALT sentinel",
		"restart_frame": "(frame_pk) — parallel to Engine:run_frame; if the frame has a child, recursively restart_frame the child first, drain, advance past the halted statement, then delegate to Engine.run_frame. Fresh (no-child) frames get the straight-through Engine.run_frame call.",
		"restart":       "(value?) -> result table — optional value injection onto the leaf, then restart_frame(top-of-stack) inside xpcall + halt-catch"
	},
	"prepared_statements_added_to_self.stmts": {
		"stop_find_child_of":      "select object_pk from objects where frame_parent = ?",
		"stop_get_owner_role":     "select owner_role from objects where object_pk = ?",
		"stop_insert_stop_frame":  "insert into objects (base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) select 'o', 'f', 'stop', '[]', 0, ?1, owner_role from objects where object_pk = ?1"
	},
	"depends_on": ["larry (production)", "engine (production)", "halt", "process_stop", "lsqlite3 (for SQLITE_ROW)"]
}
]]

--[=[
# `stop_larry` (sprint-scoped)

Sprint-scoped Larry subclass for the stop sprint.

**Four additions:**

1. `StopLarry.new(opts)` — Larry.new + sprint-scoped prepared
   statements + ProcessStop handler swap.

2. `StopLarry:run()` — wraps `Engine.run(self)` in xpcall + HALT
   sentinel catch. Anything else re-raises.

3. `StopLarry:restart_frame(frame_pk)` — parallel to Engine's
   run_frame. Same walker + reap behavior, plus a recursive
   pre-step: if the frame has a child, restart_frame the child
   first, drain, advance past the halted statement, then delegate
   to `Engine.run_frame`. Fresh frames (no child) skip the prelude
   and delegate straight through. The recursion is what handles
   multi-level halt chains; a stop frame under a stop frame under
   a stop frame reaps bottom-up naturally.

4. `StopLarry:restart(value?)` — the restart entry point. Optional
   value injection onto the leaf frame's rv, then `restart_frame`
   on the top-of-stack frame (cap's only child), all wrapped in
   xpcall + halt-catch.

**No walker duplication.** `restart_frame` doesn't copy the loop-
and-reap logic from `run_frame`. It sets up the descent-and-advance
prelude, then hands the actual walker work to `Engine.run_frame`.
Both methods use exactly one implementation of the walker loop:
production's.

**No feature tax on normal dispatch.** `run_frame` is untouched.
Every non-restart dispatch — the whole `run()` path, all handlers
that eventually invoke `run_frame` on a child — pays no
child-check cost. That work lives in `restart_frame`, which only
gets called by `restart()`.

**SQL policy.** All queries use prepared statements bound with
parameter values. Sprint-scoped prepared statements are added to
`self.stmts` in `StopLarry.new` (prefixed `stop_` to keep them
distinct from production's stmts). No string-interpolation of pks
into SQL.
]=]

local sqlite              = require('lsqlite3')
local Larry               = require('larry')
local Engine              = require('engine')
local halt                = require('halt')
local SprintProcessStop   = require('process_stop')
local ProductionProcessStop = require('handlers.process-stop')

-- Cached at module load; avoids a `sqlite.ROW` global lookup per step check.
local SQLITE_ROW = sqlite.ROW


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
## `StopLarry:restart_frame`

Parallel to `Engine:run_frame`. Same eventual behavior — walk the
ast, dispatch, drain, advance, reap — but with a check-and-recurse
pre-step for the halted-frame case.

**Fresh frame path.** If the frame has no child, the prelude is a
no-op and we delegate straight to `Engine.run_frame`. Behavior
identical to production's run_frame in this branch.

**Halted-frame path.** If the frame has a child (this frame paused
mid-dispatch during a previous halt, and the child is the pending
sub-frame), we drill down:

1. `self:restart_frame(child_pk)` — recursive. The child may have
   its own child; the recursion keeps going until it reaches a
   childless frame. That childless frame's Engine.run_frame call
   walks the ast (empty for the sprint's stop-frame leaf case)
   and reaps at frame end. The reap fires
   `frames_child_delete_propagates_rv` (lifting the child's rv
   to this frame) and `frames_child_delete_sets_parent_gc` (this
   frame's frame_gc → 1).
2. Drain needs_trace — the child's cascade populated it, and the
   next step's auto-null-gc trigger
   (`frames_gc_reset_requires_empty_needs_trace`) refuses to reset
   gc while marks are outstanding.
3. Advance this frame past the halted statement. Without this the
   walker loop's next dispatch would re-execute `%process.stop`
   and re-halt.

Then delegate to `Engine.run_frame` for the actual walker loop.
Production's run_frame walks the remaining statements, dispatches,
reaps this frame at completion, and its reap unwinds one more
level up the recursion.

**No walker duplication.** `restart_frame` never re-implements the
loop-and-reap logic. Every dispatch goes through
`Engine.run_frame` — production's single implementation.
]]
function StopLarry:restart_frame(frame_pk)
	local child_pk = find_child_of(self, frame_pk)

	if child_pk then
		self:restart_frame(child_pk)

		-- Drain before the advance so
		-- frames_gc_reset_requires_empty_needs_trace passes.
		self.data:drain_needs_trace(self.cap_pk)

		-- Read current stmt_idx via production's prepared statement.
		local get_idx = self.stmts.get_stmt_idx
		get_idx:bind_values(frame_pk)

		local current_idx

		if get_idx:step() == SQLITE_ROW then
			current_idx = get_idx:get_value(0)
		end

		get_idx:reset()

		-- Advance past the halted statement.
		local advance = self.stmts.advance
		advance:bind_values(current_idx + 1, frame_pk)
		advance:step()
		advance:reset()
	end

	Engine.run_frame(self, frame_pk)
end


--[[
## `StopLarry:restart`

The restart entry point. Optional value injection onto the leaf
frame's rv, then `restart_frame` on the top-of-stack frame (cap's
child), all wrapped in xpcall + halt-catch.

Steps:

1. **Find the top of the call stack** — cap's child. If cap has
   no children, the process is already complete — raise
   `stop_larry_restart_process_complete`.

2. **Optional value injection.** If `value` is given, walk from
   top to the leaf, materialize a scalar (polymorphic on Lua
   type), ensure the leaf's bucket, upsert the `rv` ref. Three
   writes wrapped in a savepoint — partial injection would leave
   the halt state inconsistent.

3. **restart_frame the top.** Inside xpcall — the recursion
   handles the descent, the reap-and-propagate chain, and the
   walker resumption. On success → `{complete=1, cap_pk=...}`.
   On HALT (re-halted during execution) → `{stopped=1,
   cap_pk=...}`. Anything else re-raises via `error(err, 0)`.
]]
function StopLarry:restart(value)
	local db = self.cvm

	-- 1. Find the top-of-stack frame (cap's child).
	local top_pk = find_child_of(self, self.cap_pk)

	if not top_pk then
		error("stop_larry_restart_process_complete: no non-cap frames present; nothing to restart")
	end

	-- 2. Optional value injection onto the leaf frame.
	if value ~= nil then
		-- Walk to the leaf.
		local leaf_pk = top_pk

		while true do
			local next_pk = find_child_of(self, leaf_pk)
			if not next_pk then break end
			leaf_pk = next_pk
		end

		-- Look up leaf's owner_role for the injected scalar.
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

	-- 3. restart_frame the top. Recursion handles the descent.
	local ok, result_or_err = xpcall(
		function() return self:restart_frame(top_pk) end,
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
