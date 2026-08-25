--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass. Overrides :run and :run_frame end-to-end; overrides :process_stop to insert a stop frame + raise HALT (production's default just sets self.stopped); adds :restart_frame. Under the unified design there is no separate `restart` method — run is the single entry point for both first-time execution and continuation-after-halt (with an optional restart_value for injecting a reply into a %process.stop leaf). Restart is a general resume mechanism — it works on any process paused in a valid DB state, whether the pause came from an intentional %process.stop or an unclean shutdown (crash, pulled plug). The algorithm operates on graph structure (`frame_parent`, `frame_gc`), NOT on `engine_class = 'stop'` — a crash leaves no stop marker to find (engine_class='stop' only matters as a precondition on value injection, not on the restart machinery itself). The database is always in a valid state after every transaction; that invariant is what makes crash-recovery indistinguishable from stop-recovery at this layer. All SQL uses prepared statements bound with parameter values.",
	"exports": {
		"new":           "(opts?) -> StopLarry — Larry.new + sprint-scoped prepared statements",
		"run":           "(restart_value?) -> result table — the one entry point for driving a process. First call after :load() bootstraps cap + frame 0; subsequent calls continue an existing process (halted at a stop frame, at a crash-restart chain, etc.). Optional restart_value is materialized as the leaf's rv before the descent — only valid when the leaf is engine_class='stop' (raises stop_larry_inject_requires_stop_frame otherwise). xpcall + HALT-catch wraps the whole call.",
		"run_frame":     "(frame_pk, role_pk?) — overrides Engine:run_frame. Deltas from production: (a) no self.stopped checks (HALT-as-sentinel means the flag never flips), (b) missing ast raises run_frame_no_ast instead of silently returning, (c) no tail drain (parent's run-gc step handles cascade sweep via sets_parent_gc). Optional role_pk skips the role_by_pk lookup when the caller already knows it (future spawning-handlers).",
		"process_stop":  "() -> raises HALT — overrides Engine:process_stop. Inserts a stop frame under self.current_frame_pk (via the stop_insert_stop_frame prepared statement), then raises the HALT sentinel. HALT unwinds through run_row + run_frame + restart_frame, caught by :run's xpcall.",
		"restart_frame": "(frame_pk) — parallel to run_frame. Two independent pre-steps then delegate: (a) if the frame has a child, recursively restart_frame the child first; (b) if the frame is in gc state (frame_gc = 1), run gc and advance stmt_idx. Then self:run_frame handles the rest."
	},
	"prepared_statements_added_to_self.stmts": {
		"stop_find_child_of":      "select object_pk from objects where frame_parent = ?",
		"stop_get_frame_gc":       "select frame_gc from objects where object_pk = ?",
		"stop_get_owner_role":     "select owner_role from objects where object_pk = ?",
		"stop_get_engine_class":   "select engine_class from objects where object_pk = ?",
		"reap_frame":         "delete from objects where object_pk = ? and frame_process_cap is null — the `frame_process_cap is null` clause makes the reap a silent no-op on caps, so the cap survives its own run_frame at terminal state",
		"stop_insert_stop_frame":  "insert into objects (base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) select 'o', 'f', 'stop', '[]', 0, ?1, owner_role from objects where object_pk = ?1"
	},
	"depends_on": ["larry (production)", "engine (production)", "halt", "lsqlite3 (for SQLITE_ROW / SQLITE_DONE)"]
}
]]

