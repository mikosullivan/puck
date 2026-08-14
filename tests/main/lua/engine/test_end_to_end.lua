--[[
{
	"spec": "test_end_to_end",
	"role": "Flagship end-to-end test. Runs an empty program through the engine and verifies the returned hash carries `complete` (1) and `message` (nil) — the two-field shape the caller sees when a process runs to completion."
}
]]

--[[
# `test_end_to_end`

Flagship end-to-end. An empty program (`engine.caspm = {}`) goes through the engine; when `run` returns, it hands back a hash with two fields:

- `complete` — `1`, the process finished.
- `message` — `nil`, the empty program set no message.

Everything else along the way (frame 0 pushed, empty ast walked, frame deleted, process marked complete via trigger, process auto-deleted) happens as the design specifies but isn't asserted here — those DB-state checks live in [test_end_to_end_state.lua](https://puck.uno/tests/main/lua/engine/test_end_to_end_state.lua). This test's whole job is: **empty array in → hash with two fields out.**
]]

local h      = require('helpers')
local engine = require('engine')

h.test('empty program end-to-end: run() returns { complete = 1, message = nil }', function()
	local e = engine.new()
	e.caspm = {}

	local returned = e:run()

	h.assert_true(type(returned) == 'table', 'expected run() to return a table')
	h.assert_eq(returned.complete, 1, 'expected returned.complete to be 1')
	h.assert_eq(returned.message, nil, 'expected returned.message to be nil (empty program sets no message)')
end)
