local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../../../code/lua/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

h.test('trivet.new returns a root Node', function()
	local r = trivet.new('hello')
	h.assert_true(r, 'node exists')
	h.assert_eq(r.value, 'hello')
	h.assert_true(r.is_root, 'is_root')
	h.assert_nil(r.parent, 'no parent')
end)

h.test('trivet.new returns a fresh leaf root', function()
	local r = trivet.new('r')
	h.assert_true(r.is_leaf, 'no children yet')
	h.assert_eq(r.child_count, 0)
end)

h.test('depth is 0 for root, 1 for child, 2 for grandchild', function()
	local r = trivet.new('r')
	local c = r:create_child('c')
	local g = c:create_child('g')
	h.assert_eq(r.depth, 0)
	h.assert_eq(c.depth, 1)
	h.assert_eq(g.depth, 2)
end)

h.test('is_root distinguishes roots from children', function()
	local r = trivet.new('r')
	local c = r:create_child('c')
	h.assert_true(r.is_root)
	h.assert_false(c.is_root)
end)

h.test('is_leaf and has_children', function()
	local r = trivet.new('r')
	h.assert_true(r.is_leaf)
	h.assert_false(r.has_children)
	r:create_child('c')
	h.assert_false(r.is_leaf)
	h.assert_true(r.has_children)
end)

h.test('node.value read and write', function()
	local r = trivet.new('a')
	h.assert_eq(r.value, 'a')
	r.value = 'b'
	h.assert_eq(r.value, 'b')
end)

h.test('node.value can be any Lua type', function()
	h.assert_eq(trivet.new(42).value, 42)
	h.assert_eq(trivet.new(true).value, true)
	local obj = {id = 'x'}
	h.assert_eq(trivet.new(obj).value, obj)
end)

h.test('node.value can be nil', function()
	local r = trivet.new(nil)
	h.assert_nil(r.value)
end)