--[=[
# `stop_larry` (sprint-scoped)

Sprint-scoped Larry subclass for the stop sprint.

**Three overrides and two additions:**

1. `StopLarry.new(opts)` — Larry.new + sprint-scoped prepared
   statements. No handler swap: `%process.stop` is dispatched by
   `Engine:run_row` to `Engine:process_stop`, which this class
   overrides directly (see below).

2. `StopLarry:run(restart_value?)` — the one entry point for
   driving a process. Overrides `Engine:run` end-to-end (does not
   wrap it). First call after `:load()` bootstraps cap + frame 0;
   subsequent calls continue an existing process (halted at a stop
   frame, halted at a crash-restart chain, etc.). Optional
   `restart_value` is materialized as the leaf's rv before the
   descent — only valid when the leaf is `engine_class='stop'`.
   Wraps the actual work in xpcall + HALT-catch.

3. `StopLarry:run_frame(frame_pk)` — overrides `Engine:run_frame`.
   Deltas from production: no `self.stopped` checks; missing ast
   raises `run_frame_no_ast`; no tail drain (parent's run-gc step
   sweeps the child's cascade marks).

4. `StopLarry:process_stop()` — overrides `Engine:process_stop`.
   Called by `Engine:run_row` on `%process.stop` dispatch. Inserts
   a stop frame under the current frame, then raises HALT. HALT
   unwinds through the recursion back to :run's xpcall.

5. `StopLarry:restart_frame(frame_pk)` — parallel to `run_frame`.
   Handles the two independent resume-time concerns, then
   delegates the walker/reap loop to `self:run_frame`:

   - **Descend into any child.** If the frame has a child (this
     frame is somewhere in a halt chain), recursively restart the
     child first. The recursion unwinds bottom-up: leaf reaps,
     each reap fires `frames_child_delete_sets_parent_gc` and
     puts this frame into gc state.
   - **Run gc + advance if in gc state.** If `frame_gc = 1`
     (either from a child's reap during the recursion, or from a
     leaf handler that dispatched-then-halted with gc pre-set),
     run gc + advance stmt_idx (which auto-nulls gc). Frame now
     looks fresh to the walker.
   - **Delegate to `self:run_frame`.** From here on, standard
     walker work.

**No walker duplication.** `restart_frame` doesn't copy the
loop-and-reap logic from `run_frame`. It sets up whatever
pre-steps this frame needs, then hands the walker work to
`self:run_frame`. Both methods use exactly one implementation of
the walker loop: the sprint's `run_frame`.

**SQL policy.** All queries use prepared statements bound with
parameter values. Sprint-scoped prepared statements are added to
`self.stmts` in `StopLarry.new` (prefixed `stop_` to keep them
distinct from production's stmts). The one exception is
`reap_frame`, which deliberately overwrites production's handle
with the sprint's cap-skip variant — that behavior isn't
stop-sprint-specific and the shared name reflects that. No
string-interpolation of pks into SQL.
]=]

local sqlite              = require('lsqlite3')
local cjson               = require('cjson')
local Larry               = require('larry')
local Engine              = require('engine')
local halt                = require('halt')

-- Cached at module load; avoids per-call global lookups.
local SQLITE_ROW  = sqlite.ROW
local SQLITE_DONE = sqlite.DONE


local StopLarry = setmetatable({}, {__index = Larry})
StopLarry.__index = StopLarry


--[[
## `StopLarry.new`

Constructs a sprint-scoped Larry. Delegates to `Larry.new(opts)` for
the base setup, rewraps the metatable, and prepares sprint-scoped
SQL statements under `self.stmts`. Under the current design there's
no handler swap — `%process.stop` is dispatched by `Engine:run_row`
to `Engine:process_stop`, which this class overrides directly.
]]
function StopLarry.new(opts)
	local instance = Larry.new(opts)
	setmetatable(instance, StopLarry)

	-- Prepared statements. Sprint-scoped ones prefixed `stop_` to
	-- keep them clearly distinct from production's stmts.
	-- `reap_frame` OVERWRITES production's handle — the sprint's
	-- version adds `and frame_process_cap is null` so the reap is a
	-- silent no-op on caps. Production's original handle gets GC'd
	-- (nothing else references it on a StopLarry instance).
	instance.stmts.stop_find_child_of = instance.cvm:prepare(
		"select object_pk from objects where frame_parent = ?"
	)

	instance.stmts.stop_get_frame_gc = instance.cvm:prepare(
		"select frame_gc from objects where object_pk = ?"
	)

	instance.stmts.stop_get_owner_role = instance.cvm:prepare(
		"select owner_role from objects where object_pk = ?"
	)

	instance.stmts.stop_get_engine_class = instance.cvm:prepare(
		"select engine_class from objects where object_pk = ?"
	)

	instance.stmts.reap_frame = instance.cvm:prepare(
		"delete from objects where object_pk = ? and frame_process_cap is null"
	)

	-- Insert the stop frame as a child of the current frame. Owner_role
	-- inherits from the current frame via the SELECT — one parameter,
	-- referenced twice via ?1. Called from :process_stop at
	-- %process.stop-dispatch time.
	instance.stmts.stop_insert_stop_frame = instance.cvm:prepare(
		"insert into objects "
		.. "(base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) "
		.. "select 'o', 'f', 'stop', '[]', 0, ?1, owner_role "
		.. "from objects where object_pk = ?1"
	)

	return instance
end


--[[
## `StopLarry:process_stop`

Overrides `Engine:process_stop`. Called by `Engine:run_row` when it
recognizes the `%process.stop` row shape.

**Behavior:** insert a stop frame under the current frame, then
raise HALT. The insert uses the `stop_insert_stop_frame` prepared
statement (set up in `.new`); the stop frame has
`engine_class='stop'`, empty ast (terminal at birth),
`frame_parent = self.current_frame_pk`, and inherits `owner_role`
from the current frame via the SELECT. HALT unwinds through
`run_row` → walker → `run`'s xpcall.
]]
function StopLarry:process_stop()
	local stmt = self.stmts.stop_insert_stop_frame
	stmt:bind_values(self.current_frame_pk)

	local rc = stmt:step()
	stmt:reset()

	if rc ~= SQLITE_DONE then
		error("stop_larry_process_stop_insert_failed: " .. tostring(self.cvm:errmsg()))
	end

	halt.raise()
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
## `get_frame_gc` — helper

Returns the `frame_gc` value for the given frame (`1` if the frame
is in gc state, `nil` otherwise). Wraps the `stop_get_frame_gc`
prepared statement.
]]
local function get_frame_gc(self, frame_pk)
	local stmt = self.stmts.stop_get_frame_gc
	stmt:bind_values(frame_pk)

	local gc

	if stmt:step() == SQLITE_ROW then
		gc = stmt:get_value(0)
	end

	stmt:reset()

	return gc
