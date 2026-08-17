#!/usr/bin/env lua5.4

--[[
{
	"module": "test_stmt_idx_bounds",
	"role": "Sprint-scoped tests for the frames_stmt_idx_within_ast_bounds triggers (insert + update variants) in sprints/close-schema-holes/src/schema.sql. Enforces that a frame's stmt_idx cannot exceed max(json_array_length(ast), 1) — i.e., for empty ast, {0, 1}; for length-N ast, {0..N}.",
	"run": "lua5.4 sprints/close-schema-holes/tests/test_stmt_idx_bounds.lua (from repo root)"
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

-- Seed a cap frame + return its pk. Cap has ast='[]', process=1.
local function insert_cap(db, user_pk)
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

-- Advance stmt_idx + set gc=1 in one UPDATE (walker's canonical advance).
local function walker_advance(db, frame_pk, new_stmt_idx)
	return db:exec("update objects set stmt_idx = " .. new_stmt_idx
		.. ", gc = 1 where object_pk = '" .. frame_pk .. "'")
end


-- ============================================================
-- Empty ast (length 0) → stmt_idx in {0, 1}
-- ============================================================

test('empty ast + stmt_idx = 0 at INSERT is accepted (born state)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	assert_ok(db:exec("insert into objects (primitive, ast, stmt_idx, process, owner_role) "
		.. "values ('f', '[]', 0, 1, '" .. user_pk .. "')"),
		db, 'cap born at stmt_idx = 0')
	db:close()
end)

test('empty ast + stmt_idx = 2 at INSERT is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	assert_fails_with(
		db:exec("insert into objects (primitive, ast, stmt_idx, process, owner_role) "
			.. "values ('f', '[]', 2, 1, '" .. user_pk .. "')"),
		db, 'frames_stmt_idx_out_of_bounds',
		'stmt_idx = 2 on empty ast rejected')
	db:close()
end)

test('empty ast: cap advances 0 → 1 (accepted)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	assert_ok(walker_advance(db, cap_pk, 1), db, 'cap advance 0 → 1')
	db:close()
end)

test('empty ast: cap advance beyond 1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	-- Get to stmt_idx=1 legally.
	assert_ok(walker_advance(db, cap_pk, 1), db, 'advance to 1')
	-- Reset gc so the next advance is legal (advance requires gc=1
	-- coupled with the stmt_idx move, but gc must be null beforehand).
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. cap_pk .. "'"),
		db, 'reset gc')

	-- Now try to advance 1 → 2 — should be rejected by the new bound.
	assert_fails_with(
		walker_advance(db, cap_pk, 2),
		db, 'frames_stmt_idx_out_of_bounds',
		'advance past 1 rejected on empty ast')
	db:close()
end)


-- ============================================================
-- Length-N ast → stmt_idx in {0..N}
-- ============================================================

test('length-1 ast: stmt_idx = 1 at INSERT is rejected (must start at 0)', function()
	-- Sanity — the starts-at-zero rule still applies.
	local db = fresh_db()
	local user_pk = seed_user(db)
	assert_fails_with(
		db:exec("insert into objects (primitive, ast, stmt_idx, process, owner_role) "
			.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 1, 1, '" .. user_pk .. "')"),
		db, 'frames_stmt_idx_must_start_at_zero',
		'starts-at-zero still enforced')
	db:close()
end)

-- Non-empty-ast frames are nested (parent_frame set, process null).
-- Helper: seed cap + frame 0 with the given ast, return frame 0's pk.
local function insert_frame_with_ast(db, user_pk, ast_json)
	local cap_pk = insert_cap(db, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '" .. ast_json .. "', 0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

test('length-1 ast: advance 0 → 1 is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local frame_pk = insert_frame_with_ast(db, user_pk, '[[{"in":"as"},"x",{"v":1}]]')

	assert_ok(walker_advance(db, frame_pk, 1), db, 'advance 0 → 1 (equals length)')
	db:close()
end)

test('length-1 ast: advance beyond 1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local frame_pk = insert_frame_with_ast(db, user_pk, '[[{"in":"as"},"x",{"v":1}]]')

	assert_ok(walker_advance(db, frame_pk, 1), db, 'advance to 1')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. frame_pk .. "'"), db, 'reset gc')

	assert_fails_with(
		walker_advance(db, frame_pk, 2),
		db, 'frames_stmt_idx_out_of_bounds',
		'advance past length rejected')
	db:close()
end)

test('length-3 ast: INSERT with stmt_idx = 4 is rejected', function()
	-- Guards the INSERT-time check even though starts-at-zero would
	-- normally catch stmt_idx != 0 first — a bulk-load path with the
	-- starts-at-zero trigger disabled would still hit this bound.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)

	local ast = '[["a"],["b"],["c"]]'
	assert_fails_with(
		db:exec("insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
			.. "values ('f', '" .. ast .. "', 4, '" .. cap_pk .. "', '" .. user_pk .. "')"),
		db, 'frames_stmt_idx',
		'stmt_idx = 4 on length-3 ast rejected (starts-at-zero or out-of-bounds, either counts)')
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
