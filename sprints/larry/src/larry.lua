--[[
{
	"module": "larry",
	"role": "Engine subclass intended for use in tests. Inherits everything from `engine`. Test-scoped conveniences (like FakeOutput wiring) and the prototype row-handler-chain API (add/prepend/remove/clear/handlers) live on Larry until integration promotes them into Engine.",
	"exports": {
		"new": "(opts?) -> Larry — same signature as Engine.new; opts.cvm passes through to cvm.open",
		"set_fake_stdout": "() -> FakeOutput — wires a fresh helpers.FakeOutput into self.stdout and returns it for inspection",
		"set_fake_stderr": "() -> FakeOutput — wires a fresh helpers.FakeOutput into self.stderr and returns it for inspection",
		"add_handler": "(handler) -> self — appends a handler to the end of self.row_handlers",
		"prepend_handler": "(handler) -> self — inserts a handler at index 1 of self.row_handlers (front of the chain, wins over stock handlers)",
		"remove_handler": "(handler) -> self — removes the first occurrence of `handler` by identity; raises `handler_not_found` if not in the chain",
		"clear_handlers": "() -> self — empties self.row_handlers (including stock handlers); subsequent rows raise unrecognized_row_head until at least one handler is added back",
		"handlers": "() -> array — returns a shallow copy of self.row_handlers, in chain order (index 1 is checked first at dispatch time)"
	},
	"depends_on": ["engine", "helpers (for FakeOutput)"],
	"status": "sprint-scoped",
	"promotion_target": {
		"issue": "https://github.com/mikosullivan/puck/issues/1622",
		"note": "add_handler / prepend_handler / remove_handler / clear_handlers / handlers move down to src/engine/engine.lua at integration"
	}
}
]]

--[[
# `larry`

Engine subclass. A Larry IS an engine — inherits `M.new`, `M:load`, `M:run`, `M:run_row`, `row_handlers`, everything. Tests interact with a Larry the same way they would with a plain Engine, plus whatever conveniences Larry has grown.

**Conveniences are opt-in.** `Larry.new()` doesn't auto-wire anything a plain Engine wouldn't — `self.stdout` stays nil by default, same as an Engine. Tests that need a captured stdout call `larry:set_fake_stdout()` explicitly. Keeps the default construction shape identical to Engine's, so a test that constructs a Larry but doesn't touch the conveniences behaves exactly like a plain Engine.
]]
local Engine  = require('engine')
local helpers = require('helpers')

local Larry = setmetatable({}, {__index = Engine})
Larry.__index = Larry

--[[
## `Larry.new` — construct a Larry instance

Delegates to `Engine.new(opts)` for the base instance and rewraps the metatable so the returned instance's identity is Larry. No slot changes beyond that — construction shape identical to `Engine.new(opts)`.

Method lookups on the returned instance:

- Larry-defined methods win first (via `Larry.__index = Larry`).
- Then Engine methods (via Larry's own metatable, `__index = Engine`).
- Then anything in Engine's own `__index` chain.
]]
function Larry.new(opts)
	local larry = Engine.new(opts)
	return setmetatable(larry, Larry)
end

--[[
## `Larry:set_fake_stdout` — wire a fresh FakeOutput into self.stdout

Creates a new `helpers.FakeOutput` instance, assigns it to `self.stdout`, and returns it so the caller can inspect captured output later without re-reading the slot:

~~~lua
local fake = larry:set_fake_stdout()
larry:load('...')
larry:run()
local out = fake:get_all()
~~~

Explicit rather than auto-wired at construction: tests that don't need captured output get the default Engine shape (nil stdout) unchanged, matching the "convenience features are opt-in" contract.
]]
function Larry:set_fake_stdout()
	self.stdout = helpers.FakeOutput.new()
	return self.stdout
end

--[[
## `Larry:set_fake_stderr` — wire a fresh FakeOutput into self.stderr

Same shape as `set_fake_stdout`, targeting `self.stderr` instead. Uses the same `helpers.FakeOutput` class — nothing about it is stdout-specific; it's a byte-capturing sink that satisfies the `:print(text)` contract regardless of which slot it lands in.

Note that the Engine class doesn't yet formally declare a `stderr` slot (its constructor sets up `stdout` and `debugger` but not `stderr`). Larry's `set_fake_stderr` creates the field on the Larry instance regardless; when Engine grows a real `stderr` slot, this method just wires it.
]]
function Larry:set_fake_stderr()
	self.stderr = helpers.FakeOutput.new()
	return self.stderr
end

--[[
## `Larry:add_handler` — append a handler to the row-handler chain

Appends `handler` to `self.row_handlers`. Chain order matters: handlers are consulted in order at dispatch time, first one to claim the row wins. Appending puts the new handler behind everything already registered (stock handlers included). Returns `self` for chaining.

Prototype surface for [#1622](https://github.com/mikosullivan/puck/issues/1622); moves down to Engine at integration.
]]
function Larry:add_handler(handler)
	table.insert(self.row_handlers, handler)
	return self
end

--[[
## `Larry:prepend_handler` — insert a handler at the front of the row-handler chain

Puts `handler` at index 1 of `self.row_handlers`. First handler consulted at dispatch time — wins over anything already registered, including the stock handlers wired at construction. Returns `self` for chaining.
]]
function Larry:prepend_handler(handler)
	table.insert(self.row_handlers, 1, handler)
	return self
end

--[[
## `Larry:remove_handler` — remove a handler by identity

Removes the first occurrence of `handler` from `self.row_handlers` by identity (`==`). If `handler` is not in the chain, raises `handler_not_found: handler is not in the chain` — fail loudly rather than silently no-op, so a mistyped reference or double-remove surfaces at the call site. Returns `self` for chaining.
]]
function Larry:remove_handler(handler)
	for i, h in ipairs(self.row_handlers) do
		if h == handler then
			table.remove(self.row_handlers, i)
			return self
		end
	end

	error("handler_not_found: handler is not in the chain")
end

--[[
## `Larry:clear_handlers` — empty the row-handler chain

Removes every handler from `self.row_handlers`, including the stock handlers wired at construction. After a `clear_handlers` every row raises `unrecognized_row_head` at dispatch time until at least one handler is added back. Returns `self` for chaining.
]]
function Larry:clear_handlers()
	self.row_handlers = {}
	return self
end

--[[
## `Larry:handlers` — read the current row-handler chain

Returns a shallow copy of `self.row_handlers` as a new array, so inspection doesn't hand out a reference callers could mutate to bypass the public API. Chain order is preserved — index 1 is the first handler consulted at dispatch time.

Callers that want to mutate the chain go through `add_handler`, `prepend_handler`, `remove_handler`, or `clear_handlers`.
]]
function Larry:handlers()
	local copy = {}

	for i, h in ipairs(self.row_handlers) do
		copy[i] = h
	end

	return copy
end

return Larry
