--[[
{
	"module": "frame",
	"role": "Wrapper class for `control='f'` objects rows — a frame IS an object, so Frame is a subclass of `object`. Constructed for a specific frame_pk; instance fields are the row's columns directly (object_pk, owner_role, frame_ast, control, frame_process_cap, frame_parent — bucket_pk / stack_pk if the schema denormalized them). Adds the walker methods that make a frame do its dispatch work: `run` (per-frame loop; optional `restart` flag first descends any halt chain and does gc + advance before walking), `run_row` (row dispatcher passing self and the restart flag as context to handlers). Inherits object's `bucket` accessor.",
	"inherits_from": "cvm.sqlite.object",
	"exports": {
		"new":     "(engine, pk) -> Frame — fetches the row via engine.data:object_by_pk, upgrades the metatable to Frame's",
		"run":     "(restart?) — walk the frame's ast statement-by-statement; dispatch, gc, advance, reap. Truthy `restart` first descends into any child frame (recursively), runs gc + advances if in gc state, then walks",
		"run_row": "(row, restart?) — dispatch a CaspM row through engine.row_handlers, passing self as the frame context and forwarding the restart flag"
	},
	"depends_on": ["cvm.sqlite.object", "cjson", "dispatch", "lsqlite3 (for SQLITE_ROW)"],
	"status": "V0.1"
}
]]

--[[
# `Frame`

Wrapper class for `control='f'` rows — a frame IS an object. Frame is a subclass of [`Object`](cvm/sqlite/object.lua); a Frame instance carries every column from the `objects` row directly on `self` (`self.object_pk`, `self.owner_role`, `self.frame_ast`, `self.control`, `self.frame_process_cap`, `self.frame_parent`, etc.) plus adds the walker behavior a frame needs.

**Why a class.** Under the frames-as-objects design, each frame's context lives on a Lua object. Handlers receive the Frame as the dispatch context and reach into `frame.object_pk`, `frame.owner_role`, `frame.engine.data` — no ambient `engine.current_frame_pk` field to consult, no state to save/restore on recursion (each nested walk constructs its own Frame; the outer frame's `self` binding is a lexical local and survives untouched).

**Method inventory** (Frame-specific — inherited object methods like `bucket()` come along for the ride):

- `run(restart)` — the single walker entry point. Truthy `restart` triggers a resume prelude: descend into any child frame recursively (each recursion also passes `true`), then if this frame's `frame_gc = 1`, run gc + advance stmt_idx. Whether the prelude ran or not, then walks the frame's ast statement-by-statement: dispatch via `run_row`, run gc, advance stmt_idx. Reaps at terminal.
- `run_row(row, restart)` — dispatches through `engine.row_handlers`, passing `self` as the frame context and forwarding the `restart` flag. No special-case branches — every row goes through the same handler chain.

**Live vs snapshot fields.** The row columns are captured on wrapper construction. Immutable ones (`object_pk`, `owner_role`, `frame_ast`) are always current. Mutable ones (`frame_stmt_idx`, `frame_gc`) are captured at construction and go stale as the walker advances them — the methods below (`get_stmt_idx`, `get_frame_gc`, `get_engine_class`) do a live DB re-fetch when the current value matters.

**The `restart` flag.** Handlers receive `restart` as their third arg. On a normal walk the flag is falsy; on a resume prelude driven by `run(true)` it can be truthy. Handlers that don't care ignore it. Handlers that do care use it to decide "was I already partway through this statement?" — the two-phase dispatch pattern where the same handler shape covers both the fresh-start eval and the after-child-completes bind. The plumbing is in place now; individual handlers wire it up as their two-phase logic lands.
]]
local cjson    = require('cjson')
local sqlite   = require('lsqlite3')
local dispatch = require('dispatch')
local Object   = require('cvm.sqlite.object')

local SQLITE_ROW = sqlite.ROW


local Frame = setmetatable({}, {__index = Object})
Frame.__index = Frame