end


--[[
## `get_engine_class` — helper

Returns the `engine_class` value for the given object (a string
like `'stop'`, or `nil` for objects that don't carry an
engine_class). Wraps the `stop_get_engine_class` prepared statement.
]]
local function get_engine_class(self, object_pk)
	local stmt = self.stmts.stop_get_engine_class
	stmt:bind_values(object_pk)

	local engine_class

	if stmt:step() == SQLITE_ROW then
		engine_class = stmt:get_value(0)
	end

	stmt:reset()

	return engine_class
end


--[[
## `advance_past_current` — helper

Reads the frame's current stmt_idx and advances it by one via the
production `advance` prepared statement. Assumes the schema's
advance preconditions are met by the caller (frame_gc = 1,
needs_trace empty). The advance's AFTER trigger auto-nulls
frame_gc.
]]
local function advance_past_current(self, frame_pk)
	local get_idx = self.stmts.get_stmt_idx
	get_idx:bind_values(frame_pk)

	local current_idx

	if get_idx:step() == SQLITE_ROW then
		current_idx = get_idx:get_value(0)
	end

	get_idx:reset()

	local advance = self.stmts.advance
	advance:bind_values(current_idx + 1, frame_pk)
	advance:step()
	advance:reset()
end


--[[
## `StopLarry:run`

The one entry point for driving a process — both first-time run and
continuation-after-halt. Overrides `Engine:run`. Replaces the
old `StopLarry:restart` too: since `run` and `restart` bottom out
in the same `restart_frame(cap_pk)` recursion, they're the same
call. First invocation bootstraps cap + frame 0 (`self.caspm` is
present from `:load()`); subsequent invocations skip bootstrap and
continue whatever the DB has (halted at a stop frame, halted at a
crash-restart chain, whatever).

**Optional `restart_value`.** If given, the value is materialized as
a scalar and injected as the leaf frame's `rv` before the recursion
kicks off. Only valid when the leaf is a stop frame
(`engine_class = 'stop'`) — the check raises
`stop_larry_inject_requires_stop_frame` otherwise. On a fresh run
(no halt below), passing `restart_value` doesn't make sense
either — there's no stop frame at the leaf yet — same error.

The whole run is wrapped in `xpcall` + HALT-catch. HALT unwinds
through `restart_frame` back here; anything else re-raises via
`error(err, 0)` so the caller sees the original exception with its
original stack trace.

**Result hash:** `{complete = 1, cap_pk = <pk>}` on normal
completion; `{stopped = 1, cap_pk = <pk>}` if `%process.stop`
raised HALT during the walk.
]]
function StopLarry:run(restart_value)
	local db = self.cvm
	local stmts = self.stmts

	-- Bootstrap on first call. self.caspm is set by :load() and
	-- cleared after seeding — its presence identifies "first call
	-- after load, seed the process."
	if self.caspm then
		local user_pk

		if stmts.get_user_role:step() == SQLITE_ROW then
			user_pk = stmts.get_user_role:get_value(0)
		end

		stmts.get_user_role:reset()

		-- Seed the cap.
		stmts.insert_cap:bind_values(user_pk)
		stmts.insert_cap:step()
		self.cap_pk = stmts.insert_cap:get_value(0)
		stmts.insert_cap:reset()

		-- Seed frame 0 under the cap.
		local ast_json = cjson.encode(self.caspm)
		stmts.insert_frame_0:bind_values(ast_json, self.cap_pk, user_pk)

		local rc = stmts.insert_frame_0:step()

		if rc ~= SQLITE_ROW then
			local err = self.cvm:errmsg()
			stmts.insert_frame_0:reset()
			error("stop_larry_insert_frame_0_failed: " .. err)
		end

		stmts.insert_frame_0:reset()

		self.caspm = nil
	elseif not self.cap_pk then
		error("stop_larry_run_before_load: engine:run() called before engine:load() and no existing process to continue")
	end

	-- Optional value injection onto the leaf frame.
	if restart_value ~= nil then
		local leaf_pk = self.cap_pk

		while true do
			local next_pk = find_child_of(self, leaf_pk)
			if not next_pk then break end
			leaf_pk = next_pk
		end

		-- Injecting a return value only makes sense when the process
		-- was intentionally halted via %process.stop — that's what
		-- created a stop frame at the leaf. A crash-restart, or any
		-- other paused-but-not-stopped state, has no stop frame; there
		-- is no meaningful "reply" the value could stand in for.
		local leaf_engine_class = get_engine_class(self, leaf_pk)

		if leaf_engine_class ~= 'stop' then
			error(
				"stop_larry_inject_requires_stop_frame: cannot inject a " ..
				"restart_value; the leaf frame's engine_class is " ..
				tostring(leaf_engine_class) ..
				" (expected 'stop'). Value injection is only valid on a " ..
				"process that was intentionally halted via %process.stop.")
		end

		-- Look up leaf's owner_role for the injected scalar.
		local get_owner = stmts.stop_get_owner_role
		get_owner:bind_values(leaf_pk)

		local owner_role

		if get_owner:step() == SQLITE_ROW then
			owner_role = get_owner:get_value(0)
		end

		get_owner:reset()

		assert(db:exec('savepoint run_inject_rv;') == 0, db:errmsg())

		local ok, err = pcall(function()
			local scalar_pk = self.data:add_scalar(restart_value, owner_role)
			local bucket_pk = self.data:add_bucket(leaf_pk)
			self.data:upsert_ref(bucket_pk, 'rv', scalar_pk)
		end)

		if not ok then
			db:exec('rollback to savepoint run_inject_rv;')
			db:exec('release savepoint run_inject_rv;')
			error(err, 0)
		end

		assert(db:exec('release savepoint run_inject_rv;') == 0, db:errmsg())
	end

	-- Kick the process off. restart_frame handles the full descent
	-- (recurses into any child chain), the unwind (each level's reap
	-- sets the parent's gc; parent's gc-check drains + advances), and
	-- the cap's own cycle (frame 0's reap sets cap.gc=1, cap runs gc
	-- + advances to terminal, cap's reap step no-ops via the cap-skip
	-- clause on reap_frame).
	local ok, result_or_err = xpcall(
		function() return self:restart_frame(self.cap_pk) end,
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


--[[
## `StopLarry:run_frame`

Sprint's rewrite of `Engine:run_frame`. Signature:
`(frame_pk, role_pk?)`. Three deltas from production:

1. **No `self.stopped` checks.** Under HALT-as-sentinel, `%process.stop`
   never sets `self.stopped` — the halt is an exception unwind. Both
   the mid-loop `if self.stopped then break end` and the pre-reap
   `if self.stopped then return end` are dead code under this model.
2. **Missing ast raises.** Production silently returns when
   `ast_json == nil` ("defense in depth"). That hides bugs — if
   `run_frame` is called on a pk that isn't a frame, the caller
   passed something wrong and should hear about it. Raises
   `run_frame_no_ast`.
3. **No tail drain.** When this frame is reaped, its parent gets
   `frame_gc = 1` via `frames_child_delete_sets_parent_gc`. The
   parent's next run-gc step sweeps this frame's cascade marks.
   The tail drain in production was compensating for cap-exempt;
   under the sprint's `restart_frame(cap_pk)` model, the parent
   (cap or otherwise) always handles it, so this frame doesn't
   need to double-dip.

**Optional `role_pk` parameter.** A caller that already knows the
frame's `owner_role` — e.g., a future handler that spawns a child
frame and inherits the parent's role — can pass it as the second
argument to skip the `role_by_pk` lookup. When omitted (as in every
current caller), the fetch happens inside. Cheap hook; no cost when
unused.

Everything else — walker loop shape, dispatch → drain → advance
cycle, the reap at frame end — matches production.
]]
function StopLarry:run_frame(frame_pk, role_pk)
	local stmts = self.stmts

	-- Pull the frame_ast out of the frame and parse it.
	stmts.get_ast:bind_values(frame_pk)

	local ast_json

	for row in stmts.get_ast:nrows() do
		ast_json = row.frame_ast
	end

	stmts.get_ast:reset()

	if ast_json == nil then
		error("run_frame_no_ast: run_frame called with pk " .. frame_pk
			.. " but no frame_ast found (row missing or not a frame)")
	end

	local frame_ast = cjson.decode(ast_json)

	if type(frame_ast) ~= 'table' or (next(frame_ast) ~= nil and type(next(frame_ast)) ~= 'number') then
		error('caspm_not_array: expected frame frame_ast to decode as a JSON array')
	end

	local function get_stmt_idx()
		stmts.get_stmt_idx:bind_values(frame_pk)

		local idx

		for row in stmts.get_stmt_idx:nrows() do
			idx = row.frame_stmt_idx
		end

		stmts.get_stmt_idx:reset()

		return idx
	end

	local idx = get_stmt_idx()

	-- Publish the current frame's pk + owner_role_pk for handlers.
	-- Both are immutable at the schema level, so hoisting outside the
	-- loop is safe. Handlers reach into these two fields instead of
	-- pulling a full-row wrapper.
	self.current_frame_pk = frame_pk
	self.current_role_pk  = role_pk or self.data:role_by_pk(frame_pk)

	while idx < #frame_ast do
		idx = idx + 1

		self:run_row(frame_ast[idx])

		self.data:garbage_collect(self.cap_pk)

		stmts.advance:bind_values(idx, frame_pk)
		stmts.advance:step()
		stmts.advance:reset()
	end

	self.current_frame_pk = nil
	self.current_role_pk  = nil

	-- Reap. Parent's frame_gc gets set to 1 by
	-- frames_child_delete_sets_parent_gc; parent's next run-gc step
	-- sweeps this frame's cascade marks. No tail drain here.
	--
	-- The `frame_process_cap is null` clause in reap_frame's SQL
	-- makes this a silent no-op on the cap — the cap survives its own
	-- run_frame call at terminal state, so it stays around as the
	-- process anchor while every other frame gets reaped normally.
	stmts.reap_frame:bind_values(frame_pk)
	stmts.reap_frame:step()
	stmts.reap_frame:reset()
end


--[[
## `StopLarry:restart_frame`

Parallel to `Engine:run_frame`. Two independent pre-steps, then
delegate the walker + reap to `self:run_frame` (the sprint's
override).

**Restart is a general resume mechanism, not just a %process.stop
partner.** The algorithm doesn't care why the process was paused.
`%process.stop` is one way to land there (intentional halt via HALT
sentinel, leaves a stop frame); an unclean shutdown (crash, pulled
plug, `kill -9`) is another (leaves whatever the last committed
SQLite transaction had, no stop frame). Because the schema keeps
the DB in a valid state after every transaction, both look the
same to restart_frame at the row level: a cap → frame chain with a
paused leaf. The algorithm operates on graph structure
(`frame_parent`, `frame_gc`), never on `engine_class = 'stop'` —
crash-restart has no stop marker to find, and the algorithm still
works because it doesn't need one.

**Pre-step 1: descend into any child.** If this frame has a child
(it's somewhere in a halt chain — the child is the paused
sub-frame), recursively `restart_frame` the child. The recursion
unwinds bottom-up: at the leaf, `Engine.run_frame` walks the empty
ast (terminal at birth for the sprint's stop frames) and reaps.
Each reap fires `frames_child_delete_propagates_rv` (parent gets
the child's rv) and `frames_child_delete_sets_parent_gc` (parent's
frame_gc → 1). When the recursion returns to this frame, it's now
in gc state (unless it never had a child in the first place).

**Pre-step 2: run gc + advance if in gc state.** If `frame_gc = 1`,
this frame is mid-cycle between run-statement and run-gc — either
because a child just reaped during Pre-step 1, or because a leaf
handler set gc pre-halt. Run gc (`garbage_collect` — the child's
cascade populated `needs_trace` and the advance's auto-null-gc
trigger `frames_gc_reset_requires_empty_needs_trace` refuses while
marks are outstanding), then advance stmt_idx. The advance's
`frames_advance_sets_gc_null` AFTER trigger resets `frame_gc` back
to null. This frame now looks fresh to the walker.

**Delegate.** `Engine.run_frame(self, frame_pk)` walks any
remaining stmts and reaps at frame end. The reap unwinds one level
up the recursion — where the enclosing `restart_frame` call sees
its own gc go to 1 and repeats the pattern.

**No walker duplication.** `restart_frame` never re-implements the
loop-and-reap logic. Every dispatch goes through
`Engine.run_frame` — production's single implementation. The two
pre-steps are the only restart-specific work.
]]
function StopLarry:restart_frame(frame_pk)
	local child_pk = find_child_of(self, frame_pk)

	if child_pk then
		self:restart_frame(child_pk)
	end

	if get_frame_gc(self, frame_pk) == 1 then
		self.data:garbage_collect(self.cap_pk)
		advance_past_current(self, frame_pk)
	end

	self:run_frame(frame_pk)
end


return StopLarry
