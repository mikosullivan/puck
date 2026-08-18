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

local SCHEMA_PATH    = 'sprints/trace-tables/src/schema.sql'
local PREFLIGHT_PATH = 'sprints/trace-tables/src/preflight.sql'


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
	-- schema.sql sets up main; preflight.sql sets pragmas and
	-- creates temp tables + temp triggers. Matches what the engine
	-- does on a connect: schema at DB creation, preflight on every
	-- connection open.
	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	rc = db:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))
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

	-- Attempt to delete the cap — needs_trace.process_pk FK RESTRICT
	-- (real FK, since needs_trace is persistent) should block.
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


-- ============================================================
-- composite PK (process_pk, object_pk) — per-process marking
-- ============================================================

test('same process cannot double-mark the same object (PK conflict)', function()
	-- Manual double-INSERT (no ON CONFLICT clause) should raise the
	-- unique-constraint error on the composite PK.
	local db = schema_db()
	local _user_pk, _cap_pk, _hash_pk, scalar_pk = setup(db)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'first mark')
	local rc = db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')")
	assert(rc ~= sqlite.OK, 'second insert should fail on composite PK conflict')
	assert(db:errmsg():find('UNIQUE constraint failed', 1, true) ~= nil,
		'expected UNIQUE constraint error; got: ' .. db:errmsg())

	local rows = first(db,
		"select count(*) as c from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(tonumber(rows.c) == 1, 'exactly one row should remain; got: ' .. rows.c)
	db:close()
end)

test('ref-delete trigger silently coalesces duplicate marks from the same process', function()
	-- Two ref-drops of the same child in the same process → the upsert
	-- absorbs the second. Only one row lands.
	local db = schema_db()
	local user_pk, cap_pk, hash_pk, scalar_pk = setup(db)

	-- Two distinct refs from the hash to the scalar (different keys).
	assert_ok(db:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. scalar_pk .. "', 'a', 0)"), db, 'ref a')
	assert_ok(db:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. scalar_pk .. "', 'b', 1)"), db, 'ref b')

	-- Drop both. Each fires the trigger; the second insert conflicts
	-- with the first and is silently dropped.
	assert_ok(db:exec("delete from refs where parent = '" .. hash_pk .. "' and key = 'a'"),
		db, 'drop ref a')
	assert_ok(db:exec("delete from refs where parent = '" .. hash_pk .. "' and key = 'b'"),
		db, 'drop ref b')

	local rows = first(db,
		"select count(*) as c from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(tonumber(rows.c) == 1,
		'exactly one needs_trace row should exist after both drops; got: ' .. rows.c)

	local row = first(db,
		"select process_pk from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(row.process_pk == cap_pk, 'the row should be attributed to the current cap')
	db:close()
end)

test('two different processes can each mark the same object independently', function()
	-- The composite PK is (process_pk, object_pk), so two caps each
	-- get their own row for the same target object. Uses a single
	-- registered UDF whose upvalue swings between caps.
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_a_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk
	local cap_b_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	local scalar_pk = first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	local current = cap_a_pk
	current_process_pk.register(db, function() return current end)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'mark under cap A')

	current = cap_b_pk
	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'mark under cap B')

	local rows = first(db,
		"select count(*) as c from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(tonumber(rows.c) == 2,
		'both processes should have their own mark; got: ' .. rows.c)
	db:close()
end)

test('deleting the object cascades needs_trace rows for ALL processes marking it', function()
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_a_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk
	local cap_b_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	local scalar_pk = first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	local current = cap_a_pk
	current_process_pk.register(db, function() return current end)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'mark under cap A')
	current = cap_b_pk
	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'mark under cap B')

	-- Delete the target. Both marks should cascade away.
	assert_ok(db:exec("delete from objects where object_pk = '" .. scalar_pk .. "'"),
		db, 'delete target')

	local rows = first(db,
		"select count(*) as c from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(tonumber(rows.c) == 0,
		'both marks should have cascaded away; got: ' .. rows.c)
	db:close()
end)


-- ============================================================
-- traces cascade + restrict (mirrors needs_trace)
-- ============================================================

test('deleting the target object cascades traces rows away', function()
	local db = schema_db()
	local _user_pk, _cap_pk, _hash_pk, scalar_pk = setup(db)

	-- Trace the scalar. traces_run_on_insert fires, walks up (finds
	-- nothing anchored), and lands the trace with done=1.
	local trace_row = first(db,
		"insert into traces (object_pk) values ('" .. scalar_pk .. "') returning trace_pk")
	assert(trace_row ~= nil, 'trace should exist')

	-- Delete the seed object. The traces row should cascade away.
	assert_ok(db:exec("delete from objects where object_pk = '" .. scalar_pk .. "'"),
		db, 'scalar delete')

	local remaining = first(db,
		"select count(*) as c from traces where object_pk = '" .. scalar_pk .. "'")
	assert(tonumber(remaining.c) == 0,
		'no traces rows should survive; got: ' .. remaining.c)
	db:close()
end)

-- ============================================================
-- frames_gc_reset_requires_empty_needs_trace
-- ============================================================

