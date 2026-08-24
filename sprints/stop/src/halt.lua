--[[
{
	"module": "halt",
	"role": "The HALT sentinel used by %process.stop to signal a halt via Lua's error() mechanism. Exports a unique table identity that anyone can raise via `halt.raise()` and that engine:run()'s xpcall catches via `halt.is_halt(err)`. Identity-comparing the sentinel (rather than shape-matching a field) means no intermediate error handler can accidentally construct-and-catch a fake halt.",
	"exports": {
		"raise":    "() -> never returns — raises the HALT sentinel via error(). Called by the sprint's ProcessStop handler after the stop frame is inserted.",
		"is_halt":  "(err) -> bool — true iff the caught error is our HALT sentinel. Intermediate pcall sites use this to distinguish halts from other errors so they can re-raise the halt while handling their own expected errors."
	}
}
]]

--[=[
# `halt`

Lua-side halt-signaling sentinel for `%process.stop`.

**The mechanism.** The sprint's ProcessStop handler, after inserting
the stop frame, raises a sentinel via `error()`. Every intermediate
Lua frame between the handler and `engine:run()`'s xpcall unwinds
normally. The top-level `xpcall` catches the raise, checks whether
it's our sentinel via `is_halt`, and returns the appropriate result
hash to the host. Anything that isn't our sentinel gets re-raised.

**Why identity, not shape.** The sentinel is a unique table. Callers
compare via `err.__signal == halt.SENTINEL` — table-identity check.
That's cheaper than string-matching a message and immune to a
handler accidentally constructing a table with the same shape.

**Discipline required.** Any pcall/xpcall in engine code that
catches an error and doesn't expect it MUST re-raise. Otherwise a
halt raised under that pcall gets swallowed and the process just
keeps running. `is_halt(err)` is the check to use before deciding
to handle vs. re-raise.
]=]

local M = {}

-- Unique-identity table. Only this exact table's identity signals a
-- halt; a shape-matched replica does not.
M.SENTINEL = {}

--[[
## `halt.raise`

Raises the HALT sentinel via `error()`. Never returns.
]]
function M.raise()
	error({__signal = M.SENTINEL})
end

--[[
## `halt.is_halt`

Returns true iff `err` is a HALT sentinel raised via `M.raise()`.
]]
function M.is_halt(err)
	return type(err) == 'table' and err.__signal == M.SENTINEL
end


return M
