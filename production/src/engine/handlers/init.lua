--[[
{
	"module": "handlers",
	"role": "Aggregator module for the engine's stock Handler subclasses. Individual Handler subclasses live in sibling files (`src/engine/handlers/<name>.lua`); this module requires each one, re-exports it as a field, and provides `stock_instances()` — the list of fresh Handler instances that `engine.new()` populates `row_handlers` with at construction. Adding a new stock handler = adding a new sibling file, requiring it here, exporting it, and appending an instance to the `stock_instances()` list.",
	"exports": {
		"stock_instances": "() -> array of Handler instances — one fresh instance of each stock Handler subclass; called by engine.new() to populate row_handlers"
	},
	"status": "V0.1 — ScalarAtom (value-atom evaluator) → Plus (arithmetic +) → MainHandler (stub general-dispatch for method_call rows). VariableScalar exists as a sibling file but is not registered; it'll come back as an optimization once the main handler covers its cases at general-dispatch speed. `%process.stop` was previously a stock handler but has been removed — it will return as a method on the process object once the core-method registry lands."
}
]]

--[[
# `handlers`

Aggregator module for the engine's stock Handler subclasses.

**Stock chain (order matters):**

1. [`ScalarAtom`](https://puck.uno/production/src/engine/handlers/scalar-atom.lua) — value-atom evaluator. Matches rows of shape `{v: LITERAL}` (a hash carrying a single Caspian scalar); materializes the literal as a scalar and binds it to the frame's `rv` slot. Distinct row shape from method_call, so ordering vs MainHandler is cosmetic.
2. [`Plus`](https://puck.uno/production/src/engine/handlers/plus.lua) — arithmetic `+`. Matches `{cmd:'mc'}` rows with `fn == '+'`. Multi-phase: spawns receiver + arg_0 eval frames, accumulates their values via bucket refs, computes the sum. Must precede MainHandler (which would otherwise error on the shape).
3. [`MainHandler`](https://puck.uno/production/src/engine/handlers/main-handler.lua) — the general CaspM dispatcher being built up. Claims every remaining `{cmd:'mc'}` row.

**Retired.** [`ProcessStop`](https://puck.uno/production/src/engine/handlers/process-stop.lua) — was the stock handler for `%process.stop`. Removed pending its return as a method on the process object under the core-object-methods design. `%process.stop` in a Caspian program will fail with `unrecognized_caspm` until that lands.

**`VariableScalar` deliberately NOT registered.** The file [handlers/variable-scalar.lua](https://puck.uno/production/src/engine/handlers/variable-scalar.lua) still exists on disk and is still `require`-able for its class definition, but it isn't in the stock roster. Once the main handler covers assignment via its general path, `VariableScalar` gets re-added in front of `MainHandler` as a shape-specific optimization that short-circuits the general dispatch.

**Adding a new stock handler:**

1. Create a sibling file under `src/engine/handlers/<name>.lua` containing the Handler subclass definition.
2. Add a `require` line in this file.
3. Add the class to the `M.<Name>` exports below (so callers can reach the class directly if they need it — e.g., to subclass it further or reference it in tests).
4. Add a fresh instance to the array returned by `stock_instances()` (so `engine.new()` picks it up automatically at construction). Specific / short-circuit handlers go before general ones — the array's order IS the chain-of-responsibility order.

**Not to be confused with** [`src/engine/handler.lua`](../handler.lua) — that's the base class. This is the aggregator for the concrete subclasses.
]]
local M = {}

local ScalarAtom = require('handlers.scalar-atom')
M.ScalarAtom = ScalarAtom

local Plus = require('handlers.plus')
M.Plus = Plus

local MainHandler = require('handlers.main-handler')
M.MainHandler = MainHandler

--[[
## `stock_instances` — fresh instances of every stock handler

Returns an array of newly-constructed Handler instances, one per stock subclass. The engine's `M.new()` calls this and appends each into `self.row_handlers` at construction, so every fresh engine has the standard dispatch chain wired.

Order in the returned array matters — earlier handlers get first shot at each row per the chain-of-responsibility semantics. Specific handlers come before general ones.
]]
function M.stock_instances()
	return {
		ScalarAtom.new(),
		Plus.new(),
		MainHandler.new(),
	}
end

return M
