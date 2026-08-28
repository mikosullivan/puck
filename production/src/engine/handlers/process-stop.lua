--[[
{
	"module": "handlers.process-stop",
	"role": "Core handler for the `%process.stop` system primitive. Matches `{cmd:'mc'}` rows whose envelope names `{fn:'stop', rcvr:{sys:'process'}}`; on match, inserts a stop frame under the currently-walking frame via the `insert_stop_frame` prepared statement, then raises the HALT sentinel via `halt.raise()`. Registered ahead of MainHandler in the stock chain so MainHandler never sees the stop shape. Stop is a system-level primitive — no user-extensible dispatch here; the shape check is the entire match.",
	"exports": {
		"new":    "() -> ProcessStop",
		"handle": "(frame, row, restart?) -> true when the row is the %process.stop shape (call never returns cleanly — halt.raise propagates); false otherwise"
	},
	"depends_on": ["handler", "halt", "lsqlite3 (for SQLITE_DONE)"],
	"status": "V0.1 — moved out of Frame:run_row's special-case check into the normal handler chain; the old Frame:process_stop method is retired"
}
]]

--[[
# `handlers.process-stop`

Core handler for `%process.stop`.

**Shape matched.** `[{cmd:'mc'}, {fn:'stop', rcvr:{sys:'process'}}]`. Any other row shape returns false and the dispatch chain moves on.

**On match.** Two committed side effects:

1. **Insert a stop frame.** Under the currently-walking frame, via `frame.engine.stmts.insert_stop_frame` bound to the frame's `object_pk`.
2. **Raise HALT.** Via `halt.raise()`. Propagates up through `dispatch` → `Frame:run_row`'s pcall (which re-raises anything that isn't `unrecognized_caspm`) → `Frame:run` → `Engine:run`'s xpcall (which catches HALT specifically and returns `{stopped = 1, cap_pk = ...}`).

**Why a handler, not a Frame method.** `%process.stop` is a method_call like any other from the CaspM's perspective — head atom is `{cmd:'mc'}`, envelope has `fn` + `rcvr`. Handling it in the same dispatch chain that handles every other method_call keeps the row-processing pipeline uniform: no special-case branch in `Frame:run_row`, no separate primitive-method surface on Frame or Engine. The handler shape is the extension point; system primitives just happen to be handlers that ship with the engine.

**Registered first.** MainHandler recognizes ALL `{cmd:'mc'}` rows and would try to dispatch stop as a regular method (and fail with `main_handler_unsupported_method`) if it ever saw the row. ProcessStop must precede MainHandler in the stock chain so ProcessStop claims the stop shape before MainHandler sees it. See [handlers/init.lua](init.lua).
]]
local sqlite  = require('lsqlite3')
local Handler = require('handler')
local halt    = require('halt')

local SQLITE_DONE = sqlite.DONE


local ProcessStop = setmetatable({}, {__index = Handler})
ProcessStop.__index = ProcessStop


function ProcessStop.new()
	return setmetatable(Handler.new(), ProcessStop)
end


--[[
## `ProcessStop:handle` — match `%process.stop` and halt

Returns false on any row that isn't the `%process.stop` shape. On the stop shape, inserts a stop frame under the currently-walking frame and raises HALT — the raise propagates through dispatch and never returns cleanly, so the `return true` at the end of the function is unreachable but kept for signature parity with the Handler contract.
]]
function ProcessStop:handle(frame, row, restart)
	local head = row[1]

	if type(head) ~= 'table' or head.cmd ~= 'mc' then
		return false
	end

	local envelope = row[2]

	if type(envelope) ~= 'table' or envelope.fn ~= 'stop' then
		return false
	end

	if type(envelope.rcvr) ~= 'table' or envelope.rcvr.sys ~= 'process' then
		return false
	end

	-- Resume path: the halt already happened and the stop frame is
	-- already inserted. When the walker re-dispatches this statement
	-- under restart, our job is just to claim it (return true) so
	-- the walker can gc + advance. `frame_gc = 1` is already set from
	-- the stop frame's reap during the resume-descent.
	if restart then
		return true
	end

	local stmt = frame.engine.stmts.insert_stop_frame
	stmt:bind_values(frame.object_pk)

	local rc = stmt:step()
	stmt:reset()

	if rc ~= SQLITE_DONE then
		error("process_stop_insert_failed: " .. tostring(frame.engine.cvm:errmsg()))
	end

	halt.raise()
end


return ProcessStop