test('gc 1 → null is rejected while the current process has needs_trace rows', function()
	-- Mark an object, mark gc=1 on the cap, then try to reset gc to
	-- null. Rejected — needs_trace still has an outstanding entry for
	-- the current process.
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1')

	assert_fails_with(
		db:exec("update objects set gc = null where object_pk = '" .. cap_pk .. "'"),
		db, 'frames_gc_reset_requires_empty_needs_trace',
		'gc reset blocked while needs_trace non-empty for current process')
	db:close()
end)

test('gc 1 → null succeeds once needs_trace is cleared', function()
	local db = schema_db()
	local _user_pk, cap_pk, _hash_pk, scalar_pk = setup(db)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'needs_trace insert')
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_pk .. "'"),
		db, 'cap gc=1')

	assert_ok(db:exec("delete from needs_trace"), db, 'clear needs_trace')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. cap_pk .. "'"),
		db, 'gc reset after cleanup')
	db:close()
end)

test('gc 1 → null is not blocked by needs_trace rows for a DIFFERENT process', function()
	-- Two caps, A (current) and B. Mark an object under B (by swinging
	-- current_process_pk temporarily), then swing back to A. A's gc
	-- reset succeeds because its own needs_trace worklist is empty —
	-- B's outstanding row is scoped to B.
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_a_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk
	local cap_b_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	local scalar_pk = first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	local current = cap_b_pk
	current_process_pk.register(db, function() return current end)

	assert_ok(db:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'mark under cap B')

	current = cap_a_pk
	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. cap_a_pk .. "'"),
		db, 'cap A gc=1')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. cap_a_pk .. "'"),
		db, 'cap A gc reset — B\'s worklist doesn\'t block A')
	db:close()
end)

test('deleting a traces row cascades matching in_trace rows away', function()
	-- Isolated test of `traces_delete_cascades_in_trace`. Populate
	-- traces and in_trace directly (no trace-run trigger involved),
	-- delete the traces row, verify in_trace empties.
	local db = schema_db()
	local _user_pk, _cap_pk, hash_pk, scalar_pk = setup(db)

	local trace_pk = first(db,
		"insert into traces (object_pk) values ('" .. scalar_pk .. "') returning trace_pk").trace_pk

	assert_ok(db:exec(
		"insert into in_trace (trace_pk, object_pk) values ("
		.. trace_pk .. ", '" .. scalar_pk .. "'), (" .. trace_pk .. ", '" .. hash_pk .. "')"),
		db, 'in_trace seed')

	local before = first(db,
		"select count(*) as c from in_trace where trace_pk = " .. trace_pk)
	assert(tonumber(before.c) == 2, 'in_trace should have 2 rows before delete; got: ' .. before.c)

	assert_ok(db:exec("delete from traces where trace_pk = " .. trace_pk),
		db, 'traces delete')

	local after = first(db,
		"select count(*) as c from in_trace where trace_pk = " .. trace_pk)
	assert(tonumber(after.c) == 0,
		'in_trace should have 0 rows after cascade; got: ' .. after.c)
	db:close()
end)


-- ============================================================
-- temp isolation vs persistence
-- ============================================================

test('needs_trace persists across connections; traces does not', function()
	-- Two connections against the same on-disk DB. needs_trace is
	-- in main → shared. traces is temp → per-connection.
	local path = os.tmpname()
	os.remove(path)  -- os.tmpname creates it; SQLite will.

	local db1 = sqlite.open(path)
	local rc = db1:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'db1 schema: ' .. tostring(db1:errmsg()))
	rc = db1:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'db1 preflight: ' .. tostring(db1:errmsg()))

	-- Set up state in db1.
	local user_pk = first(db1, "select object_pk from objects where core_role = 'u'").object_pk
	local cap_pk = first(db1,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk
	current_process_pk.register(db1, function() return cap_pk end)
	local scalar_pk = first(db1,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	assert_ok(db1:exec("insert into needs_trace (object_pk) values ('" .. scalar_pk .. "')"),
		db1, 'db1 needs_trace insert')
	assert_ok(db1:exec("insert into traces (object_pk) values ('" .. scalar_pk .. "')"),
		db1, 'db1 traces insert')

	-- Close db1 to force everything to disk.
	db1:close()

	-- Open a fresh connection. Main tables carry over from disk;
	-- preflight recreates the temp tables + triggers and sets pragmas.
	-- The engine follows exactly this pattern on every connection open.
	local db2 = sqlite.open(path)
	rc = db2:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'db2 preflight: ' .. tostring(db2:errmsg()))

	-- needs_trace: persisted, should still be there.
	local nt_rows = first(db2, "select count(*) as c from needs_trace")
	assert(tonumber(nt_rows.c) == 1,
		'needs_trace should have survived; got: ' .. nt_rows.c)

	-- traces: temp, should be gone (fresh per-connection).
	local t_rows = first(db2, "select count(*) as c from traces")
	assert(tonumber(t_rows.c) == 0,
		'traces should be empty on a fresh connection; got: ' .. t_rows.c)

	db2:close()
	os.remove(path)
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
