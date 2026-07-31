local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../src/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

local function build()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local b = r:create_child('b')
	local c = r:create_child('c')
	return r, a, b, c
end

h.test('children iterates in insertion order', function()
	local r = build()
	h.assert_seq(h.values_of(r:children()), {'a', 'b', 'c'})
end)

h.test('children returns empty iterator for a leaf', function()
	local r = trivet.new('r')
	h.assert_seq(h.values_of(r:children()), {})
end)

h.test('children returns a snapshot (safe to mutate during iteration)', function()
	local r, a, b = build()
	local seen = {}

	for c in r:children() do
		table.insert(seen, c.value)

		if c == a then
			b:remove()
		end
	end

	h.assert_seq(seen, {'a', 'b', 'c'})
end)

h.test('first_child and last_child', function()
	local r, a, _, c = build()
	h.assert_eq(r.first_child, a)
	h.assert_eq(r.last_child, c)
end)

h.test('first_child and last_child of a leaf are nil', function()
	local r = trivet.new('r')
	h.assert_nil(r.first_child)
	h.assert_nil(r.last_child)
end)

h.test('child_count', function()
	local r = trivet.new('r')
	h.assert_eq(r.child_count, 0)
	r:create_child('a')
	h.assert_eq(r.child_count, 1)
	r:create_child('b')
	h.assert_eq(r.child_count, 2)
end)

h.test('child(index) returns Nth child (1-indexed)', function()
	local r, a, b, c = build()
	h.assert_eq(r:child(1), a)
	h.assert_eq(r:child(2), b)
	h.assert_eq(r:child(3), c)
end)

h.test('child(index) out of range returns nil', function()
	local r = build()
	h.assert_nil(r:child(0))
	h.assert_nil(r:child(99))
	h.assert_nil(r:child(-1))
end)

h.test('parent back-reference is correct', function()
	local r, a, b, c = build()
	h.assert_eq(a.parent, r)
	h.assert_eq(b.parent, r)
	h.assert_eq(c.parent, r)
end)

h.test('create_child returns the new node', function()
	local r = trivet.new('r')
	local c = r:create_child('c')
	h.assert_eq(c.value, 'c')
	h.assert_eq(c.parent, r)
	h.assert_true(c.is_leaf)
end)

h.test('create_child appends at the end', function()
	local r = build()
	local d = r:create_child('d')
	h.assert_eq(r.last_child, d)
	h.assert_eq(r.child_count, 4)
end)

h.test('deep nesting works', function()
	local prev = trivet.new('level_0')

	for i = 1, 20 do
		prev = prev:create_child('level_' .. i)
	end

	h.assert_eq(prev.depth, 20)
	h.assert_eq(prev.value, 'level_20')
end)
