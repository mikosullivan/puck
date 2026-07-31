--[=[
{
	"module": "trivet",
	"role": "Generic n-ary tree library for Lua. Wraps arbitrary values in Node objects; enforces single-parent and no-cycle invariants at every mutation. A tree is defined by its root node — there is no container class. trivet.new(value) returns a fresh root Node.",
	"exports": {
		"new": "value -> a fresh root Node (parent = nil)"
	},
	"invariants": {
		"single_parent": "each node has exactly one parent (or is a root); enforced by construction — every mutation updates node.parent",
		"no_cycles": "create_child / insert_child never produce cycles because they always create a fresh node; move_to walks the target's ancestor chain and refuses if self appears",
		"root_derivation": "a node is a root iff node.parent == nil. No _is_root field, no Trivet container."
	},
	"api_shape": "node-wraps-value: tree logic never touches the wrapped value; the value is opaque"
}
]=]

local M = {}

local Node = {}
local Node_methods = {}
local Node_properties = {}

Node.__index = function(node, key)
	local method = Node_methods[key]

	if method then
		return method
	end

	local prop = Node_properties[key]

	if prop then
		return prop(node)
	end

	return nil
end

local function new_node(value, parent)
	local node = setmetatable({}, Node)
	node.value = value
	node.parent = parent
	node._children = {}
	return node
end

local function remove_from_array(arr, target)
	for i, v in ipairs(arr) do
		if v == target then
			table.remove(arr, i)
			return i
		end
	end

	return nil
end

local function detach_node(node)
	if node.parent then
		remove_from_array(node.parent._children, node)
		node.parent = nil
	end

	return
end

function M.new(value)
	return new_node(value, nil)
end

Node_properties.depth = function(node)
	local d = 0
	local current = node.parent

	while current do
		d = d + 1
		current = current.parent
	end

	return d
end

Node_properties.is_root = function(node)
	return node.parent == nil
end

Node_properties.is_leaf = function(node)
	return #node._children == 0
end

Node_properties.has_children = function(node)
	return #node._children > 0
end

Node_properties.first_child = function(node)
	return node._children[1]
end

