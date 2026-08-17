#!/usr/bin/env lua5.4

--[[
{
	"module": "test_remaining_rules",
	"role": "Sprint-scoped tests for rules 2 (INSERT never sets gc=1), 3 (child delete auto-sets parent's gc=1), 7 (no gc=1 at max stmt_idx), and 9 (frame cannot be deleted with a child).",
	"run": "lua5.4 sprints/stmt-idx-ast-immutability/tests/test_remaining_rules.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/stmt-idx-ast-immutability/src/schema.sql'


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
-- fixtures
-- ------------------------------------------------------------

local function seed_user(db)
	return first(db, "select object_pk from objects where core_role = 'u'").object_pk
end

local function insert_cap(db, user_pk)
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do return row.object_pk end
end

local function insert_frame_of_length(db, parent_pk, user_pk, length)
	local stmts = {}
	for i = 1, length do
		stmts[i] = string.format('[{"in":"as"},"x%d",{"v":%d}]', i, i)
	end
	local ast = '[' .. table.concat(stmts, ',') .. ']'
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '" .. ast .. "', 0, '" .. parent_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do return row.object_pk end
end


-- ============================================================
-- Rule 2: INSERT never sets gc=1
-- ============================================================

test('rule 2: inserting a frame with gc = 1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	local sql = "insert into objects (primitive, ast, stmt_idx, gc, parent_frame, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, 1, '"
		.. cap_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'frames_gc_starts_null',
		'INSERT with gc=1 rejected')
	db:close()
end)

test('rule 2: inserting a frame with gc = null (omitted) is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	-- Bare INSERT: gc column omitted → default null.
	local child = insert_frame_of_length(db, cap_pk, user_pk, 2)
	assert(child ~= nil, 'child insert with default gc should succeed')

	local row = first(db, "select gc from objects where object_pk = '" .. child .. "'")
	assert(row.gc == nil, 'gc should be null; got: ' .. tostring(row.gc))
	db:close()
end)

test('rule 2: inserting the cap with gc = 1 is also rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local sql = "insert into objects (primitive, process, ast, stmt_idx, gc, owner_role) "
		.. "values ('f', 1, '[]', 0, 1, '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'frames_gc_starts_null',
		'INSERT cap with gc=1 rejected')
	db:close()
end)


-- ============================================================
-- Rule 3: child delete auto-sets parent's gc = 1
-- ============================================================

test('rule 3: deleting a child frame sets the parent gc = 1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)
	local child_pk = insert_frame_of_length(db, parent_pk, user_pk, 1)

	-- Advance child to terminal so its own gc=null (rule 9 requires
	-- gc=null to delete). Actually, child is at (0, null, 0 kids). Just
	-- delete the child directly — its gc is already null, and rule 9
	-- has no child of its own to block.
	assert_ok(db:exec("delete from objects where object_pk = '" .. child_pk .. "'"),
		db, 'child delete succeeded')

	-- Parent should now be at gc = 1.
	local row = first(db, "select gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(row.gc) == 1, 'parent gc should be 1 after child delete; got: ' .. tostring(row.gc))
	db:close()
end)

test('rule 3: cap gets gc = 1 when its child (frame 0) is deleted', function()
	-- Same mechanism from a nested frame's perspective — verifies the
	-- rule works for the cap parent too.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local frame0_pk = insert_frame_of_length(db, cap_pk, user_pk, 1)

	-- Delete frame 0.
	assert_ok(db:exec("delete from objects where object_pk = '" .. frame0_pk .. "'"),
		db, 'frame 0 delete succeeded')

	local row = first(db, "select gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(tonumber(row.gc) == 1, 'cap gc should be 1 after frame 0 delete; got: ' .. tostring(row.gc))
	db:close()
end)

-- ============================================================
-- Rule 7: no gc = 1 when stmt_idx = max
-- ============================================================

test('rule 7: setting gc = 1 on a frame at max stmt_idx is rejected', function()
	-- To construct: use a frame with length-2 ast. Get it to (1, null),
	-- then advance to (2, null) — but the auto-delete fires and removes
	-- it. Can't reach a "terminal frame that still exists" via normal
	-- flow. Use the CAP for this test — cap is exempt from auto-delete.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	-- Cap at (0, null, no kids). Set gc=1, advance to (1, null).
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1 (0/1)')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap advance to 1 (terminal)')

	-- Now try to set gc=1 on the terminal cap.
	assert_fails_with(
		db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'frames_gc_set_rejects_at_terminal',
		'gc=1 at max rejected')
	db:close()
end)

test('rule 7: setting gc = 1 on a frame BELOW max is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)

	-- Parent at (0, null). Max is 2. Setting gc=1 is fine.
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc=1 below max accepted')
	db:close()
end)


-- ============================================================
-- Rule 9: frame cannot be deleted while it has a child
-- ============================================================

test('rule 9: deleting a parent with a live child is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)
	local _child_pk = insert_frame_of_length(db, parent_pk, user_pk, 1)

	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_delete_requires_no_child',
		'parent-with-child delete rejected')
	db:close()
end)

test('rule 9: deleting a childless parent is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)

	-- Parent has no children — delete should succeed (subject to
	-- rule 9's companion frames_delete_requires_gc_null; parent's
	-- gc is null so that's fine too).
	assert_ok(
		db:exec("delete from objects where object_pk = '" .. parent_pk .. "'"),
		db, 'childless parent delete accepted')
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
