#!/usr/bin/env lua5.4

--[[
{
	"module": "test_hash_array_keys",
	"role": "Sprint-scoped tests for the two new triggers in sprints/close-schema-holes/src/schema.sql — `refs_hash_key_required` (hash parents must have a non-null key) and `refs_array_key_forbidden` (array parents must have a null key). Runs standalone against the sprint's copy of the schema.",
	"run": "lua5.4 sprints/close-schema-holes/tests/test_hash_array_keys.lua (from repo root)"
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

local function insert_array(db, owner_role)
	local sql = "insert into objects (primitive, owner_role) values ('a', '"
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
-- refs_hash_key_required — hash parent must have non-null key
-- ============================================================

test('hash parent with null key is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'refs_hash_key_required',
		'null key under hash parent rejected')
	db:close()
end)

test('hash parent with non-null key is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"),
		db, 'non-null key under hash parent accepted')
	db:close()
end)


-- ============================================================
-- refs_array_key_forbidden — array parent must have null key
-- ============================================================

test('array parent with non-null key is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local array_pk = insert_array(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. array_pk .. "', '" .. child_pk .. "', 'k', 0)"),
		db, 'refs_array_key_forbidden',
		'non-null key under array parent rejected')
	db:close()
end)

test('array parent with null key is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local array_pk = insert_array(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. array_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'null key under array parent accepted')
	db:close()
end)


-- ============================================================
-- Non-container parents still unaffected — the two new rules
-- only fire when parent is 'h' or 'a', not 'o' or 'f'.
-- ============================================================

test('non-container (object) parent with null key is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local owner_pk = insert_scalar(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. owner_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'null-keyed bucket-ref from a scalar owner accepted')
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
