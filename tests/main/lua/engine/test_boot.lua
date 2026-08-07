local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h      = require('helpers')
local engine = require('engine')

--[[
## Drinian is created on boot

`engine.new()` is the boot entry point; its first act is to construct
a fresh Drinian state hash (via `state.new()`) and stash it as
`engine.state`. Everything downstream in the engine reads and writes
through that hash.
]]

h.test("engine.new() creates a state hash on boot", function()
	local e = engine.new()
	h.assert_true(e.state ~= nil, "engine.state is populated at construction")
end)

h.test("engine.new()'s state has every top-level Drinian field", function()
	local e = engine.new()
	h.assert_true(e.state.roles      ~= nil, "roles present")
	h.assert_true(e.state.srcs       ~= nil, "srcs present")
	h.assert_true(e.state.objects    ~= nil, "objects present")
	h.assert_true(e.state.references ~= nil, "references present")
	h.assert_true(e.state.call_stack ~= nil, "call_stack present")
	h.assert_true(e.state.gc_errors  ~= nil, "gc_errors present")
	h.assert_true(e.state.asts       ~= nil, "asts present")
	h.assert_true(e.state.sequence   ~= nil, "sequence present")
end)

h.test("engine.new()'s state bootstraps roles with engine at root and user as child", function()
	local e = engine.new()
	h.assert_eq(e.state.roles.value.name, 'engine',        "root role is engine")
	h.assert_eq(e.state.roles.child_count, 1,              "engine has one child")
	h.assert_eq(e.state.roles:child(1).value.name, 'user', "child is user")
end)

--[[
## The sequence system works via engine.state

Every allocation in the engine goes through
`engine.state.sequence:next()`. First call after boot returns `"1"`;
each subsequent call advances by one; two engines get independent
sequences.
]]

h.test("engine.state.sequence:next() returns '1' on the first call after boot", function()
	local e = engine.new()
	h.assert_eq(e.state.sequence:next(), '1', "first ID via engine.state.sequence")
end)

h.test("engine.state.sequence:next() hands out sequential IDs", function()
	local e = engine.new()
	h.assert_eq(e.state.sequence:next(), '1', "first ID")
	h.assert_eq(e.state.sequence:next(), '2', "second ID")
	h.assert_eq(e.state.sequence:next(), '3', "third ID")
end)

h.test("each engine.new() gets its own state and its own sequence", function()
	local e1 = engine.new()
	local e2 = engine.new()
	e1.state.sequence:next()
	e1.state.sequence:next()
	h.assert_eq(e1.state.sequence:next(), '3', "e1 is on its third handout")
	h.assert_eq(e2.state.sequence:next(), '1', "e2 is still on its first — independent state")
end)
