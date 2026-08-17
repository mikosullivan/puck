#!/usr/bin/env lua5.4

--[[
{
	"module": "test_chain_reaction",
	"role": "End-to-end schema-level test of the new gc cycle's cascade. Walks a three-level fixture (cap → parent → child) through completion via four UPDATE statements, verifying that rules 3, 6, 8 and cap-exclusion all fire in the right order across each hop of the cascade.",
	"run": "lua5.4 sprints/stmt-idx-ast-immutability/tests/test_chain_reaction.lua (from repo root)"
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

local function insert_length_1_frame_under(db, parent_pk, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do return row.object_pk end
end


-- ============================================================
-- The full cascade: child completes → parent gc=1 → parent
-- completes → cap gc=1 → cap advances to terminal (excluded from
-- auto-delete, stays alive as the process anchor).
-- ============================================================

test('end-to-end cascade: three-level stack collapses to cap', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Fixture: cap + parent + child. All at (0, null).
	local cap_pk    = insert_cap(db, user_pk)
	local parent_pk = insert_length_1_frame_under(db, cap_pk, user_pk)
	local child_pk  = insert_length_1_frame_under(db, parent_pk, user_pk)

	-- Sanity: all three exist, all at (0, null, has-a-child except child).
	assert(first(db, "select object_pk from objects where object_pk = '" .. cap_pk    .. "'") ~= nil, 'cap exists')
	assert(first(db, "select object_pk from objects where object_pk = '" .. parent_pk .. "'") ~= nil, 'parent exists')
	assert(first(db, "select object_pk from objects where object_pk = '" .. child_pk  .. "'") ~= nil, 'child exists')

	-- ----------------------------------------------------------
	-- Step 1: dispatch child's one statement completes → set gc=1
	-- ----------------------------------------------------------
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. child_pk .. "'"),
		db, 'step 1: child gc = 1')

	local child_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. child_pk .. "'")
	assert(child_row and tonumber(child_row.stmt_idx) == 0 and tonumber(child_row.gc) == 1,
		'step 1: child should be (0, 1)')

	local parent_row = first(db, "select gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(parent_row.gc == nil, 'step 1: parent gc should still be null')

	-- ----------------------------------------------------------
	-- Step 2: advance child → auto-set null → auto-delete →
	--         rule 3 sets parent.gc = 1
	-- ----------------------------------------------------------
	assert_ok(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. child_pk .. "'"),
		db, 'step 2: advance child')

	assert(first(db, "select object_pk from objects where object_pk = '" .. child_pk .. "'") == nil,
		'step 2: child should be gone (auto-deleted at terminal)')
	parent_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(parent_row and tonumber(parent_row.stmt_idx) == 0 and tonumber(parent_row.gc) == 1,
		'step 2: parent should be at (0, 1) via rule 3')

	local cap_row = first(db, "select gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(cap_row.gc == nil, 'step 2: cap gc should still be null')

	-- ----------------------------------------------------------
	-- Step 3: advance parent → cascade one level up
	-- ----------------------------------------------------------
	assert_ok(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'step 3: advance parent')

	assert(first(db, "select object_pk from objects where object_pk = '" .. parent_pk .. "'") == nil,
		'step 3: parent should be gone')
	cap_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(cap_row and tonumber(cap_row.stmt_idx) == 0 and tonumber(cap_row.gc) == 1,
		'step 3: cap should be at (0, 1) via rule 3')

	-- ----------------------------------------------------------
	-- Step 4: advance cap → auto-set null → auto-delete EXCLUDES
	--         cap (process = 1) → cap terminal-alive
	-- ----------------------------------------------------------
	assert_ok(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'step 4: advance cap')

	cap_row = first(db, "select stmt_idx, gc, process from objects where object_pk = '" .. cap_pk .. "'")
	assert(cap_row, 'step 4: cap should still exist (process=1 excluded from auto-delete)')
	assert(tonumber(cap_row.stmt_idx) == 1, 'step 4: cap stmt_idx should be 1')
	assert(cap_row.gc == nil, 'step 4: cap gc should be null after advance')
	assert(tonumber(cap_row.process) == 1, 'step 4: cap process should still be 1')

	-- No non-cap frames remain.
	local remaining = first(db, "select count(*) as n from objects where primitive = 'f' and process is not 1")
	assert(tonumber(remaining.n) == 0, 'step 4: no non-cap frames should remain; got: ' .. tostring(remaining.n))
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
