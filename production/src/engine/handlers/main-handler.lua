--[[
{
	"module": "handlers.main-handler",
	"role": "The main row-handler for the CaspM dispatcher. Stub for now — claims every row it sees and does nothing with it. Will eventually be the general dispatcher that recognizes all CaspM row shapes; specialized handlers (variable-scalar, etc.) get added back later as optimizations for shapes the main handler could handle at general-dispatch speed but shouldn't have to.",
	"exports": {
		"new":    "() -> MainHandler",
		"handle": "(engine, row) -> true — claims every row; no side effects yet"
	},
	"depends_on": ["handler"],
	"status": "V0.1 — stub, no dispatch logic implemented"
}
]]

--[[
# `handlers.main-handler`

The engine's main row-handler.

**Current state:** stub. `:handle` claims every row (returns `true`) and does nothing with it. `run_row` therefore succeeds without side effects; the walker's advance-preconditions (`frame_gc = 1`) are NOT met by this handler, so any program the walker actually tries to advance through will fail loudly at the schema level — that's the intended signal while dispatch logic is being built up.

**Design intent.** Once dispatch logic lands, the main handler recognizes every CaspM row shape (assignment, function call, control flow, block, whatever) and does the right thing for each. Specialized handlers like `variable-scalar` get slotted back in FRONT of the main handler as pure optimizations — they short-circuit specific shapes at a faster path, while the main handler remains the fallback that could have handled anything.

**Only handler for now.** Registered as the sole entry in `handlers.stock_instances()`. Any row that would previously have gone through `variable-scalar` now falls through to this handler and gets no-op'd. Tests that exercise real dispatch (`$x = 1`, etc.) will fail — expected.
]]
local Handler = require('handler')


local MainHandler = setmetatable({}, {__index = Handler})
MainHandler.__index = MainHandler


function MainHandler.new()
	return setmetatable(Handler.new(), MainHandler)
end


function MainHandler:handle(engine, row)
	-- Stub. Claims every row, does nothing with it. Dispatch logic
	-- lands as the sprint builds up.
	return true
end


return MainHandler
