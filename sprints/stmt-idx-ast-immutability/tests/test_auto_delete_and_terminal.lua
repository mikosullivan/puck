#!/usr/bin/env lua5.4

--[[
{
	"module": "test_auto_delete_and_terminal",
	"role": "Sprint-scoped tests for the new-gc-cycle rules covering the terminal state: rule 8 (auto-delete on reaching terminal, cap excluded) and the follow-on rule that a child frame cannot be inserted under a parent in its terminal state.",
	"run": "lua5.4 sprints/stmt-idx-ast-immutability/tests/test_auto_delete_and_terminal.lua (from repo root)"
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

-- Insert a length-N frame with the given parent. N controls the
-- terminal position: for length-2, stmt_idx=2 is terminal.
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
-- Auto-delete at terminal
-- ============================================================

test('length-2 frame at (1, gc=1) advancing to 2 is auto-deleted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)

	-- Simulate one full dispatch cycle: gc=1 then advance to 1.
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set 1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'advance to 1')

	-- Frame should still exist at (1, null) — not yet terminal.
	local row = first(db, "select stmt_idx from objects where object_pk = '" .. parent_pk .. "'")
	assert(row and tonumber(row.stmt_idx) == 1, 'frame should still exist at stmt_idx=1')

	-- Second cycle: gc=1 then advance to 2 (terminal).
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set 1 again')
	assert_ok(db:exec("update objects set stmt_idx = 2 where object_pk = '" .. parent_pk .. "'"),
		db, 'advance to 2 (terminal)')

	-- Frame should be gone.
	local gone = first(db, "select object_pk from objects where object_pk = '" .. parent_pk .. "'")
	assert(gone == nil, 'frame at terminal should have been auto-deleted')
	db:close()
end)

test('length-2 frame at (0, gc=1) advancing to 1 is NOT deleted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_of_length(db, cap_pk, user_pk, 2)

	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set 1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'advance to 1')

	local row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(row ~= nil, 'frame should still exist')
	assert(tonumber(row.stmt_idx) == 1, 'stmt_idx should be 1')
	assert(row.gc == nil, 'gc should be null after advance')
	db:close()
end)

test('cap advancing to its terminal (stmt_idx=1) is NOT auto-deleted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	-- Cap has ast='[]', max=1. Advance cap all the way to terminal.
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc set 1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap advance to 1')

	local row = first(db, "select stmt_idx from objects where object_pk = '" .. cap_pk .. "' and process = 1")
	assert(row ~= nil, 'cap should still exist (process=1 excluded from auto-delete)')
	assert(tonumber(row.stmt_idx) == 1, 'cap stmt_idx should be 1')
	db:close()
end)


-- ============================================================
-- Cannot insert a child under a terminal parent
-- ============================================================

test('inserting a child under a parent at stmt_idx=max is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	-- Cap has max=1. Advance it to terminal.
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc set 1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap advance to 1 (terminal)')

	-- Try to add a child under the terminal cap.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '" .. cap_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'frames_no_child_under_terminal_parent',
		'child insert under terminal cap rejected')
	db:close()
end)

test('inserting a child under a parent at stmt_idx < max is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	-- Cap is at stmt_idx=0, max=1. Not terminal.
	local child = insert_frame_of_length(db, cap_pk, user_pk, 2)
	assert(child ~= nil, 'child insert under non-terminal parent should succeed')
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
