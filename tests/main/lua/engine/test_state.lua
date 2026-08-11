local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h     = require('helpers')
local state = require('state')

--[[
## Constructor shape

`state.new()` returns a hash with every top-level CVM field present
at its empty representation, plus a fresh Sequence and the roles tree
bootstrapped with `engine` at the root and `user` as its only child.
]]

h.test('state.new() returns a hash with all eight top-level fields present', function()
	local s = state.new()
	h.assert_true(s.roles      ~= nil, 'roles present')
	h.assert_true(s.srcs       ~= nil, 'srcs present')
	h.assert_true(s.objects    ~= nil, 'objects present')
	h.assert_true(s.references ~= nil, 'references present')
	h.assert_true(s.call_stack ~= nil, 'call_stack present')
	h.assert_true(s.gc_errors  ~= nil, 'gc_errors present')
	h.assert_true(s.asts       ~= nil, 'asts present')
	h.assert_true(s.sequence   ~= nil, 'sequence present')
end)

h.test('state.new() bootstraps roles with engine at root and user as its child', function()
	local s = state.new()
	h.assert_eq(s.roles.value.name, 'engine',        'root role is engine')
	h.assert_true(s.roles.is_root,                   'roles tree root has no parent')
	h.assert_eq(s.roles.child_count, 1,              'engine has one child')
	h.assert_eq(s.roles:child(1).value.name, 'user', 'the child is user')
	h.assert_eq(s.roles:child(1).depth, 1,           'user is at depth 1')
end)

h.test('state.new() wires a Sequence whose first :next() returns "1"', function()
	local s = state.new()
	h.assert_eq(s.sequence:next(), '1', 'first ID from the state Sequence is "1"')
end)

h.test('state.new() gives each fresh state its own roles tree', function()
	local s1 = state.new()
	local s2 = state.new()
	s1.roles:create_child({name = 'library:foo'})
	h.assert_eq(s1.roles.child_count, 2, 's1 got the new child')
	h.assert_eq(s2.roles.child_count, 1, 's2 was not affected')
end)

h.test('state.new() gives each fresh state its own Sequence', function()
	local s1 = state.new()
	local s2 = state.new()
	s1.sequence:next()
	s1.sequence:next()
	h.assert_eq(s1.sequence:next(), '3', 's1 is on its third handout')
	h.assert_eq(s2.sequence:next(), '1', 's2 is still on its first')
end)
