--[[
{
	"module": "handlers",
	"role": "Aggregator module for the engine's stock Handler subclasses. Individual Handler subclasses live in sibling files (`src/engine/handlers/<name>.lua`); this module requires each one, re-exports it as a field, and provides `stock_instances()` — the list of fresh Handler instances that `engine.new()` populates `row_handlers` with at construction. Adding a new stock handler = adding a new sibling file, requiring it here, exporting it, and appending an instance to the `stock_instances()` list.",
	"exports": {
		"stock_instances": "() -> array of Handler instances — one fresh instance of each stock Handler subclass; called by engine.new() to populate row_handlers"
	},
	"status": "empty — no stock handlers landed yet; first-variable sprint will register the first"
}
]]

--[[
# `handlers`

Aggregator module for the engine's stock Handler subclasses. Currently empty — no handlers have landed yet. The first (a `DispatchAs` subclass for `$x = 1`-style assignments) arrives with the first-variable sprint.

**Adding a new stock handler:**

1. Create a sibling file under `src/engine/handlers/<name>.lua` containing the Handler subclass definition.
2. Add a `require` line in this file.
3. Add the class to the `M.<Name>` exports below (so callers can reach the class directly if they need it — e.g., to subclass it further or reference it in tests).
4. Add a fresh instance to the array returned by `stock_instances()` (so `engine.new()` picks it up automatically at construction).

**Not to be confused with** [`src/engine/handler.lua`](../handler.lua) — that's the base class. This is the aggregator for the concrete subclasses.
]]
local M = {}

local VariableScalar = require('handlers.variable-scalar')
M.VariableScalar = VariableScalar

--[[
## `stock_instances` — fresh instances of every stock handler

Returns an array of newly-constructed Handler instances, one per stock subclass. The engine's `M.new()` calls this and appends each into `self.row_handlers` at construction, so every fresh engine has the standard dispatch chain wired.

Order in the returned array matters — earlier handlers get first shot at each row per the chain-of-responsibility semantics. Specific handlers should come before general ones.

Empty for now; grows as sprints register subclasses.
]]
function M.stock_instances()
	return {
		VariableScalar.new(),
	}
end

return M