--[[
## `Frame.new`

Fetches the row for `pk` via `engine.data:object_by_pk`, upgrades the returned object wrapper to Frame's metatable, returns it. Raises `frame_new_no_row` if the pk doesn't resolve; raises `frame_new_not_a_frame` if the row's control isn't `'f'`.

The instance's engine field is the top-level Engine (set by `Object.new` when `cvm:object_by_pk` calls it, per the Engine's `data.engine = engine` back-reference at construction).
]]
function Frame.new(engine, pk)
	local obj = engine.data:object_by_pk(pk)

	if obj == nil then
		error("frame_new_no_row: no objects row with pk " .. tostring(pk))
	end

	if obj.control ~= 'f' then
		error("frame_new_not_a_frame: pk " .. tostring(pk)
			.. " has control '" .. tostring(obj.control) .. "', expected 'f'")
	end

	return setmetatable(obj, Frame)
end


--[[
## `Frame:get_stmt_idx` — live read of frame_stmt_idx

Snapshot from `.frame_stmt_idx` goes stale as the walker advances; use this when the current value matters.
]]
function Frame:get_stmt_idx()
	local stmt = self.engine.stmts.get_stmt_idx
	stmt:bind_values(self.object_pk)

	local idx

	for row in stmt:nrows() do
		idx = row.frame_stmt_idx
	end

	stmt:reset()

	return idx
end


--[[
## `Frame:get_frame_gc` — live read of frame_gc
]]
function Frame:get_frame_gc()
	local stmt = self.engine.stmts.get_frame_gc
	stmt:bind_values(self.object_pk)

	local gc

	if stmt:step() == SQLITE_ROW then
		gc = stmt:get_value(0)
	end

	stmt:reset()

	return gc
end


--[[
## `Frame:get_engine_class` — live read of engine_class
]]
function Frame:get_engine_class()
	local stmt = self.engine.stmts.get_engine_class
	stmt:bind_values(self.object_pk)

	local engine_class

	if stmt:step() == SQLITE_ROW then
		engine_class = stmt:get_value(0)
	end

	stmt:reset()

	return engine_class
end

--[[
## `Frame:find_child_pk`

Returns the object_pk of this frame's single child (or nil). Under the linear-stack rule, at most one child.
]]
function Frame:find_child_pk()
	local stmt = self.engine.stmts.find_child_of
	stmt:bind_values(self.object_pk)

	local child_pk

	if stmt:step() == SQLITE_ROW then
		child_pk = stmt:get_value(0)
	end

	stmt:reset()

	return child_pk
end


--[[
## `Frame:advance` — advance frame_stmt_idx by one

The schema enforces advance-by-1 (`frames_stmt_idx_advances_by_one`), so no target value is bindable — the SQL expresses "increment" directly (`SET frame_stmt_idx = frame_stmt_idx + 1`). The BEFORE trigger `frames_advance_requires_gc` still needs `frame_gc = 1` beforehand; the AFTER trigger `frames_advance_sets_gc_null` still resets `frame_gc` on completion.
]]
function Frame:advance()
	local stmt = self.engine.stmts.advance
	stmt:bind_values(self.object_pk)
	stmt:step()
	stmt:reset()
end


--[[
## `Frame:reap` — DELETE this frame from objects

The `reap_frame` prepared statement's cap-skip clause makes the delete a silent no-op on caps: cap's own walk hits terminal and calls reap, but the WHERE filter drops caps so the cap survives as the process anchor.
]]
function Frame:reap()
	local stmt = self.engine.stmts.reap_frame
	stmt:bind_values(self.object_pk)
	stmt:step()
	stmt:reset()
end


