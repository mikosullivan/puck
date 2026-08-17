#!/usr/bin/env lua5.4

--[[
{
	"module": "test_refs_debug_mutable",
	"role": "Sprint-scoped test: refs.debug is mutable. `debug` is a human-readable informational label with no query path reading it; the refs_no_update trigger's WHEN clause omits it, so changing debug on an existing ref is accepted. The other columns (ref_pk, parent, child, key, idx) remain immutable.",
	"run": "lua5.4 sprints/close-schema-holes/tests/test_refs_debug_mutable.lua (from repo root)"
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

local function insert_scalar(db, owner_role)
	local sql = "insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 1, '" .. owner_role .. "') returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end
end


-- ============================================================
-- refs.debug is mutable
-- ============================================================

test('setting refs.debug from null to a value is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"), db, 'insert ref')

	assert_ok(db:exec("update refs set debug = 'first label' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'set debug from null')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == 'first label',
		'debug should be "first label"; got: ' .. tostring(row.debug))
	db:close()
end)

test('changing refs.debug to a different value is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx, debug) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0, 'first')"), db, 'insert with debug')

	assert_ok(db:exec("update refs set debug = 'second' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'update debug')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == 'second',
		'debug should be "second"; got: ' .. tostring(row.debug))
	db:close()
end)

test('clearing refs.debug (back to null) is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx, debug) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0, 'label')"), db, 'insert with debug')

	assert_ok(db:exec("update refs set debug = null where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'clear debug')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == nil, 'debug should be null; got: ' .. tostring(row.debug))
	db:close()
end)


-- ============================================================
-- Regression: the other columns remain immutable
-- ============================================================

test('changing refs.key is still rejected (regression)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"), db, 'insert ref')

	assert_fails_with(
		db:exec("update refs set key = 'y' where parent = '"
			.. hash_pk .. "' and idx = 0"),
		db, 'refs_immutable',
		'changing key should still be rejected')
	db:close()
end)

test('changing refs.child is still rejected (regression)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_a = insert_scalar(db, user_pk)
	local child_b = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_a .. "', 'x', 0)"), db, 'insert ref')

	assert_fails_with(
		db:exec("update refs set child = '" .. child_b .. "' where parent = '"
			.. hash_pk .. "' and key = 'x'"),
		db, 'refs_immutable',
		'changing child should still be rejected')
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
