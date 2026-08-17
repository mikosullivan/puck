#!/usr/bin/env lua5.4

--[[
{
	"module": "test_needs_trace_lifecycle",
	"role": "Sprint-scoped tests for the needs_trace table's cascade / restrict semantics: `object_pk` FK cascades on object delete, `process_pk` FK restricts (a process can't be deleted while it has outstanding needs_trace rows), and a process cap can't advance to terminal while any needs_trace rows still reference it.",
	"run": "lua5.4 sprints/trace-tables/tests/test_needs_trace_lifecycle.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path = 'sprints/trace-tables/src/engine/cvm/udfs/?.lua;' .. package.path

local sqlite = require('lsqlite3')
local current_process_pk = require('current_process_pk')

local SCHEMA_PATH = 'sprints/trace-tables/src/schema.sql'


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local function schema_db()
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
-- fixture: cap + hash + scalar, UDF pointed at the cap
-- ------------------------------------------------------------

local function setup(db)
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	current_process_pk.register(db, function() return cap_pk end)

	local hash_pk = first(db,
		"insert into objects (primitive, owner_role) values ('h', '" .. user_pk .. "') returning object_pk").object_pk

	local scalar_pk = first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	return user_pk, cap_pk, hash_pk, scalar_pk
end


-- ============================================================
-- object_pk FK: cascade on object delete
-- ============================================================

test('deleting the marked object cascades its needs_trace row away', function()
	local db = schema_db()
	local _user_pk, _cap_pk, _hash_pk, scalar_pk = setup(db)

	-- Mark the scalar for trace.
	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')

	-- Confirm the row exists.
	assert(first(db, "select object_pk from needs_trace where object_pk = '" .. scalar_pk .. "'") ~= nil,
		'needs_trace row should exist before delete')

	-- Delete the scalar. Its needs_trace row should cascade away.
	assert_ok(db:exec("delete from objects where object_pk = '" .. scalar_pk .. "'"),
		db, 'scalar delete')

	assert(first(db, "select object_pk from needs_trace where object_pk = '" .. scalar_pk .. "'") == nil,
		'needs_trace row should be gone after cascade')
	db:close()
end)


-- ============================================================
-- process_pk FK: RESTRICT on process delete
-- ============================================================

test('deleting a process cap with outstanding needs_trace rows is rejected', function()
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	-- Mark the scalar (process_pk defaults to cap via the UDF).
	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')

	-- Attempt to delete the cap — FK RESTRICT on process_pk should block.
	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. cap_pk .. "'"),
		db, 'FOREIGN KEY constraint',
		'cap delete blocked by needs_trace.process_pk FK')
	db:close()
end)

test('deleting a process cap after clearing its needs_trace succeeds', function()
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')

	-- Clear the needs_trace row.
	assert_ok(db:exec("delete from needs_trace where object_pk = '" .. scalar_pk .. "'"),
		db, 'needs_trace delete')

	-- Now the cap can be deleted.
	assert_ok(db:exec("delete from objects where object_pk = '" .. cap_pk .. "'"),
		db, 'cap delete after cleanup')
	db:close()
end)


-- ============================================================
-- process_cap_terminal_requires_no_needs_trace
-- ============================================================

test('cap cannot advance to terminal while needs_trace rows reference it', function()
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	-- Mark the scalar.
	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')

	-- Get the cap to gc=1 (unrestricted set) so it's advance-eligible.
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1')

	-- Try to advance the cap to its terminal (stmt_idx = 1). Should be rejected.
	assert_fails_with(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'process_cap_terminal_requires_no_needs_trace',
		'cap advance to terminal blocked by outstanding needs_trace')
	db:close()
end)

test('cap CAN advance to terminal after clearing its needs_trace', function()
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')

	assert_ok(db:exec("delete from needs_trace where object_pk = '" .. scalar_pk .. "'"),
		db, 'needs_trace delete')

	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap advance to terminal after cleanup')
	db:close()
end)

test('cap CAN advance to terminal when it never had any needs_trace rows', function()
	-- Baseline: nothing marked, cap should reach terminal cleanly.
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, _scalar_pk = setup(db)

	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1')
	assert_ok(db:exec("update objects set stmt_idx = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap advance to terminal with no needs_trace')
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
