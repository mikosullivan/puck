--[[
{
	"module": "handler",
	"role": "Base class for row-head dispatch handlers PLUS three temporary test-support subclasses (AlwaysTrue, AlwaysFalse, AlwaysRaise) baked in here so the dispatch mechanism can be tested from day one without a separate test-support file. Instances live in the engine's row-handlers array and get offered each CaspM row via `:handle`. The base defines the interface — one overridable method — and returns false from its default implementation. Concrete handlers subclass and override.",
	"exports": {
		"(module)":    "Handler class table with test-support subclasses attached as fields",
		"Handler.new":         "() -> Handler — bare constructor",
		"Handler:handle":      "(engine, row) -> true | false — override in subclasses",
		"Handler.AlwaysTrue":  "test-support subclass whose :handle always returns true",
		"Handler.AlwaysFalse": "test-support subclass whose :handle always returns false",
		"Handler.AlwaysRaise": "test-support subclass whose :handle always raises"
	},
	"status": "sprint-scoped; test-support subclasses will move out to their own test-support file eventually"
}
]]

--[[
# `handler`

Base class for the dispatch chain's handlers, plus three temporary test-support subclasses attached to the module.

**Contract for real subclasses:**

- Override `:handle(engine, row)`.
- Return `true` if you recognized the row shape and executed it.
- Return `false` if you didn't recognize the shape — the dispatch chain moves on to the next handler.
- Raise a Lua exception if you recognized the shape but hit a problem executing it. Dispatch doesn't catch; the raise propagates to the caller.

**Why a class instead of a bare function.** Handlers can carry state (config, counters, cached prepared statements, log destinations). Shared machinery can live here in the base. Each handler has an identity that surfaces in debugging. Matches the rest of the Lua-object codebase — `engine`, `cvm`, `frame`, `object` are all classes with `.new()` constructors and `:method()` calls.

**Minimal today.** The base is deliberately empty except for `handle` returning `false`. Common shape-check helpers and common error patterns can grow here as concrete handlers surface repeated patterns.

## Test-support subclasses (temporary)

`Handler.AlwaysTrue`, `Handler.AlwaysFalse`, and `Handler.AlwaysRaise` are minimal subclasses that always return `true`, always return `false`, and always raise, respectively. They exist so the dispatch mechanism can be exercised in tests without needing any real row-handling logic. Baked into this file for now because the sprint's test infrastructure is intentionally small; they'll move out to a dedicated test-support file when the sprint scales up.
]]
local Handler = {}
Handler.__index = Handler

--[[
## `Handler.new` — construct a base Handler instance

Returns a bare instance with no state. Subclasses call this from their own `new` to get the base metatable set up, then chain on their own metatable.
]]
function Handler.new()
	return setmetatable({}, Handler)
end

--[[
## `Handler:handle` — default implementation returns false

Base implementation. Any un-overridden Handler instance declines every row (returns `false`), so the dispatch chain moves on. Subclasses override to match and execute row shapes.
]]
function Handler:handle(engine, row)
	return false
end

-- ================================================================
-- Test-support subclasses — temporary, will move to a test-support
-- file once the sprint scales up. Attached to Handler as fields so
-- callers can reach them via `require('handler').AlwaysTrue` etc.
-- ================================================================

--[[
## `Handler.AlwaysTrue` — always returns true from `:handle`

Test-support subclass. Instances always return `true`. Used to exercise the "first `true` wins, loop stops" behavior of the dispatch chain without any real matching logic.
]]
local AlwaysTrue = setmetatable({}, {__index = Handler})
AlwaysTrue.__index = AlwaysTrue

function AlwaysTrue.new()
	return setmetatable(Handler.new(), AlwaysTrue)
end

function AlwaysTrue:handle(engine, row)
	return true
end

Handler.AlwaysTrue = AlwaysTrue

--[[
## `Handler.AlwaysFalse` — always returns false from `:handle`

Test-support subclass. Instances always return `false`. Used to exercise the "handler declines, chain moves on" behavior — and (when it's the only handler in the chain) to exercise the "no handler claimed" fallback raise.
]]
local AlwaysFalse = setmetatable({}, {__index = Handler})
AlwaysFalse.__index = AlwaysFalse

function AlwaysFalse.new()
	return setmetatable(Handler.new(), AlwaysFalse)
end

function AlwaysFalse:handle(engine, row)
	return false
end

Handler.AlwaysFalse = AlwaysFalse

--[[
## `Handler.AlwaysRaise` — always raises from `:handle`

Test-support subclass. Instances always call `error(...)`. Used to exercise "handler raise propagates out of dispatch" and, when paired with an `AlwaysTrue` earlier in the chain, to prove first-wins (dispatch returns cleanly, the AlwaysRaise never fires).
]]
local AlwaysRaise = setmetatable({}, {__index = Handler})
AlwaysRaise.__index = AlwaysRaise

function AlwaysRaise.new()
	return setmetatable(Handler.new(), AlwaysRaise)
end

function AlwaysRaise:handle(engine, row)
	error("always_raise_fired: AlwaysRaise handler is configured to always raise")
end

Handler.AlwaysRaise = AlwaysRaise

return Handler
