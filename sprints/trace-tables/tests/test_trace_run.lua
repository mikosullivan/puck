#!/usr/bin/env lua5.4

--[[
{
	"module": "test_trace_run",
	"role": "Sprint-scoped tests for the `traces_run_on_insert` trigger — the SQL-side backward-reachability trace kicked off by inserting a row into `traces`. Covers: seed whose ancestor closure hits uspace (via persistent, via cap frame, via being uspace itself) → trace deleted; seed whose closure is entirely unanchored garbage → trace completes done=1 with in_trace populated; seed with no incoming refs → trace completes with just the seed in in_trace.",
	"run": "lua5.4 sprints/trace-tables/tests/test_trace_run.lua (from repo root)"
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

local function assert_ok(rc, db, note)
	if rc ~= sqlite.OK then
		error((note or 'expected OK') .. ': ' .. tostring(db:errmsg()), 2)
	end
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


-- ------------------------------------------------------------
-- setup: user role, cap, and a helper to make bare objects
-- ------------------------------------------------------------

local function base_setup(db)
	local user_pk = first(db, "select object_pk from objects where core_role = 'u'").object_pk

	local cap_pk = first(db,
		"insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk").object_pk

	current_process_pk.register(db, function() return cap_pk end)

	return user_pk, cap_pk
end

local function make_hash(db, user_pk)
	return first(db,
		"insert into objects (primitive, owner_role) values ('h', '"
		.. user_pk .. "') returning object_pk").object_pk
end

local function make_scalar(db, user_pk, value)
	return first(db,
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', " .. tostring(value) .. ", '"
		.. user_pk .. "') returning object_pk").object_pk
end

local function link(db, parent_pk, child_pk, key, idx)
	assert_ok(db:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. parent_pk .. "', '" .. child_pk .. "', '" .. key .. "', " .. tostring(idx) .. ")"),
		db, 'refs insert ' .. key)
end

local function in_trace_pks(db, trace_pk)
	local pks = {}
	for row in db:nrows("select object_pk from in_trace where trace_pk = "
			.. tostring(trace_pk) .. " order by object_pk") do
		table.insert(pks, row.object_pk)
	end
	return pks
end

local function set_contains(pks, target)
	for _, pk in ipairs(pks) do
		if pk == target then return true end
	end
	return false
end


-- ============================================================
-- success cases: no uspace hit → trace done, in_trace populated
-- ============================================================

test('seed with no incoming refs: trace done, only seed in in_trace', function()
	local db = schema_db()
	local user_pk, _cap_pk = base_setup(db)

	-- A single isolated scalar. Nothing refs it; the walk finds no
	-- ancestors; the trace terminates cleanly.
	local scalar_pk = make_scalar(db, user_pk, 42)

	local trace_pk = first(db,
		"insert into traces (object_pk) values ('" .. scalar_pk .. "') returning trace_pk").trace_pk

	local row = first(db, "select done from traces where trace_pk = " .. trace_pk)
	assert(row ~= nil, 'trace row should still exist')
	assert(tonumber(row.done) == 1, 'trace should be done; got: ' .. tostring(row.done))

	local pks = in_trace_pks(db, trace_pk)
	assert(#pks == 1, 'in_trace should have exactly one row; got: ' .. #pks)
	assert(pks[1] == scalar_pk, 'in_trace row should be the seed')
	db:close()
end)

test('seed with a chain of unanchored ancestors: trace done, full chain in in_trace', function()
	-- Chain: hash -> scalar. Neither anchored. Trace seeded on the
	-- scalar walks up to hash and terminates.
	local db = schema_db()
	local user_pk, _cap_pk = base_setup(db)

	local hash_pk = make_hash(db, user_pk)
	local scalar_pk = make_scalar(db, user_pk, 42)
	link(db, hash_pk, scalar_pk, 'x', 0)

	local trace_pk = first(db,
		"insert into traces (object_pk) values ('" .. scalar_pk .. "') returning trace_pk").trace_pk

	local row = first(db, "select done from traces where trace_pk = " .. trace_pk)
	assert(row ~= nil, 'trace row should exist')
	assert(tonumber(row.done) == 1, 'trace should be done')

	local pks = in_trace_pks(db, trace_pk)
	assert(#pks == 2, 'in_trace should have 2 rows; got: ' .. #pks)
	assert(set_contains(pks, scalar_pk), 'in_trace missing seed')
	assert(set_contains(pks, hash_pk), 'in_trace missing hash ancestor')
	db:close()
end)


-- ============================================================
-- uspace hit → trace (and its in_trace rows) deleted
-- ============================================================

test('ancestor is persistent (uspace): trace deleted, no in_trace rows survive', function()
	local db = schema_db()
	local user_pk, _cap_pk = base_setup(db)

	-- hash is persistent → uspace. Seed a scalar under it. Walk up
	-- finds the persistent hash → trace abandoned.
	local hash_pk = make_hash(db, user_pk)
	assert_ok(db:exec("update objects set persistent = 1 where object_pk = '" .. hash_pk .. "'"),
		db, 'mark hash persistent')
	local scalar_pk = make_scalar(db, user_pk, 42)
	link(db, hash_pk, scalar_pk, 'x', 0)

	local pre_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert_ok(db:exec("insert into traces (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'traces insert')
	local post_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert(tonumber(post_max) == tonumber(pre_max),
		'no new traces row should survive; pre=' .. tostring(pre_max) .. ' post=' .. tostring(post_max))

	local orphaned = first(db, "select count(*) as c from in_trace")
	assert(tonumber(orphaned.c) == 0, 'no in_trace rows should survive; got: ' .. orphaned.c)
	db:close()
end)

test('ancestor is a cap frame (uspace): trace deleted', function()
	-- cap -> hash -> scalar. Cap is uspace via process_cap=1. Seed
	-- the scalar → walk goes scalar -> hash -> cap → uspace hit.
	local db = schema_db()
	local user_pk, cap_pk = base_setup(db)

	local hash_pk = make_hash(db, user_pk)
	link(db, cap_pk, hash_pk, 'bucket', 0)
	local scalar_pk = make_scalar(db, user_pk, 42)
	link(db, hash_pk, scalar_pk, 'x', 0)

	local pre_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert_ok(db:exec("insert into traces (object_pk) values ('" .. scalar_pk .. "')"),
		db, 'traces insert')
	local post_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert(tonumber(post_max) == tonumber(pre_max), 'no new traces row should survive')

	local orphaned = first(db, "select count(*) as c from in_trace")
	assert(tonumber(orphaned.c) == 0, 'no in_trace rows should survive')
	db:close()
end)

test('seed is itself uspace (a persistent object): trace deleted immediately', function()
	local db = schema_db()
	local user_pk, _cap_pk = base_setup(db)

	local hash_pk = make_hash(db, user_pk)
	assert_ok(db:exec("update objects set persistent = 1 where object_pk = '" .. hash_pk .. "'"),
		db, 'mark hash persistent')

	local pre_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert_ok(db:exec("insert into traces (object_pk) values ('" .. hash_pk .. "')"),
		db, 'traces insert')
	local post_max = first(db, "select coalesce(max(trace_pk), 0) as m from traces").m
	assert(tonumber(post_max) == tonumber(pre_max),
		'trace with uspace seed should be deleted; pre=' .. tostring(pre_max) .. ' post=' .. tostring(post_max))
	db:close()
end)


-- ============================================================
-- cycle safety: refs cycle would loop forever without UNION dedup
-- ============================================================

test('cycle in refs terminates via UNION dedup', function()
	-- a -> b, b -> a (via distinct keys). Trace seeded on a should
	-- terminate; both a and b end up in in_trace; nothing anchored,
	-- so trace done=1.
	local db = schema_db()
	local user_pk, _cap_pk = base_setup(db)

	local a_pk = make_hash(db, user_pk)
	local b_pk = make_hash(db, user_pk)
	link(db, a_pk, b_pk, 'to_b', 0)
	link(db, b_pk, a_pk, 'to_a', 0)

	local trace_pk = first(db,
		"insert into traces (object_pk) values ('" .. a_pk .. "') returning trace_pk").trace_pk

	local row = first(db, "select done from traces where trace_pk = " .. trace_pk)
	assert(row ~= nil, 'trace should exist')
	assert(tonumber(row.done) == 1, 'trace should be done despite the cycle')

	local pks = in_trace_pks(db, trace_pk)
	assert(#pks == 2, 'in_trace should have both nodes; got: ' .. #pks)
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
