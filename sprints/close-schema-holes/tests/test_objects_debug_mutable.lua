#!/usr/bin/env lua5.4

--[[
{
	"module": "test_objects_debug_mutable",
	"role": "Sprint-scoped test: objects.debug is mutable — including on core-role rows. `debug` is an informational label with no query path reading it. The base objects_no_update trigger doesn't guard it; the core-role guard objects_no_update_root_role explicitly exempts it (alongside needs_trace and in_trace).",
	"run": "lua5.4 sprints/close-schema-holes/tests/test_objects_debug_mutable.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/close-schema-holes/src/schema.sql'


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local function fresh_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')
	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	return db
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end


local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)

	if ok then
		passed = passed + 1
		print('  PASS  ' .. name)
	else
		failed = failed + 1
		print('  FAIL  ' .. name)
		table.insert(failures, {name = name, err = err})
	end
end

local function assert_ok(rc, db, note)
	if rc ~= sqlite.OK then
		error((note or 'expected OK') .. ': ' .. tostring(db:errmsg()), 2)
	end
end

local function assert_fails_with(rc, db, expected_substr, note)
	if rc == sqlite.OK then
		error((note or 'expected failure') .. ' — but the operation succeeded', 2)
	end

	local msg = db:errmsg()

	if not msg:find(expected_substr, 1, true) then
		error(
			(note or 'wrong error') .. '\n'
			.. '  expected substring: ' .. expected_substr .. '\n'
			.. '  actual: ' .. msg,
			2
		)
	end
end


-- ------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------

local function seed_user(db)
	local row = first(db, "select object_pk from objects where core_role = 'u'")
	return row.object_pk
end

local function insert_hash(db, owner_role)
	local sql = "insert into objects (primitive, owner_role) values ('h', '"
		.. owner_role .. "') returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end
end


-- ============================================================
-- objects.debug is mutable on regular (non-core-role) rows
-- ============================================================

test('setting objects.debug on a regular row is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("update objects set debug = 'my label' where object_pk = '" .. hash_pk .. "'"),
		db, 'set debug on regular row')

	local row = first(db, "select debug from objects where object_pk = '" .. hash_pk .. "'")
	assert(row.debug == 'my label', 'debug should be "my label"; got: ' .. tostring(row.debug))
	db:close()
end)

test('changing objects.debug on a regular row is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("update objects set debug = 'first' where object_pk = '" .. hash_pk .. "'"),
		db, 'first set')
	assert_ok(db:exec("update objects set debug = 'second' where object_pk = '" .. hash_pk .. "'"),
		db, 'change')

	local row = first(db, "select debug from objects where object_pk = '" .. hash_pk .. "'")
	assert(row.debug == 'second', 'debug should be "second"; got: ' .. tostring(row.debug))
	db:close()
end)


-- ============================================================
-- objects.debug is mutable on core-role rows (engine, cache, user)
-- ============================================================

test('setting objects.debug on the engine core role is accepted', function()
	local db = fresh_db()
	local engine_pk = first(db, "select object_pk from objects where core_role = 'e'").object_pk

	assert_ok(db:exec("update objects set debug = 'engine seed' where object_pk = '" .. engine_pk .. "'"),
		db, 'set debug on engine core role')

	local row = first(db, "select debug from objects where object_pk = '" .. engine_pk .. "'")
	assert(row.debug == 'engine seed', 'engine.debug should be "engine seed"; got: ' .. tostring(row.debug))
	db:close()
end)

test('setting objects.debug on the cache core role is accepted', function()
	local db = fresh_db()
	local cache_pk = first(db, "select object_pk from objects where core_role = 'c'").object_pk

	assert_ok(db:exec("update objects set debug = 'cache seed' where object_pk = '" .. cache_pk .. "'"),
		db, 'set debug on cache core role')

	local row = first(db, "select debug from objects where object_pk = '" .. cache_pk .. "'")
	assert(row.debug == 'cache seed', 'cache.debug should be "cache seed"; got: ' .. tostring(row.debug))
	db:close()
end)

test('setting objects.debug on the user core role is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(db:exec("update objects set debug = 'user seed' where object_pk = '" .. user_pk .. "'"),
		db, 'set debug on user core role')

	local row = first(db, "select debug from objects where object_pk = '" .. user_pk .. "'")
	assert(row.debug == 'user seed', 'user.debug should be "user seed"; got: ' .. tostring(row.debug))
	db:close()
end)


-- ============================================================
-- Regression: other core-role fields still blocked
-- ============================================================

test('changing objects.persistent on a core role is still blocked (regression)', function()
	local db = fresh_db()
	local engine_pk = first(db, "select object_pk from objects where core_role = 'e'").object_pk

	assert_fails_with(
		db:exec("update objects set persistent = null where object_pk = '" .. engine_pk .. "'"),
		db, 'root_role_cannot_be_updated',
		'clearing persistent on engine core role should still be rejected')
	db:close()
end)


-- ------------------------------------------------------------
-- report
-- ------------------------------------------------------------

print()
print(string.format('TOTAL: %d passed, %d failed', passed, failed))

if failed > 0 then
	print()
	print('Failures:')

	for _, f in ipairs(failures) do
		print('  [' .. f.name .. ']')

		for line in tostring(f.err):gmatch('[^\n]+') do
			print('    ' .. line)
		end
	end

	os.exit(1)
end

os.exit(0)
