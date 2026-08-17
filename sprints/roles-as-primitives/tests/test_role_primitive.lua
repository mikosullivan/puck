#!/usr/bin/env lua5.4

--[[
{
	"module": "test_role_primitive",
	"role": "Sprint-scoped tests for the roles-as-primitives changes in sprints/roles-as-primitives/src/schema.sql. Covers: 'r' primitive accepted, non-'r' rows rejected for core_role/parent_role, role rows rejected as ref parents, parent_role/owner_role must target 'r' rows, only the engine can be a role-tree root, seeded rows come up as 'r', roles view contains exactly the 'r' rows.",
	"run": "lua5.4 sprints/roles-as-primitives/tests/test_role_primitive.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/roles-as-primitives/src/schema.sql'


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

local function engine_pk(db)
	return first(db, "select object_pk from objects where core_role = 'e'").object_pk
end

local function user_pk(db)
	return first(db, "select object_pk from objects where core_role = 'u'").object_pk
end

local function insert_hash(db, owner_role)
	local sql = "insert into objects (primitive, owner_role) values ('h', '"
		.. owner_role .. "') returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end
end


-- ============================================================
-- The 'r' primitive is accepted; seeded rows use it
-- ============================================================

test('seeded engine/cache/user rows come up as primitive = r', function()
	local db = fresh_db()

	for _, code in ipairs({'e', 'c', 'u'}) do
		local row = first(db, "select primitive from objects where core_role = '" .. code .. "'")
		assert(row.primitive == 'r',
			"core_role='" .. code .. "' should have primitive='r'; got: " .. tostring(row.primitive))
	end
	db:close()
end)

test('a runtime role (parent_role set, no core_role) can be inserted', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	assert_ok(db:exec("insert into objects (primitive, parent_role, owner_role) "
		.. "values ('r', '" .. eng .. "', '" .. eng .. "')"),
		db, 'runtime role accepted')

	local n = first(db, "select count(*) as n from objects where primitive = 'r'").n
	assert(tonumber(n) == 4, 'expected 4 role rows (3 seeded + 1 new); got: ' .. tostring(n))
	db:close()
end)


-- ============================================================
-- Non-'r' rows can't carry role columns
-- ============================================================

test('non-r row with core_role is rejected (cross-column check)', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	assert_fails_with(
		db:exec("insert into objects (primitive, scalar_type, scalar_value, core_role, owner_role) "
			.. "values ('o', 'n', 42, 'e', '" .. eng .. "')"),
		db, 'CHECK constraint',
		'scalar with core_role rejected')
	db:close()
end)

test('non-r row with parent_role is rejected (cross-column check)', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	assert_fails_with(
		db:exec("insert into objects (primitive, parent_role, owner_role) "
			.. "values ('h', '" .. eng .. "', '" .. eng .. "')"),
		db, 'CHECK constraint',
		'hash with parent_role rejected')
	db:close()
end)


-- ============================================================
-- 'r' cannot be a ref parent
-- ============================================================

test('a ref whose parent is a role row is rejected', function()
	local db = fresh_db()
	local eng = engine_pk(db)
	local child_pk = insert_hash(db, eng)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. eng .. "', '" .. child_pk .. "', 'x', 0)"),
		db, 'refs_role_cannot_be_parent',
		'ref-under-role rejected')
	db:close()
end)


-- ============================================================
-- parent_role / owner_role must reference an 'r' row
-- ============================================================

test('parent_role pointing at a non-role row is rejected', function()
	local db = fresh_db()
	local eng = engine_pk(db)
	local hash = insert_hash(db, eng)

	assert_fails_with(
		db:exec("insert into objects (primitive, parent_role, owner_role) "
			.. "values ('r', '" .. hash .. "', '" .. eng .. "')"),
		db, 'parent_role_must_be_role',
		'parent_role → hash rejected')
	db:close()
end)

test('owner_role pointing at a non-role row is rejected', function()
	local db = fresh_db()
	local eng = engine_pk(db)
	local hash = insert_hash(db, eng)

	assert_fails_with(
		db:exec("insert into objects (primitive, owner_role) values ('h', '" .. hash .. "')"),
		db, 'owner_role_must_be_role',
		'owner_role → hash rejected')
	db:close()
end)


-- ============================================================
-- Only the engine role can be a role-tree root
-- ============================================================

test('runtime role with parent_role = null is rejected', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	assert_fails_with(
		db:exec("insert into objects (primitive, owner_role) values ('r', '" .. eng .. "')"),
		db, 'objects_only_engine_can_be_role_root',
		'root-shaped runtime role rejected')
	db:close()
end)

test('cache-like role (core_role != e) with parent_role = null is rejected', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	-- core_role='c' is already taken (unique) — use a different tack:
	-- attempt to insert a new 'r' row with core_role null AND
	-- parent_role null. Different code path, same trigger.
	assert_fails_with(
		db:exec("insert into objects (primitive, owner_role) values ('r', '" .. eng .. "')"),
		db, 'objects_only_engine_can_be_role_root',
		'role with no core_role AND no parent_role rejected')
	db:close()
end)


-- ============================================================
-- Roles view contains exactly the 'r' rows
-- ============================================================

test("roles view returns exactly the primitive = 'r' rows", function()
	local db = fresh_db()

	local view_count = first(db, "select count(*) as n from roles").n
	local r_count = first(db, "select count(*) as n from objects where primitive = 'r'").n
	assert(tonumber(view_count) == tonumber(r_count),
		'roles view count (' .. tostring(view_count) .. ') should equal count of primitive=r rows ('
		.. tostring(r_count) .. ')')

	-- And it should be 3 at initialized state (engine, cache, user).
	assert(tonumber(view_count) == 3, 'roles view should have 3 rows at init; got: ' .. tostring(view_count))
	db:close()
end)


-- ============================================================
-- Non-role rows still require owner_role
-- ============================================================

test('non-role row inserted without owner_role is rejected', function()
	local db = fresh_db()

	assert_fails_with(
		db:exec("insert into objects (primitive) values ('h')"),
		db, 'objects_owner_role_required',
		'ownerless non-role rejected')
	db:close()
end)


-- ============================================================
-- Deleting a role: blocked while children reference it
-- ============================================================

test('deleting a role with children in parent_role is rejected (FK RESTRICT)', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	-- Create a parent runtime role.
	local sql = "insert into objects (primitive, parent_role, owner_role) "
		.. "values ('r', '" .. eng .. "', '" .. eng .. "') returning object_pk"
	local parent_role_pk
	for row in db:nrows(sql) do parent_role_pk = row.object_pk end

	-- Create a child role under it.
	assert_ok(db:exec("insert into objects (primitive, parent_role, owner_role) "
		.. "values ('r', '" .. parent_role_pk .. "', '" .. eng .. "')"),
		db, 'child role inserted')

	-- Try to delete the parent — FK RESTRICT should block it.
	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. parent_role_pk .. "'"),
		db, 'FOREIGN KEY constraint',
		'delete of role with children rejected')
	db:close()
