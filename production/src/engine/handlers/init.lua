--[[
{
	"module": "handlers",
	"role": "Aggregator module for the engine's stock Handler subclasses. Individual Handler subclasses live in sibling files (`src/engine/handlers/<name>.lua`); this module requires each one, re-exports it as a field, and provides `stock_instances()` — the list of fresh Handler instances that `engine.new()` populates `row_handlers` with at construction. Adding a new stock handler = adding a new sibling file, requiring it here, exporting it, and appending an instance to the `stock_instances()` list.",
	"exports": {
		"stock_instances": "() -> array of Handler instances — one fresh instance of each stock Handler subclass; called by engine.new() to populate row_handlers"
	},
	"status": "V0.1 — MainHandler (stub) is the only stock handler. VariableScalar exists as a sibling file but is not registered; it'll come back as an optimization once the main handler covers its cases at general-dispatch speed. %process.stop is dispatched by Engine:run_row to Engine:process_stop as a system primitive (not a handler)."
}
]]

--[[
# `handlers`

Aggregator module for the engine's stock Handler subclasses. Currently one handler is registered: [`MainHandler`](https://puck.uno/src/engine/handlers/main-handler.lua) — a stub for the general CaspM dispatcher being built up.

**`VariableScalar` deliberately NOT registered.** The file [handlers/variable-scalar.lua](https://puck.uno/src/engine/handlers/variable-scalar.lua) still exists on disk and is still `require`-able for its class definition, but it isn't in the stock roster. Once the main handler covers assignment via its general path, `VariableScalar` gets re-added in front of `MainHandler` as a shape-specific optimization that short-circuits the general dispatch.

**`%process.stop` is not a handler.** The stop primitive lives on the engine as `Engine:process_stop`, called by `Engine:run_row` on row-shape match — a system-level primitive, not a user-extensible dispatch shape.

**Adding a new stock handler:**

1. Create a sibling file under `src/engine/handlers/<name>.lua` containing the Handler subclass definition.
2. Add a `require` line in this file.
3. Add the class to the `M.<Name>` exports below (so callers can reach the class directly if they need it — e.g., to subclass it further or reference it in tests).
4. Add a fresh instance to the array returned by `stock_instances()` (so `engine.new()` picks it up automatically at construction).

**Not to be confused with** [`src/engine/handler.lua`](../handler.lua) — that's the base class. This is the aggregator for the concrete subclasses.
]]
local M = {}

local MainHandler = require('handlers.main-handler')
M.MainHandler = MainHandler

--[[
## `stock_instances` — fresh instances of every stock handler

Returns an array of newly-constructed Handler instances, one per stock subclass. The engine's `M.new()` calls this and appends each into `self.row_handlers` at construction, so every fresh engine has the standard dispatch chain wired.

Order in the returned array matters — earlier handlers get first shot at each row per the chain-of-responsibility semantics. Specific handlers should come before general ones.
]]
function M.stock_instances()
	return {
		MainHandler.new(),
	}
end

return M
