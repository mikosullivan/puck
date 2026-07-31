local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../../../code/lua/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

local function build()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local b = r:create_child('b')
	local c = r:create_child('c')
	local d = r:create_child('d')
	return r, a, b, c, d
end

h.test('siblings excludes self', function()
	local _, a = build()
	h.assert_seq(h.values_of(a:siblings()), {'b', 'c', 'd'})
end)

h.test('siblings for middle node', function()
	local _, _, b = build()
	h.assert_seq(h.values_of(b:siblings()), {'a', 'c', 'd'})
end)

h.test('siblings for last node', function()
	local _, _, _, _, d = build()
	h.assert_seq(h.values_of(d:siblings()), {'a', 'b', 'c'})
end)

h.test('siblings when only child returns empty', function()
	local r = trivet.new('r')
	local only = r:create_child('only')
	h.assert_seq(h.values_of(only:siblings()), {})
end)

h.test('previous_sibling and next_sibling', function()
	local _, a, b, c, d = build()
	h.assert_nil(a.previous_sibling)
	h.assert_eq(a.next_sibling, b)
	h.assert_eq(b.previous_sibling, a)
	h.assert_eq(b.next_sibling, c)
	h.assert_eq(d.previous_sibling, c)
	h.assert_nil(d.next_sibling)
end)

h.test('sibling_index is 1-based', function()
	local _, a, b, c, d = build()
	h.assert_eq(a.sibling_index, 1)
	h.assert_eq(b.sibling_index, 2)
	h.assert_eq(c.sibling_index, 3)
	h.assert_eq(d.sibling_index, 4)
end)

h.test('root has no siblings and nil sibling_index', function()
	local r = trivet.new('r')
	h.assert_seq(h.values_of(r:siblings()), {})
	h.assert_nil(r.previous_sibling)
	h.assert_nil(r.next_sibling)
	h.assert_nil(r.sibling_index)
end)

h.test('removed node has no siblings (it is now a root)', function()
	local _, _, b = build()
	b:remove()
	h.assert_nil(b.sibling_index)
	h.assert_nil(b.previous_sibling)
	h.assert_nil(b.next_sibling)
	h.assert_seq(h.values_of(b:siblings()), {}, 'no siblings once detached')
end)
