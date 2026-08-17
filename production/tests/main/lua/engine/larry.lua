--[[
{
	"module": "larry",
	"role": "Engine subclass intended for use in tests. Inherits everything from `engine`, including the row-handler-chain API. Test-scoped conveniences (like FakeOutput wiring) are opt-in via methods on Larry — the constructor doesn't wire anything the plain Engine wouldn't.",
	"exports": {
		"new": "(opts?) -> Larry — same signature as Engine.new; opts.cvm passes through to cvm.open",
		"set_fake_stdout": "() -> FakeOutput — wires a fresh helpers.FakeOutput into self.stdout and returns it for inspection",
		"set_fake_stderr": "() -> FakeOutput — wires a fresh helpers.FakeOutput into self.stderr and returns it for inspection"
	},
	"depends_on": ["engine", "helpers (for FakeOutput)"]
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

return Larry
