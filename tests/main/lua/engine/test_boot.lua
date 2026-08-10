local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local h      = require('helpers')
local engine = require('engine')

--[[
## The MVM is opened on boot

`engine.new()` is the boot entry point; its first act is to open an
MVM (via `drinian.open()`) and stash the resulting SQLite handle as
`engine.mvm`. Everything downstream in the engine reads and writes
runtime state through that handle.
]]

h.test("engine.new() opens an MVM on boot", function()
	local e = engine.new()
	h.assert_true(e.mvm ~= nil, "engine.mvm is populated at construction")
end)

h.test("engine.new()'s MVM is a functional SQLite handle", function()
	local e = engine.new()
	local n = nil

	for row in e.mvm:nrows('select count(*) as n from objects') do
		n = row.n
	end

	h.assert_true(n ~= nil, 'query returned a row')
	h.assert_eq(n, 1, 'seed row is present (one row in objects after open)')
end)

h.test("engine.new()'s MVM has the user seed row", function()
	local e = engine.new()
	local count = nil

	for row in e.mvm:nrows('select count(*) as n from objects where user') do
		count = row.n
	end

	h.assert_eq(count, 1, 'exactly one user row after boot')
end)

h.test("engine.new()'s MVM has foreign keys enabled", function()
	local e = engine.new()
	local fk = nil

	for row in e.mvm:nrows('pragma foreign_keys') do
		fk = row.foreign_keys
	end

	h.assert_eq(fk, 1, 'foreign_keys pragma is on')
end)

--[[
## Each engine gets its own MVM

Two `engine.new()` calls return engines with independent in-memory
MVMs; writes to one don't touch the other. This is the property that
lets a host run multiple programs in one Lua VM without cross-talk.
]]

h.test("each engine.new() gets its own MVM", function()
	local e1 = engine.new()
	local e2 = engine.new()
	h.assert_true(e1.mvm ~= e2.mvm, 'the two mvm handles are distinct')

	-- Insert a plain HashPrimitive into e1's MVM and verify e2 doesn't see it.
	local ok = e1.mvm:exec("insert into objects (primitive) values ('h')")
	h.assert_true(ok == 0, 'insert succeeded on e1 (lsqlite3 exec returns 0 on OK)')

	local n1, n2

	for row in e1.mvm:nrows('select count(*) as n from objects') do
		n1 = row.n
	end

	for row in e2.mvm:nrows('select count(*) as n from objects') do
		n2 = row.n
	end

	h.assert_eq(n1, 2, 'e1 sees seed + new insert')
	h.assert_eq(n2, 1, 'e2 sees only the seed — its MVM is independent')
end)
