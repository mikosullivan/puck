--[[
{
	"module": "dispatch",
	"role": "Row-head dispatch function. Walks an array of Handler instances calling `:handle` on each; stops at the first handler that returns true. Raises `unrecognized_caspm` if no handler claims. Handler raises propagate — dispatch doesn't catch.",
	"exports": {
		"(function)": "(handlers, ...) -> nil — variadic after handlers; extra args forward to each handler:handle"
	},
	"depends_on": ["handler (only through duck-typed :handle method calls)"],
	"status": "sprint-scoped"
}
]]

--[[
# `dispatch`

Row-head dispatch — the function that turns "here's an array of handlers, please dispatch this input" into either a clean return (some handler claimed it) or a raise (none did).

**Signature.** `dispatch(handlers, ...)`. Handlers is the array. Everything after is passthrough — forwarded to each handler's `:handle(...)` call. Dispatch doesn't inspect the trailing args; that's the handlers' business.

**Semantics.**

- Iterate `handlers` in order.
- For each handler, call `handler:handle(...)` with whatever extra args dispatch received.
- If the call returns `true`, dispatch returns.
- If the call returns `false` (or nil), continue to the next handler.
- If no handler returns `true`, dispatch raises `unrecognized_caspm`.
- If a handler raises, the raise propagates through dispatch to the caller — not caught.

Two-channel contract for handlers is enforced by this loop shape: the boolean return picks whether the loop advances or stops; a raise bypasses the loop entirely. Dispatch never overloads one channel to mean the other.

**Typical caller.** `Frame:run_row` calls this with `dispatch(self.engine.row_handlers, self, row, restart)` — passing the currently-walking Frame, the row, and the restart flag as the trailing args. Each handler's `:handle(frame, row, restart)` then receives all three. But dispatch itself doesn't know or care about that convention; it just forwards.
]]
local function dispatch(handlers, ...)
	for _, handler in ipairs(handlers) do
		if handler:handle(...) then
			return
		end
	end

	error("unrecognized_caspm: no handler in the chain recognized the input")
end

return dispatch
