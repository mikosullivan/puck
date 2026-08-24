--[[
{
	"module": "stop_larry",
	"role": "Sprint-scoped Engine subclass that swaps in the sprint's process_stop handler and wraps :run() in an xpcall that catches the HALT sentinel. Inherits everything else from production's Larry (which itself inherits from Engine). Named `stop_larry` (not `larry`) to avoid shadowing production's Larry in package.path — this module requires production's `larry` module, so a same-name collision would recurse.",
	"exports": {
		"new":    "(opts?) -> StopLarry — same signature as Larry.new; also swaps the stock ProcessStop handler for the sprint's version",
		"run":    "() -> result table — overrides Engine:run to catch the HALT sentinel; returns {stopped=1, cap_pk=...} on halt, {complete=1, cap_pk=...} on normal completion"
	},
	"depends_on": ["larry (production)", "engine (production)", "halt", "process_stop"]
}
]]

--[=[
# `larry` (sprint-scoped)

Sprint-scoped Larry subclass for the stop sprint.

**Two overrides:**

1. `StopLarry.new(opts)` — calls production's `Larry.new`, then
   walks `self.row_handlers` and replaces production's ProcessStop
   handler with the sprint's version. Everything else stays wired
   as production configured it.

2. `StopLarry:run()` — wraps the parent's `Engine.run(self)` in
   `xpcall`. If the caught error is our HALT sentinel, returns a
   stopped-result hash. Anything else re-raises via `error(err, 0)`.


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


return StopLarry
