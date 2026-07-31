local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../src/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

local function build()
	local r = trivet.new('r')
	local a = r:create_child('a')
	a:create_child('a1')
	a:create_child('a2')
	r:create_child('b')
	local c = r:create_child('c')
	c:create_child('c1')
	return r
end

h.test('walk visits every descendant in pre-order by default', function()
	local r = build()
	local seen = {}

	r:walk(function(node)
		table.insert(seen, node.value)
	end)

	h.assert_seq(seen, {'a', 'a1', 'a2', 'b', 'c', 'c1'})
end)

h.test('walk with explicit pre-order', function()
	local r = build()
	local seen = {}

	r:walk(function(node)
		table.insert(seen, node.value)
	end, 'pre')

	h.assert_seq(seen, {'a', 'a1', 'a2', 'b', 'c', 'c1'})
end)

h.test('walk with post-order', function()
	local r = build()
	local seen = {}

	r:walk(function(node)
		table.insert(seen, node.value)
	end, 'post')

	h.assert_seq(seen, {'a1', 'a2', 'a', 'b', 'c1', 'c'})
end)

h.test('walk with bfs', function()
	local r = build()
	local seen = {}

	r:walk(function(node)
		table.insert(seen, node.value)
	end, 'bfs')

	h.assert_seq(seen, {'a', 'b', 'c', 'a1', 'a2', 'c1'})
end)

h.test('walk does not include the starting node', function()
	local r = build()
	local seen = {}

	r:walk(function(node)
		table.insert(seen, node.value)
	end)

	for _, v in ipairs(seen) do
		if v == 'r' then
			error('walk should not include the starting node')
		end
	end
end)

h.test('walk on a leaf does not call fn', function()
	local r = trivet.new('r')
	local calls = 0

	r:walk(function()
		calls = calls + 1
	end)

	h.assert_eq(calls, 0)
end)

h.test('walk from an inner node', function()
	local r = build()
	local a = r.first_child
	local seen = {}

	a:walk(function(node)
		table.insert(seen, node.value)
	end)

	h.assert_seq(seen, {'a1', 'a2'})
end)

h.test('walk raises on unknown order', function()
	local r = build()
	h.assert_raises(function()
		r:walk(function() end, 'bogus')
	end, 'unknown order')
end)

h.test('walk returns non-nil callback value and stops', function()
	local r = build()
	local visited = {}
	local result = r:walk(function(node)
		table.insert(visited, node.value)

		if node.value == 'b' then
			return 'found ' .. node.value
		end

		return nil
	end)
	h.assert_eq(result, 'found b', 'returns the callback value')
	h.assert_eq(visited[#visited], 'b', 'stops after match')
end)

h.test('walk returns nil when callback never returns non-nil', function()
	local r = build()
	local result = r:walk(function() return nil end)
	h.assert_eq(result, nil, 'returns nil')
end)

h.test('walk returns false is treated as continue (only non-nil stops)', function()
	local r = build()
	local count = 0
	local result = r:walk(function()
		count = count + 1
		return nil
	end)
	h.assert_eq(result, nil, 'returns nil')
	h.assert_eq(count > 1, true, 'visited more than one node')
end)
