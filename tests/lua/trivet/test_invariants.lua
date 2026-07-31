local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../../../code/lua/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

h.test('single parent: each child has exactly one parent link', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local b = r:create_child('b')
	h.assert_eq(a.parent, r)
	h.assert_eq(b.parent, r)
	-- The same value can appear twice, but they are distinct NODES:
	local a_dup = r:create_child('a')
	h.assert_false(a == a_dup, 'distinct nodes even with same value')
end)

h.test('single parent: moving a node into a new parent removes from old', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local b = r:create_child('b')
	local x = a:create_child('x')
	x:move_to(b)
	-- x should NOT still be in a's children
	local a_children = {}

	for c in a:children() do
		table.insert(a_children, c)
	end

	h.assert_eq(#a_children, 0, 'a has no children after move')
	local b_children = {}

	for c in b:children() do
		table.insert(b_children, c)
	end

	h.assert_eq(#b_children, 1, 'b has one child after move')
	h.assert_eq(x.parent, b, 'x parent updated')
end)

h.test('no cycles: move_to self raises', function()
	local r = trivet.new('r')
	h.assert_raises(function()
		r:move_to(r)
	end, 'cycle')
end)

h.test('no cycles: move_to descendant raises', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local a1 = a:create_child('a1')
	local a1x = a1:create_child('a1x')
	h.assert_raises(function()
		r:move_to(a1x)
	end, 'cycle')
	h.assert_raises(function()
		a:move_to(a1)
	end, 'cycle')
	h.assert_raises(function()
		a:move_to(a1x)
	end, 'cycle')
end)

h.test('no cycles: create_child cannot create a cycle (fresh nodes only)', function()
	-- create_child takes a VALUE, not a node — cannot introduce an existing node
	-- as a child. This is enforced by the API shape (there is no accept-a-node
	-- form of create_child).
	local r = trivet.new('r')
	local a = r:create_child('a')
	-- Trying to "pass a node in" would just wrap the node-as-value in a new node
	local weird = r:create_child(a)
	h.assert_eq(weird.value, a, 'value is the wrapped node object')
	h.assert_false(weird == a, 'but weird is a new node, not a')
	h.assert_eq(weird.parent, r)
end)

h.test('root distinguishability: is_root true only for roots', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local a1 = a:create_child('a1')
	h.assert_true(r.is_root)
	h.assert_false(a.is_root)
	h.assert_false(a1.is_root)
end)

h.test('removed node becomes a root', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local detached = a:remove()
	h.assert_eq(detached, a, 'remove returns the detached node itself')
	h.assert_true(a.is_root, 'removed node has no parent, so is root')
	h.assert_nil(a.parent)
end)

h.test('root distinguishability: demoted root is not a root', function()
	local a = trivet.new('a')
	local b = trivet.new('b')
	b:move_to(a)
	h.assert_true(a.is_root)
	h.assert_false(b.is_root, 'demoted root loses is_root')
end)

h.test('detached node retains subtree structure', function()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local a1 = a:create_child('a1')
	local a1x = a1:create_child('a1x')
	a:remove()
	-- Subtree still walkable
	local seen = {}

	a:walk(function(node)
		table.insert(seen, node.value)
	end)

	h.assert_seq(seen, {'a1', 'a1x'})
	h.assert_eq(a1.parent, a)
	h.assert_eq(a1x.parent, a1)
end)

h.test('independent trees coexist without any link', function()
	local a = trivet.new('a')
	local b = trivet.new('b')
	local c = trivet.new('c')
	h.assert_true(a.is_root)
	h.assert_true(b.is_root)
	h.assert_true(c.is_root)
	h.assert_false(a:is_ancestor_of(b), 'unrelated roots have no ancestry')
	h.assert_eq(a.depth, 0)
end)
