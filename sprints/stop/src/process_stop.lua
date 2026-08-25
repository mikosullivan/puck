--[[
{
	"module": "process_stop",
	"role": "Sprint-scoped rewrite of the ProcessStop handler for the stop sprint. Matches the same CaspM row shape production's handler does (fc-head + call atom with fn='stop', rc.sys='process'), but instead of flipping engine.stopped it inserts a stop frame under the current frame (base='o', control='f', engine_class='stop', empty ast so terminal at birth) via the `stop_insert_stop_frame` prepared statement (set up in StopLarry.new), then raises the HALT sentinel from `halt.lua`. The sprint's Larry catches the raise in its overridden run().",
	"exports": {
		"new":    "() -> ProcessStop",
		"handle": "(engine, row) -> raises HALT sentinel on match; returns false when the row isn't ours"
	},
	"depends_on": ["handler", "halt"]
}
]]

--[[
# `process_stop`

Sprint's ProcessStop handler.

**Match** — same as production: `row[1]` is an array whose head atom
carries `in='fc'` and whose call atom has `fn='stop'` and
`rc.sys='process'`.

**Execute** — two steps, then raise:

1. Insert the stop frame as a child of `engine.current_frame`.
   Row shape: `base='o'`, `control='f'`, `engine_class='stop'`,
   `frame_ast='[]'`, `frame_stmt_idx=0`, `frame_parent=<current
   frame's pk>`, `owner_role` inherited from the current frame.
   Empty ast means the frame is terminal at birth — a future
   restart just reaps it (the walker's normal terminal-frame
   behavior), which fires `frames_child_delete_propagates_rv`
   and lifts the stop frame's rv (null unless someone set it
   pre-rerun) up to the parent.
2. Call `halt.raise()`. This never returns; the Lua unwind travels
   through run_row + run_frame back to `Larry:run`'s xpcall which
   catches the sentinel and returns the stopped-result hash to the
   host.

**Why the stop frame if restart isn't implemented in this sprint?**
It's the anchor for the future restart machinery. Under the
"restart is just plain rerun" model Miko sketched, a future
`engine:run()` invocation would find the stop frame at the bottom
of the process chain, reap it (its terminal-at-birth state makes
that natural), propagate its rv upward, and continue. This sprint
lays the anchor; the rerun path stays deferred.
]]
local sqlite  = require('lsqlite3')
local Handler = require('handler')
local halt    = require('halt')

-- Cached at module load; avoids a `sqlite.DONE` global lookup per step check.
local SQLITE_DONE = sqlite.DONE


local ProcessStop = setmetatable({}, {__index = Handler})
ProcessStop.__index = ProcessStop


function ProcessStop.new()
	return setmetatable(Handler.new(), ProcessStop)
end


function ProcessStop:handle(engine, row)
	local expr = row[1]

	if type(expr) ~= 'table' then
		return false
	end

	local head = expr[1]
	local call = expr[2]

	if type(head) ~= 'table' or head['in'] ~= 'fc' then
		return false
	end

	if type(call) ~= 'table' or call.fn ~= 'stop' then
		return false
	end

	if type(call.rc) ~= 'table' or call.rc.sys ~= 'process' then
		return false
	end

	-- Insert the stop frame under the current frame via the prepared
	-- statement `stop_insert_stop_frame` (set up in StopLarry.new). The
	-- statement's SELECT inherits owner_role from the current frame,
	-- so the stop frame is owned by whoever the caller is owned by.
	-- Empty ast + frame_stmt_idx=0 means terminal at birth.
	local current_pk = engine.current_frame.object_pk
	local stmt       = engine.stmts.stop_insert_stop_frame

	stmt:bind_values(current_pk)

	local rc = stmt:step()
	stmt:reset()

	if rc ~= SQLITE_DONE then
		error("process_stop_insert_failed: " .. tostring(engine.cvm:errmsg()))
	end

	halt.raise()
end


return ProcessStop
