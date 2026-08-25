--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass that swaps in the sprint's process_stop handler, catches the HALT sentinel from :run(), and overrides :run_frame to recurse into any existing child before dispatching. The recursion is what makes restart work: `restart()` optionally injects a rv on the leaf, then calls run_frame on the top-of-stack frame; the override drills down through any pending child, reaps it, and unwinds back up. Named `stop_larry` (not `larry`) to avoid shadowing production's Larry in package.path. All SQL uses prepared statements bound with parameter values — same rule production's engine follows, and no interpolation of pks into SQL strings.",
	"exports": {
		"new":       "(opts?) -> StopLarry — same signature as Larry.new; also swaps the stock ProcessStop handler for the sprint's version and prepares sprint-scoped SQL under self.stmts",
		"run":       "() -> result table — overrides Engine:run to catch the HALT sentinel; returns {stopped=1, cap_pk=...} on halt, {complete=1, cap_pk=...} on normal completion",
		"run_frame": "(frame_pk) — overrides Engine:run_frame with a pre-recurse: if the frame has a child, run_frame the child first, drain, advance past the halted statement, THEN delegate to Engine.run_frame for the normal walker loop. On a fresh frame with no child the override is a straight-through call to Engine.run_frame.",
		"restart":   "(value?) -> result table — restarts a halted process. Optionally materializes a scalar of `value` on the leaf frame's rv (three writes wrapped in a savepoint). Then calls run_frame on the top-of-stack frame (cap's only child). The override's child-recursion handles the drill-down."
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

**Four overrides / additions:**

1. `StopLarry.new(opts)` — calls production's `Larry.new`, prepares
   sprint-scoped SQL under `self.stmts`, then swaps the stock
   ProcessStop handler for the sprint's version.

2. `StopLarry:run()` — wraps the parent's `Engine.run(self)` in
   `xpcall`. If the caught error is our HALT sentinel, returns a
   stopped-result hash. Anything else re-raises via `error(err, 0)`.

3. `StopLarry:run_frame(frame_pk)` — overrides Engine's run_frame
   with a check-and-recurse pre-step: if this frame has a child,
   run_frame the child first. The child bottoms out at the leaf,
   reaps, and via propagate-rv + sets_parent_gc leaves us with
   rv set and gc=1 on this frame. Then drain + advance past the
   halted statement so the walker doesn't re-dispatch it. Only
   then delegate to Engine.run_frame for the normal walker loop.

4. `StopLarry:restart(value?)` — the whole restart action. Walks
   to find the leaf (for optional value injection), then calls
   run_frame on the top-of-stack frame (cap's child). The
   run_frame override's recursion handles everything else.

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
## `StopLarry:run_frame`

Overrides Engine's run_frame with a check-and-recurse pre-step.

**Fresh frame path.** If the frame has no child (the common case —
fresh dispatch of frame 0 during `run()`, or any frame that hasn't
halted), the check falls through immediately and we delegate
straight to `Engine.run_frame` for its normal walker loop. Zero
behavioral change from production.

**Halted-frame path.** If the frame has a child (this frame paused
mid-dispatch during a previous halt, and the child is the pending
sub-frame), recursion drills down. The child's own run_frame may
recurse further; eventually the recursion bottoms out at a terminal
leaf (a stop frame under our current halt model — empty ast,
stmt_idx=0). Engine.run_frame on the leaf immediately breaks the
walker loop and reaps. The reap fires the schema's two child-delete
triggers:

- `frames_child_delete_propagates_rv` writes whatever rv the child
  held to this frame's rv slot (materializing this frame's bucket
  on demand if needed).
- `frames_child_delete_sets_parent_gc` sets this frame's
  `frame_gc = 1`.

After recursion returns, we've got rv set and gc=1. Two mechanical
follow-ups before we can safely re-enter the walker on this frame:

1. **Drain needs_trace.** The child's cascade populated
   needs_trace; the advance's auto-null-gc trigger
   (`frames_gc_reset_requires_empty_needs_trace`) refuses to reset
   gc while the current process has outstanding marks.

2. **Advance past the halted statement.** The paused `stmt_idx` is
   still pointing at whatever statement caused the halt (the
   `%process.stop` call). If we don't advance, the walker loop's
   next dispatch would re-execute that statement and re-halt. The
   advance moves stmt_idx forward one and auto-nulls gc via
   `frames_advance_sets_gc_null`.

Then delegate to Engine.run_frame. From here the walker loop iterates
over the remaining statements (starting from the advanced position),
dispatches each, and reaps this frame at the end — which fires the
same triggers on THIS frame's parent, unwinding one level up the
recursion.

**Scope note.** The check is at the top of run_frame, once per call.
That's sufficient under this sprint because %process.stop is the
only handler that spawns a child, and it raises HALT immediately —
control never returns to the walker loop, so there's no "child
spawned mid-loop" case to handle. Future sprints where handlers
spawn children without halting (real method-call dispatch, etc.)
will need per-iteration checks.
]]
function StopLarry:run_frame(frame_pk)
	local child_pk = find_child_of(self, frame_pk)

	if child_pk then
		-- Recurse into the child. It bottoms out at the leaf, reaps,
		-- and via propagate-rv + sets_parent_gc leaves this frame
		-- with rv set and gc=1.
		self:run_frame(child_pk)

		-- Drain before the advance so frames_gc_reset_requires_empty_needs_trace
		-- passes.
		self.data:drain_needs_trace(self.cap_pk)

		-- Read the current stmt_idx via production's prepared statement.
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

	-- Delegate to Engine.run_frame for the normal walker loop.
	Engine.run_frame(self, frame_pk)
end


--[[
## `StopLarry:restart`

Restarts a halted process. Optional value injection first; then
run_frame on the top-of-stack frame (cap's child). The run_frame
override's recursion drills down to the leaf and unwinds naturally.

Steps:

1. **Find the leaf frame** — walk `frame_parent` chain from
   `cap_pk` down. If the walk never moves (cap has no children),
   the process is complete — raise
   `stop_larry_restart_process_complete`.

2. **Optional value injection.** If `value` is given, materialize
   a scalar (polymorphic on Lua type), ensure the leaf's bucket,
   upsert the `rv` ref. Three writes inside a savepoint —
   partial injection would leave the halt state inconsistent.

3. **Find the top of the call stack** (cap's only child; guaranteed
   to exist since we didn't hit the process-complete branch).

4. **Run it.** `self:run_frame(top_pk)` inside an xpcall. The
   override's recursion handles the descent.
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

	-- 2. Optional value injection onto the leaf frame.
	if value ~= nil then
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

	-- 3. Find the top-of-stack frame (cap's child).
	local top_pk = find_child_of(self, self.cap_pk)

	-- 4. Run it. run_frame override recurses into any child.
	local ok, result_or_err = xpcall(
		function() return self:run_frame(top_pk) end,
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