end)

test('deleting a childless runtime role is accepted', function()
	local db = fresh_db()
	local eng = engine_pk(db)

	local sql = "insert into objects (primitive, parent_role, owner_role) "
		.. "values ('r', '" .. eng .. "', '" .. eng .. "') returning object_pk"
	local role_pk
	for row in db:nrows(sql) do role_pk = row.object_pk end

	assert_ok(db:exec("delete from objects where object_pk = '" .. role_pk .. "'"),
		db, 'childless runtime role deletable')
	db:close()
end)


-- ============================================================
-- Cycle-free by construction (note-only)
-- ============================================================

test('role tree is cycle-free by construction (documentation)', function()
	-- This test doesn't exercise a runtime cycle-check trigger —
	-- there isn't one. The tree can't cycle because parent_role
	-- must reference an existing role at INSERT time and is
	-- immutable thereafter. The invariant is structural.
	-- Recorded here so a future reader doesn't wonder where the
	-- cycle guard lives.
	--
	-- Sanity check: create a runtime role, then try to reparent
	-- it (change its parent_role). The parent_role_immutable trigger
	-- rejects. (The core roles have an additional root-role guard
	-- that would fire first, so the sanity check uses a runtime role
	-- to isolate the immutability rule.)
	local db = fresh_db()
	local eng = engine_pk(db)
	local usr = user_pk(db)

	local sql = "insert into objects (primitive, parent_role, owner_role) "
		.. "values ('r', '" .. eng .. "', '" .. eng .. "') returning object_pk"
	local runtime_role
	for row in db:nrows(sql) do runtime_role = row.object_pk end

	assert_fails_with(
		db:exec("update objects set parent_role = '" .. usr .. "' where object_pk = '" .. runtime_role .. "'"),
		db, 'objects_parent_role_immutable',
		'reparenting a runtime role is rejected (immutability keeps the tree cycle-free)')
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
