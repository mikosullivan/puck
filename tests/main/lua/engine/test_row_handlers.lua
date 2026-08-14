--[[
{
	"spec": "test_row_handlers",
	"role": "Tests for the row-handler chain public API on Engine: add_handler, prepend_handler, remove_handler, clear_handlers, handlers. Verifies mutation shape, chaining, front vs back positioning, identity-based removal, fail-loudly on missing removal, empty-after-clear, and the copy semantics of handlers()."
}
]]

--[[
# `test_row_handlers`

Public-API tests for the engine's row-handler chain. Every case here
exercises one of the five surface methods (`add_handler`,
`prepend_handler`, `remove_handler`, `clear_handlers`, `handlers`)
against a fresh engine, and reads the underlying `row_handlers` array
only where the test is asserting on the observable effect.

The `remove_handler` cases include the fail-loudly-early path: a
`handler_not_found` raise when the caller tries to remove a handler
that isn't in the chain, rather than a silent no-op.
]]

local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h = require('helpers')
local engine = require('engine')

h.test("add_handler appends to row_handlers", function()
	local e = engine.new()
	local stock_count = #e.row_handlers
	local handler = {}
	e:add_handler(handler)
	h.assert_true(#e.row_handlers == stock_count + 1, "expected chain length to grow by 1")
	h.assert_true(e.row_handlers[#e.row_handlers] == handler, "expected new handler at the end of the chain")
end)

h.test("add_handler returns self for chaining", function()
	local e = engine.new()
	local returned = e:add_handler({})
	h.assert_true(returned == e, "expected add_handler to return self")
end)

h.test("prepend_handler inserts at index 1", function()
	local e = engine.new()
	local handler = {}
	e:prepend_handler(handler)
	h.assert_true(e.row_handlers[1] == handler, "expected new handler at the front of the chain")
end)

h.test("prepend_handler returns self for chaining", function()
	local e = engine.new()
	local returned = e:prepend_handler({})
	h.assert_true(returned == e, "expected prepend_handler to return self")
end)

h.test("prepend_handler orders itself before stock handlers", function()
	local e = engine.new()
	local stock_first = e.row_handlers[1]
	local handler = {}
	e:prepend_handler(handler)
	h.assert_true(e.row_handlers[1] == handler, "new handler is at index 1")
	h.assert_true(e.row_handlers[2] == stock_first, "previous first handler shifted to index 2")
end)

h.test("remove_handler removes by identity", function()
	local e = engine.new()
	local handler = {}
	e:add_handler(handler)
	local before = #e.row_handlers
	e:remove_handler(handler)
	h.assert_true(#e.row_handlers == before - 1, "expected chain length to shrink by 1")

	local still_present = false

	for _, x in ipairs(e.row_handlers) do
		if x == handler then still_present = true end
	end

	h.assert_true(not still_present, "expected handler to be gone from the chain")
end)

h.test("remove_handler returns self for chaining", function()
	local e = engine.new()
	local handler = {}
	e:add_handler(handler)
	local returned = e:remove_handler(handler)
	h.assert_true(returned == e, "expected remove_handler to return self")
end)

h.test("remove_handler raises handler_not_found when handler is not in the chain", function()
	local e = engine.new()
	local handler = {}
	local ok, err = pcall(function() e:remove_handler(handler) end)
	h.assert_true(not ok, "expected an error to be raised")
	h.assert_true(
		tostring(err):find("handler_not_found") ~= nil,
		"expected error to mention handler_not_found; got: " .. tostring(err)
	)
end)

h.test("remove_handler removes only the first occurrence when the same handler is added twice", function()
	local e = engine.new()
	e:clear_handlers()
	local handler = {}
	e:add_handler(handler)
	e:add_handler(handler)
	h.assert_true(#e.row_handlers == 2, "sanity: chain has two entries")
	e:remove_handler(handler)
	h.assert_true(#e.row_handlers == 1, "one entry left after single remove")
	h.assert_true(e.row_handlers[1] == handler, "remaining entry is still the handler")
end)

h.test("clear_handlers empties the chain", function()
	local e = engine.new()
	e:clear_handlers()
	h.assert_true(#e.row_handlers == 0, "expected chain to be empty after clear")
end)

h.test("clear_handlers returns self for chaining", function()
	local e = engine.new()
	local returned = e:clear_handlers()
	h.assert_true(returned == e, "expected clear_handlers to return self")
end)

h.test("handlers() returns the chain in order", function()
	local e = engine.new()
	e:clear_handlers()
	local h1, h2, h3 = {}, {}, {}
	e:add_handler(h1)
	e:add_handler(h2)
	e:add_handler(h3)

	local list = e:handlers()

	h.assert_true(#list == 3, "expected handlers() to return 3 items")
	h.assert_true(list[1] == h1, "list[1] is h1")
	h.assert_true(list[2] == h2, "list[2] is h2")
	h.assert_true(list[3] == h3, "list[3] is h3")
end)

h.test("handlers() returns a copy — mutating the returned list does NOT affect the live chain", function()
	local e = engine.new()
	local list = e:handlers()
	local before = #e.row_handlers
	table.insert(list, {})
	h.assert_true(
		#e.row_handlers == before,
		"live row_handlers should be unchanged after mutating the returned list"
	)
end)
