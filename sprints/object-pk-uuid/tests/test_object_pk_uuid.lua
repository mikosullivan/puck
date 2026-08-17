#!/usr/bin/env lua5.4

--[[
{
	"module": "test_object_pk_uuid",
	"role": "Sprint-scoped tests for the object_pk shape CHECK and the tightened v4 DEFAULT in sprints/object-pk-uuid/src/schema.sql. Covers: DEFAULT-generated pks satisfy v4 shape (position 15 = '4', position 20 ∈ {8,9,a,b}); CHECK accepts loose 8-4-4-4-12 hex UUIDs of either case; CHECK rejects non-UUID strings, wrong-length strings, and strings with non-hex/non-hyphen characters; seeded core-role rows come up with compliant object_pks.",
	"run": "lua5.4 sprints/object-pk-uuid/tests/test_object_pk_uuid.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/object-pk-uuid/src/schema.sql'


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


-- ============================================================
-- Seeded rows are compliant
-- ============================================================

test('seeded core-role rows have compliant object_pks', function()
	local db = fresh_db()

	for _, code in ipairs({'e', 'c', 'u'}) do
		local row = first(db, "select object_pk from objects where core_role = '" .. code .. "'")
		local pk = row.object_pk

		-- length 36
		assert(#pk == 36, "core_role='" .. code .. "' object_pk should be length 36; got: " .. #pk .. " (" .. pk .. ")")
		-- hyphens at 9, 14, 19, 24 (1-indexed)
		assert(pk:sub(9, 9) == '-', "hyphen expected at position 9 in " .. pk)
		assert(pk:sub(14, 14) == '-', "hyphen expected at position 14 in " .. pk)
		assert(pk:sub(19, 19) == '-', "hyphen expected at position 19 in " .. pk)
		assert(pk:sub(24, 24) == '-', "hyphen expected at position 24 in " .. pk)
		-- v4: position 15 (start of third block) must be '4'
		assert(pk:sub(15, 15) == '4', "position 15 should be '4' (v4 version bit) in " .. pk)
		-- variant: position 20 (start of fourth block) must be 8/9/a/b
		local v = pk:sub(20, 20)
		assert(v == '8' or v == '9' or v == 'a' or v == 'b',
			"position 20 should be one of 8/9/a/b (variant bit) in " .. pk .. " (got '" .. v .. "')")
	end
	db:close()
end)


-- ============================================================
-- DEFAULT generates v4 shape across many inserts
-- ============================================================

test('DEFAULT generates v4-shaped pks across 100 inserts', function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	for i = 1, 100 do
		local sql = "insert into objects (primitive, owner_role) values ('h', '"
			.. user_pk .. "') returning object_pk"
		local row = first(db, sql)
		local pk = row.object_pk

		assert(#pk == 36, "iteration " .. i .. ": pk length should be 36; got: " .. #pk .. " (" .. pk .. ")")
		assert(pk:sub(15, 15) == '4', "iteration " .. i .. ": position 15 should be '4'; got: " .. pk)

		local v = pk:sub(20, 20)
		assert(v == '8' or v == '9' or v == 'a' or v == 'b',
			"iteration " .. i .. ": position 20 should be 8/9/a/b; got: '" .. v .. "' in " .. pk)
	end
	db:close()
end)


-- ============================================================
-- CHECK accepts compliant callers-supplied UUIDs
-- ============================================================

test('CHECK accepts a caller-supplied lowercase v4 UUID', function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_ok(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdef01-2345-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'compliant lowercase v4 UUID accepted')
	db:close()
end)

test('CHECK rejects a caller-supplied uppercase UUID (lowercase enforced)', function()
	-- Same conceptual UUID as the lowercase-accept test above but in
	-- uppercase. Rejected because SQLite's default TEXT collation is
	-- binary — accepting both cases would let the same UUID sit under
	-- two distinct PKs.
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('ABCDEF01-2345-4678-9ABC-DEF012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'uppercase UUID rejected')
	db:close()
end)

test('CHECK rejects a caller-supplied mixed-case UUID (lowercase enforced)', function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('AbCdEf01-2345-4678-9aBc-dEf012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'mixed-case UUID rejected')
	db:close()
end)

test('CHECK accepts a non-v4 UUID (loose shape — no version-bit check)', function()
	-- Version-3 (position 15 = '3') and non-v4 variants should pass —
	-- the CHECK only enforces the general 8-4-4-4-12 hex shape.
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_ok(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdef01-2345-3678-c000-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'v3-shaped UUID accepted (no version-bit check)')
	db:close()
end)


-- ============================================================
-- CHECK rejects non-compliant strings
-- ============================================================

test("CHECK rejects 'banana' (not UUID-shaped at all)", function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('banana', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'banana rejected')
	db:close()
end)

test("CHECK rejects a UUID-length-but-wrong-hyphen-position string", function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	-- Same length (36) but hyphens in wrong places.
	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdef0123-45-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'wrong hyphen positions rejected')
	db:close()
end)

test("CHECK rejects a UUID-shape with a non-hex character in place", function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	-- Same layout, but position 5 is 'g' (not hex).
	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdgf01-2345-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'non-hex character rejected')
	db:close()
end)

test("CHECK rejects the historical 'no-such-uuid-...' sentinel", function()
	-- The word 'no-such-uuid' has non-hex letters (n, o, s, u).
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('no-such-uuid-0000-0000-000000000000', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		"'no-such-uuid-...' rejected")
	db:close()
end)

test("CHECK rejects a too-short string", function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdef01-2345', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'too-short string rejected')
	db:close()
end)

test("CHECK rejects a too-long string", function()
	local db = fresh_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	assert_fails_with(
		db:exec("insert into objects (object_pk, primitive, owner_role) "
			.. "values ('abcdef01-2345-4678-9abc-def012345678-extra', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'too-long string rejected')
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
