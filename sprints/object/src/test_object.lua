#!/usr/bin/env lua5.4

--[[
{
	"module": "test_object",
	"role": "Tests for the sprint's Lua-side Object class implementation. Exercises the constructor's field shape (pk, engine, db) and the placeholder method surfaces (methods, obj) being present as empty tables.",
	"invoke": "lua5.4 sprints/object/src/test_object.lua",
	"status": "sprint tests"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'sprints/object/src/?.lua;' .. package.path

local sqlite = require('lsqlite3')
local object = require('object')


-- ------------------------------------------------------------
-- Assertion helpers
-- ------------------------------------------------------------

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(string.format("  \27[32mok\27[0m   %s", label))
end

local function fail(label, why)
	failed = failed + 1
	print(string.format("  \27[31mFAIL\27[0m %s", label))
	print(string.format("       %s", why))
end

local function assert_eq(actual, expected, label)
	if actual == expected then
		pass(label)
	else
		fail(label, string.format('expected %s, got %s', tostring(expected), tostring(actual)))
	end
end


-- ------------------------------------------------------------
-- Fake engine — enough to satisfy the constructor's needs. The real
-- engine carries far more; the constructor only reads `.cvm`.
-- ------------------------------------------------------------

local function fake_engine()
	return {cvm = sqlite.open_memory()}
end


-- ------------------------------------------------------------
-- Test cases
-- ------------------------------------------------------------

print('== object.new + fields ==')

do  -- Fresh wrapper carries pk, engine, db
	local engine = fake_engine()
	local o      = object.new(engine, 'abc-123')

	assert_eq(o.pk,     'abc-123', 'wrapper has pk')
	assert_eq(o.engine, engine,    'wrapper has engine')
	assert_eq(o.db,     engine.cvm,'wrapper has db (cached from engine.cvm)')
end

do  -- The db field really IS a live sqlite handle
	local engine = fake_engine()
	local o      = object.new(engine, 'xyz-456')

	local ok = pcall(function()
		return o.db:exec("select 1")
	end)

	if ok then
		pass('wrapper.db can execute SQL')
	else
		fail('wrapper.db can execute SQL', 'exec raised')
	end
end

do  -- Method-surface placeholders present as tables
	assert_eq(type(object.methods), 'table', 'object.methods is a table')
	assert_eq(type(object.obj),     'table', 'object.obj is a table')
end

do  -- Constructor does no side effects
	local engine = fake_engine()

	-- No rows should be created just by wrapping a pk.
	local before
	for row in engine.cvm:nrows("select count(*) as n from sqlite_master where type='table'") do
		before = row.n
	end

	object.new(engine, 'no-side-effect-pk')

	local after
	for row in engine.cvm:nrows("select count(*) as n from sqlite_master where type='table'") do
		after = row.n
	end

	assert_eq(after, before, 'constructor creates no tables (no side effects)')
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format('  %d passed, %d failed', passed, failed))

if failed > 0 then
	os.exit(1)
end
