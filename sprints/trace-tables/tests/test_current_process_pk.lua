#!/usr/bin/env lua5.4

--[[
{
	"module": "test_current_process_pk",
	"role": "Sprint-scoped tests for the `current_process_pk` UDF. Covers: bare-connection tests that the UDF returns whatever the registered getter provides (including nil), reflects updates to the getter's state, and can be invoked in query contexts. Also a schema-loaded integration test that uses the UDF to populate `needs_trace.process_pk` and verifies the row lands with the right value.",
	"run": "lua5.4 sprints/trace-tables/tests/test_current_process_pk.lua (from repo root)"
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

-- bare_db is the pre-schema state: pragmas set, but no CVM DDL
-- applied. Used by UDF-behavior tests that don't need the schema.
-- Note: since the UDF isn't registered here, the preflight file
-- would fail to apply (its triggers reference current_process_pk
-- in their WHEN clauses at fire time; schema-apply-time is fine).
local function bare_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')
	return db
end

local function schema_db()
	local db = bare_db()
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


-- ============================================================
-- UDF returns whatever the getter provides
-- ============================================================

test('returns the value the getter provides', function()
	local db = bare_db()
	local pk_value = 'abcdef01-2345-4678-9abc-def012345678'
	current_process_pk.register(db, function() return pk_value end)

	local row = first(db, 'select current_process_pk() as pk')
	assert(row.pk == pk_value,
		'expected ' .. pk_value .. '; got: ' .. tostring(row.pk))
	db:close()
end)

test('returns nil when the getter returns nil', function()
	local db = bare_db()
	current_process_pk.register(db, function() return nil end)

	local row = first(db, 'select current_process_pk() as pk')
	assert(row.pk == nil,
		'expected nil; got: ' .. tostring(row.pk))
	db:close()
end)

test('reflects updates to the getter closure state', function()
	local db = bare_db()
	local current = nil
	current_process_pk.register(db, function() return current end)

	-- Initially nil.
	local row = first(db, 'select current_process_pk() as pk')
	assert(row.pk == nil, 'initial call should return nil')

	-- Set state, call again.
	current = 'abcdef01-2345-4678-9abc-def012345678'
	row = first(db, 'select current_process_pk() as pk')
	assert(row.pk == current,
		'after set: expected ' .. current .. '; got: ' .. tostring(row.pk))

	-- Change state, call again.
	current = 'fedcba98-7654-4321-8fed-cba987654321'
	row = first(db, 'select current_process_pk() as pk')
	assert(row.pk == current,
		'after change: expected ' .. current .. '; got: ' .. tostring(row.pk))
	db:close()
end)


-- ============================================================
-- Integration: UDF works inside a schema-loaded connection and
-- can populate `needs_trace.process_pk` (rounds out the whole
-- reason the UDF exists).
-- ============================================================

test('current_process_pk() populates needs_trace.process_pk from an INSERT', function()
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	-- Insert a cap frame.
	local cap_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	-- Register the UDF pointing at the cap.
	current_process_pk.register(db, function() return cap_pk end)

	-- Insert a marker for the cap itself using current_process_pk().
	assert_ok(db:exec(
		"insert into needs_trace (object_pk, process_pk) "
		.. "values ('" .. cap_pk .. "', current_process_pk())"),
		db, 'needs_trace insert via current_process_pk()')

	-- Verify the row landed with both columns populated.
	local row = first(db, "select object_pk, process_pk from needs_trace where object_pk = '" .. cap_pk .. "'")
	assert(row ~= nil, 'needs_trace row should exist')
	assert(row.object_pk == cap_pk, 'object_pk should match cap')
	assert(row.process_pk == cap_pk, 'process_pk should equal the cap\'s pk (via the UDF)')
	db:close()
end)

test('INSERT omitting process_pk picks up the DEFAULT from current_process_pk()', function()
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	current_process_pk.register(db, function() return cap_pk end)

	-- Insert without specifying process_pk — should default to the UDF's value.
	assert_ok(db:exec(
		"insert into needs_trace (object_pk) values ('" .. cap_pk .. "')"),
		db, 'needs_trace insert with process_pk omitted')

	local row = first(db, "select process_pk from needs_trace where object_pk = '" .. cap_pk .. "'")
	assert(row.process_pk == cap_pk,
		'DEFAULT should have filled process_pk with the UDF value; got: ' .. tostring(row.process_pk))
	db:close()
end)

test('INSERT via ref-delete trigger (implicit DEFAULT) records the current process', function()
	-- Round-trips the whole loop: create a ref, delete it, verify
	-- `refs_mark_needs_trace_after_delete` inserted a needs_trace row
	-- with process_pk defaulted from the UDF.
	local db = schema_db()
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	current_process_pk.register(db, function() return cap_pk end)

	-- Create a hash and a scalar; ref the scalar from the hash.
	local hash_pk = first(db,
		"insert into objects (primitive, owner_role) values ('h', '" .. user_pk .. "') returning object_pk").object_pk
	local scalar_pk = first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk
	assert_ok(db:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. scalar_pk .. "', 'x', 0)"),
		db, 'ref insert')

	-- Delete the ref — trigger should fire and insert into needs_trace.
	assert_ok(db:exec(
		"delete from refs where parent = '" .. hash_pk .. "' and key = 'x'"),
		db, 'ref delete')

	local row = first(db, "select process_pk from needs_trace where object_pk = '" .. scalar_pk .. "'")
	assert(row ~= nil, 'needs_trace row should have been auto-inserted by the trigger')
	assert(row.process_pk == cap_pk,
		'process_pk should have defaulted to current_process_pk() = ' .. cap_pk
		.. '; got: ' .. tostring(row.process_pk))
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
