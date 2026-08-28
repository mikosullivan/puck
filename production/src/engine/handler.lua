--[[
{
	"module": "handler",
	"role": "Base class for row-head dispatch handlers. Instances live in the engine's row_handlers array and get offered each CaspM row via `:handle`. The base defines the interface — one overridable method — and returns false from its default implementation. Concrete handlers subclass and override to match specific row shapes and execute them.",
	"exports": {
		"new":    "() -> Handler — bare constructor; instances have no state at the base level",
		"handle": "(frame, row, restart?) -> true | false — override in subclasses; return true if this handler recognized AND executed the row, false if it didn't recognize the shape; raise if it recognized but hit a problem. Truthy `restart` means the current statement is being picked up mid-execution (post-halt or after a completed child), the handler's cue to check for prior work before starting fresh; base implementations ignore it"
	},
	"status": "walking-skeleton"
}
]]

--[[
# `handler`

Base class for the dispatch chain's handlers. The dispatch function walks an array of handler instances calling `:handle(frame, row, restart)` on each; the first that returns `true` wins.

**Contract for subclasses:**

- Override `:handle(frame, row, restart)`.
- Return `true` if you recognized the row shape and executed it.
- Return `false` if you didn't recognize the shape — the dispatch chain will move on to the next handler.
- Raise a Lua exception if you recognized the shape but hit a problem executing it. Dispatch doesn't catch; the raise propagates out to the caller.

**The `restart` arg.** Truthy when the walker is picking up an in-progress statement — either after a resume-from-halt or (later) after a child evaluation frame reaped and phase 2 needs to run. Handlers that don't care about two-phase dispatch ignore it. Handlers that do care check it to distinguish "start this statement fresh" from "complete the work already in progress" (typically by inspecting `frame.rv` or a similar persisted state marker).

**Why a class instead of a bare function.** Handlers can carry state (config, counters, cached prepared statements, log destinations). Shared machinery can live here in the base. Each handler has an identity that surfaces in debugging. Matches the rest of the Lua-object codebase — `engine`, `cvm`, `frame`, `object` are all classes with `.new()` constructors and `:method()` calls.

**Minimal today.** The base is deliberately empty except for `handle` returning `false`. Common shape-check helpers and common error patterns can grow here as concrete handlers surface repeated patterns.
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

Base implementation. Any un-overridden Handler instance declines every row (returns `false`), so the dispatch chain moves on. Subclasses override to match and execute row shapes. The `restart` arg is ignored at the base level; subclasses that care wire it in.
]]
function Handler:handle(frame, row, restart)
	return false
end

return Handler
