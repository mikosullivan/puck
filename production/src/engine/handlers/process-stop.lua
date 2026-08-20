--[[
{
	"module": "handlers.process-stop",
	"role": "Handler for the `%process.stop` global method call. Matches the CaspM row shape produced by that call (a single-expression row containing an fc-head atom + a call atom whose rc is `{sys: 'process'}` and fn is `'stop'`). On match, sets `engine.stopped = true` so the walker's loop can observe it and exit before advancing.",
	"exports": {
		"new":    "() -> ProcessStop",
		"handle": "(engine, row) -> true (recognized and executed) | false (not our shape)"
	},
	"depends_on": ["handler"],
	"status": "V0.1"
}
]]

--[[
# `handlers.process-stop`

Handler for `%process.stop` — the primitive that halts execution in place, leaving the database as-is, and returns control to the Lua caller. Purely an engine-level flag flip; no schema writes, no cleanup.

**Match criteria:** `row[1]` is a table (Lua array) whose first element has `.in == 'fc'` (function-call head) and whose second element has `.fn == 'stop'` and `.rc.sys == 'process'`.

**On match, execute:** set `engine.stopped = true`. That's it. The walker's per-iteration check picks up the flag, breaks out of the dispatch loop, and returns control up through `engine:run()`.

Doesn't touch the frame's gc, stmt_idx, or anything else — leaving the DB alone is the whole point.
]]
local Handler = require('handler')


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

	engine.stopped = true

	return true
end


return ProcessStop