--[[
## `Frame:run` — the walker

Single entry point for both first-time execution and continuation-after-halt.

**Optional `restart` flag.** Truthy triggers a resume prelude: if this frame has a child (it's somewhere in a halt chain), recursively `run(true)` a Frame for the child. The recursion unwinds bottom-up: each reap fires `frames_child_delete_propagates_rv` (parent gets the child's rv) and `frames_child_delete_sets_parent_gc` (parent's frame_gc → 1). Whether descent actually happened is tracked as `descended` — only truthy if we came out of a real halt chain.

**Walker loop.** For each remaining statement, an inner dispatch-and-recurse loop:

1. Dispatch the statement via `run_row(row, stmt_restart)`. On the first iteration for the resumed statement, `stmt_restart = descended` — the handler sees `true` iff we just came out of a real halt chain (fresh runs get `false`).
2. If dispatch spawned a child frame (a handler chose to defer part of its work — e.g. arg evaluation for a method_call), walk the child recursively via `Frame.new(...):run(true)`, then loop back to re-dispatch the same statement with `stmt_restart = true`. The child's reap has set our `frame_gc = 1` and propagated its `rv` to this frame's bucket, so the handler's re-entry can pick up the work.
3. If dispatch did NOT spawn a child, the statement is complete — the handler set `frame_gc` (either directly or via a child reap). Exit the inner loop.
4. `garbage_collect` + `advance` — the standard per-statement finalize. `frames_advance_requires_gc` will raise if the handler failed to set gc (either directly or via a child), which is how handler bugs self-detect.

Null statements (`[null]`, notably the cap's dummy slot) skip dispatch entirely — the outer gc + advance still runs, which is why the schema requires `frame_gc = 1` on the frame at that point (frame 0's reap sets the cap's gc before the cap's walker gets here).

**Fresh vs resume.** A fresh process (no halt chain below the cap) with `run(true)` no-ops the descent, and `descended` stays false. The first-statement dispatch gets `restart = false` — same as `run(false)`. On resume from halt, descent happens; `descended = true`; the first-statement dispatch sees `restart = true`. Subsequent statements (past the resumed one) always dispatch with `restart = false` — only the resumed statement gets the flag.

**Multi-phase handlers.** Handlers that decompose their work across multiple child frames (e.g. `Plus`, which evaluates receiver + args in successive eval frames) read state from `frame.rv` and their reserved bucket slots (`receiver`, `arg_0`, ...) to decide their next action. Between phases the handler moves `rv` into a named slot, spawns the next eval frame, and returns. The walker re-dispatch loop above is what threads them together.
]]
function Frame:run(restart)
	local descended = false

	if restart then
		local child_pk = self:find_child_pk()

		if child_pk then
			local child = Frame.new(self.engine, child_pk)
			child:run(true)
			descended = true
		end
	end

	if self.frame_ast == nil then
		error("run_frame_no_ast: no frame_ast for pk " .. self.object_pk
			.. " (row missing or not a frame)")
	end

	local ast = cjson.decode(self.frame_ast)

	if type(ast) ~= 'table' or (next(ast) ~= nil and type(next(ast)) ~= 'number') then
		error("caspm_not_array: expected frame_ast to decode as a JSON array")
	end

	local idx = self:get_stmt_idx()

	while idx < #ast do
		idx = idx + 1

		-- frame_ast indices are 0-based in the DB; Lua arrays are
		-- 1-based, so we advance idx first (0→1) and use it directly.
		local stmt = ast[idx]

		if stmt ~= nil and stmt ~= cjson.null then
			local stmt_restart = descended

			while true do
				self:run_row(stmt, stmt_restart)

				local child_pk = self:find_child_pk()

				if child_pk == nil then
					break
				end

				local child = Frame.new(self.engine, child_pk)
				child:run(true)
				stmt_restart = true
			end
		end

		self.engine.data:garbage_collect(self.engine.cap_pk)

		self:advance()

		descended = false
	end

	self:reap()
end


--[[
## `Frame:run_row` — dispatch a CaspM row

Every row goes through `dispatch` with `self` and the `restart` flag as the trailing args — handlers receive `(frame, row, restart)`. No shape special-cases here; the handler chain decides. See [handlers/init.lua](handlers/init.lua) for the stock roster and its order.

Raises `unrecognized_caspm` with the row-head atom's key set appended when no handler claims the row.
]]
function Frame:run_row(row, restart)
	local ok, err = pcall(dispatch, self.engine.row_handlers, self, row, restart)

	if ok then
		return
	end

	if type(err) == 'string' and err:find('unrecognized_caspm', 1, true) then
		local keys = {}

		if type(row[1]) == 'table' then
			for k in pairs(row[1]) do table.insert(keys, tostring(k)) end
		end

		table.sort(keys)
		error("unrecognized_caspm: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {"
			.. table.concat(keys, ', ') .. "}")
	end

	error(err, 0)
end


return Frame
