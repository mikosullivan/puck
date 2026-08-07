local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h     = require('helpers')
local roles = require('roles')

--[[
## The Role constructor

`roles.new(name)` creates a fresh Role with the given name. Names are
opaque strings — the engine doesn't parse them or derive meaning from
their contents.
]]

h.test("roles.new(name) creates a Role with the given name", function()
	local r = roles.new('engine')
	h.assert_eq(r.name, 'engine', "name field is set")
end)

h.test("roles.new accepts arbitrary opaque strings", function()
	local r1 = roles.new('engine')
	local r2 = roles.new('user')
	local r3 = roles.new('markdown.uno/render')
	local r4 = roles.new('r0')

	h.assert_eq(r1.name, 'engine',              "engine role")
	h.assert_eq(r2.name, 'user',                "user role")
	h.assert_eq(r3.name, 'markdown.uno/render', "url-shaped role name")
	h.assert_eq(r4.name, 'r0',                  "opaque short name")
end)

h.test("each roles.new() call returns a distinct instance", function()
	local r1 = roles.new('engine')
	local r2 = roles.new('engine')
	h.assert_true(r1 ~= r2, "two roles.new() calls produce distinct tables even with the same name")
end)

--[[
## Boot creates the engine and user roles

The two roles V1 always starts with. Verified via state.new() (the
role-tree bootstrap that state uses).
]]

h.test("boot creates the engine role at the root of the role tree", function()
	local state = require('state')
	local s = state.new()
	h.assert_eq(s.roles.value.name, 'engine', "root role is engine")
end)

h.test("boot creates the user role as engine's child", function()
	local state = require('state')
	local s = state.new()
	h.assert_eq(s.roles.child_count, 1,              "engine has exactly one child at boot")
	h.assert_eq(s.roles:child(1).value.name, 'user', "the child is user")
end)

h.test("boot-created roles are Role instances, not bare hashes", function()
	local state = require('state')
	local s = state.new()
	local engine_role = s.roles.value
	local user_role   = s.roles:child(1).value

	h.assert_true(getmetatable(engine_role) ~= nil, "engine role has a metatable")
	h.assert_true(getmetatable(user_role)   ~= nil, "user role has a metatable")
	h.assert_true(getmetatable(engine_role) == getmetatable(user_role),
		"engine and user role share a metatable (same class)")
end)