Node_properties.last_child = function(node)
	return node._children[#node._children]
end

Node_properties.child_count = function(node)
	return #node._children
end

local function sibling_container(node)
	if node.parent then
		return node.parent._children
	end

	return nil
end

Node_properties.previous_sibling = function(node)
	local container = sibling_container(node)

	if not container then
		return nil
	end

	for i, s in ipairs(container) do
		if s == node then
			return container[i - 1]
		end
	end

	return nil
end

Node_properties.next_sibling = function(node)
	local container = sibling_container(node)

	if not container then
		return nil
	end

	for i, s in ipairs(container) do
		if s == node then
			return container[i + 1]
		end
	end

	return nil
end

Node_properties.sibling_index = function(node)
	local container = sibling_container(node)

	if not container then
		return nil
	end

	for i, s in ipairs(container) do
		if s == node then
			return i
		end
	end

	return nil
end

Node_properties.descendant_count = function(node)
	local function count(n)
		local c = #n._children

		for _, child in ipairs(n._children) do
			c = c + count(child)
		end

		return c
	end

	return count(node)
end

function Node_methods.children(node)
	local snapshot = {}

	for i, c in ipairs(node._children) do
		snapshot[i] = c
	end

	local i = 0
	return function()
		i = i + 1
		return snapshot[i]
	end
end

function Node_methods.child(node, index)
	return node._children[index]
end

function Node_methods.siblings(node)
	local container = sibling_container(node)
	local snapshot = {}

	if container then
		for _, s in ipairs(container) do
			if s ~= node then
				table.insert(snapshot, s)
			end
		end
	end

	local i = 0
	return function()
		i = i + 1
		return snapshot[i]
	end
end

function Node_methods.ancestors(node)
	local current = node.parent
	return function()
		local n = current

		if n then
			current = n.parent
		end

		return n
	end
end

function Node_methods.path_from_root(node)
	local path = {}
	local current = node

	while current do
		table.insert(path, 1, current)
		current = current.parent
	end

	local i = 0
	return function()
		i = i + 1
		return path[i]
	end
end

local function pre_order_iter(root)
	local stack = {}

	for i = #root._children, 1, -1 do
		table.insert(stack, root._children[i])
	end

	return function()
		if #stack == 0 then
			return nil
		end

		local node = table.remove(stack)

		for i = #node._children, 1, -1 do
			table.insert(stack, node._children[i])
		end

		return node
	end
end

local function post_order_iter(root)
	local result = {}

	local function visit(node)
		for _, c in ipairs(node._children) do
			visit(c)
		end

		if node ~= root then
			table.insert(result, node)
		end
	end

	visit(root)
	local i = 0
	return function()
		i = i + 1
		return result[i]
	end
end

local function bfs_iter(root)
	local queue = {}

	for _, c in ipairs(root._children) do
		table.insert(queue, c)
	end

	local head = 1
	return function()
		if head > #queue then
			return nil
		end

		local node = queue[head]
		head = head + 1

		for _, c in ipairs(node._children) do
			table.insert(queue, c)
		end

		return node
	end
end

function Node_methods.descendants(node, order)
	order = order or 'pre'

	if order == 'pre' then
		return pre_order_iter(node)
	end

	if order == 'post' then
		return post_order_iter(node)
	end

	if order == 'bfs' then
		return bfs_iter(node)
	end

	error("trivet.descendants: unknown order " .. tostring(order) .. " (expected 'pre', 'post', or 'bfs')", 2)
end

function Node_methods.subtree(node, order)
	order = order or 'pre'

	if order == 'pre' or order == 'bfs' then
		local desc_iter = node:descendants(order)
		local emitted_self = false
		return function()
			if not emitted_self then
				emitted_self = true
				return node
			end

			return desc_iter()
		end
	elseif order == 'post' then
		local desc_iter = node:descendants('post')
		local emitted_self = false
		return function()
			if emitted_self then
				return nil
			end

			local n = desc_iter()

			if n then
				return n
			end

			emitted_self = true
			return node
		end
	end

	error("trivet.subtree: unknown order " .. tostring(order) .. " (expected 'pre', 'post', or 'bfs')", 2)
end

function Node_methods.walk(node, fn, order)
	for descendant in node:descendants(order) do
		local result = fn(descendant)

		if result ~= nil then
			return result
		end
	end

	return nil
end

function Node_methods.is_ancestor_of(node, other)
	local current = other.parent

	while current do
		if current == node then
			return true
		end

		current = current.parent
	end

	return false
end

function Node_methods.is_descendant_of(node, other)
	return other:is_ancestor_of(node)
end

function Node_methods.create_child(node, value)
	local child = new_node(value, node)
	table.insert(node._children, child)
	return child
end

function Node_methods.insert_child(node, index, value)
	local n = #node._children

	if type(index) ~= 'number' or index < 1 or index > n + 1 or math.floor(index) ~= index then
		error("trivet.insert_child: index " .. tostring(index) .. " out of range (1.." .. tostring(n + 1) .. ")", 2)
	end

	local child = new_node(value, node)
	table.insert(node._children, index, child)
	return child
end

function Node_methods.remove(node)
	detach_node(node)
	return node
end

function Node_methods.move_to(node, new_parent)
	if new_parent == nil then
		error("trivet.move_to: new_parent is nil", 2)
	end

	if new_parent == node then
		error("trivet.move_to: cannot move a node to itself (would create a cycle)", 2)
	end

	local current = new_parent

	while current do
		if current == node then
			error("trivet.move_to: would create a cycle (new_parent is a descendant of self)", 2)
		end

		current = current.parent
	end

	detach_node(node)
	table.insert(new_parent._children, node)
	node.parent = new_parent
	return
end

local function move_relative(node, sibling, offset, method_name)
	if sibling == nil then
		error("trivet." .. method_name .. ": sibling is nil", 2)
	end

	if node == sibling then
		return
	end

	if node.parent == nil or node.parent ~= sibling.parent then
		error("trivet." .. method_name .. ": nodes do not share a parent", 2)
	end

	local container = node.parent._children
	remove_from_array(container, node)

	for i, s in ipairs(container) do
		if s == sibling then
			table.insert(container, i + offset, node)
			return
		end
	end

	error("trivet." .. method_name .. ": sibling not found in shared parent (internal invariant broken)", 2)
end

function Node_methods.move_before(node, sibling)
	move_relative(node, sibling, 0, 'move_before')
	return
end

function Node_methods.move_after(node, sibling)
	move_relative(node, sibling, 1, 'move_after')
	return
end

return M
