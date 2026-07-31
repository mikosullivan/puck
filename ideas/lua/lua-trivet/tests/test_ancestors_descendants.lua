local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../src/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local h = require('helpers')

-- Test tree:
--   r
--   ├─ a
--   │  ├─ a1
--   │  └─ a2
--   ├─ b
--   └─ c
--      └─ c1
--         └─ c1a
local function build()
	local r = trivet.new('r')
	local a = r:create_child('a')
	local a1 = a:create_child('a1')
	local a2 = a:create_child('a2')
	local b = r:create_child('b')
	local c = r:create_child('c')
	local c1 = c:create_child('c1')
	local c1a = c1:create_child('c1a')
	return {r = r, a = a, a1 = a1, a2 = a2, b = b, c = c, c1 = c1, c1a = c1a}
end

h.test('ancestors: leaf to root', function()
	local n = build()
	h.assert_seq(h.values_of(n.c1a:ancestors()), {'c1', 'c', 'r'})
end)

h.test('ancestors: root has none', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:ancestors()), {})
end)

h.test('ancestors: direct child returns just root', function()
	local n = build()
	h.assert_seq(h.values_of(n.b:ancestors()), {'r'})
end)

h.test('descendants pre-order (default)', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:descendants()), {'a', 'a1', 'a2', 'b', 'c', 'c1', 'c1a'})
end)

h.test('descendants pre-order (explicit)', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:descendants('pre')), {'a', 'a1', 'a2', 'b', 'c', 'c1', 'c1a'})
end)

h.test('descendants post-order', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:descendants('post')), {'a1', 'a2', 'a', 'b', 'c1a', 'c1', 'c'})
end)

-- Judgment call: post-order INCLUDES the root itself. This is the standard
-- meaning of post-order traversal (visit children, then node). The spec is
-- silent on whether the starting node is included in descendants; pre-order
-- clearly excludes it (a1 not r first), so post-order for consistency should
-- also exclude the starting node — but post-order without the last-visited
-- node is unusual. Splitting the difference: pre and bfs skip the starting
-- node (per spec's descendants excludes self); post ALSO skips the starting
-- node to keep the "descendants excludes self" invariant. Documented here.
h.test('descendants post-order excludes starting node', function()
	local n = build()
	local vals = h.values_of(n.r:descendants('post'))
	-- 'r' should NOT be in the post-order descendants
	for _, v in ipairs(vals) do
		if v == 'r' then
			error('post-order should exclude the starting node')
		end
	end
end)

h.test('descendants bfs', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:descendants('bfs')), {'a', 'b', 'c', 'a1', 'a2', 'c1', 'c1a'})
end)

h.test('descendants of a leaf is empty', function()
	local n = build()
	h.assert_seq(h.values_of(n.a1:descendants()), {})
	h.assert_seq(h.values_of(n.a1:descendants('post')), {})
	h.assert_seq(h.values_of(n.a1:descendants('bfs')), {})
end)

h.test('descendants raises on unknown order', function()
	local n = build()
	h.assert_raises(function()
		n.r:descendants('bogus')
	end, 'unknown order')
end)

h.test('path_from_root: root to self', function()
	local n = build()
	h.assert_seq(h.values_of(n.c1a:path_from_root()), {'r', 'c', 'c1', 'c1a'})
end)

h.test('path_from_root for root itself is just root', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:path_from_root()), {'r'})
end)

h.test('descendant_count', function()
	local n = build()
	h.assert_eq(n.r.descendant_count, 7)
	h.assert_eq(n.a.descendant_count, 2)
	h.assert_eq(n.a1.descendant_count, 0)
	h.assert_eq(n.c.descendant_count, 2)
end)

h.test('is_ancestor_of and is_descendant_of', function()
	local n = build()
	h.assert_true(n.r:is_ancestor_of(n.a))
	h.assert_true(n.r:is_ancestor_of(n.c1a))
	h.assert_true(n.c:is_ancestor_of(n.c1a))
	h.assert_false(n.a:is_ancestor_of(n.b))
	h.assert_false(n.r:is_ancestor_of(n.r), 'not its own ancestor')
	h.assert_false(n.c1a:is_ancestor_of(n.r), 'descendant is not ancestor')

	h.assert_true(n.c1a:is_descendant_of(n.r))
	h.assert_true(n.c1a:is_descendant_of(n.c))
	h.assert_false(n.r:is_descendant_of(n.c1a))
	h.assert_false(n.r:is_descendant_of(n.r))
end)

h.test('is_ancestor_of across unrelated trees is always false', function()
	local n1 = build()
	local n2 = build()
	h.assert_false(n1.r:is_ancestor_of(n2.a))
	h.assert_false(n1.a:is_descendant_of(n2.r))
end)

h.test('subtree: pre-order includes self first', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:subtree()), {'r', 'a', 'a1', 'a2', 'b', 'c', 'c1', 'c1a'})
end)

h.test('subtree: bfs includes self first', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:subtree('bfs')), {'r', 'a', 'b', 'c', 'a1', 'a2', 'c1', 'c1a'})
end)

h.test('subtree: post-order includes self last', function()
	local n = build()
	h.assert_seq(h.values_of(n.r:subtree('post')), {'a1', 'a2', 'a', 'b', 'c1a', 'c1', 'c', 'r'})
end)

h.test('subtree on leaf yields just self', function()
	local n = build()
	h.assert_seq(h.values_of(n.a1:subtree()), {'a1'})
	h.assert_seq(h.values_of(n.a1:subtree('post')), {'a1'})
	h.assert_seq(h.values_of(n.a1:subtree('bfs')), {'a1'})
end)

h.test('subtree count = descendant_count + 1', function()
	local n = build()
	local count = 0
	for _ in n.r:subtree() do count = count + 1 end
	h.assert_eq(count, n.r.descendant_count + 1)
end)

h.test('subtree raises on unknown order', function()
	local n = build()
	h.assert_raises(function()
		for _ in n.r:subtree('bogus') do end
	end, 'unknown order')
end)
