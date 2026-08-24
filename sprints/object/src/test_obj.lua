#!/usr/bin/env lua5.4

--[[
{
	"module": "test_obj",
	"role": "Tests for obj.new — the agent constructor. Loads production schema into an in-memory SQLite (production carries the b/p/s invariants since object-sprint Track 1 landed), seeds a target object, then walks through the row shape obj.new must produce: agent row with engine_class='obj' and inherited owner_role, bucket with the b-ref linking it, target ref keyed 'target' inside the bucket. Also covers fresh-per-access and missing-target error.",
	"invoke": "lua5.4 sprints/object/src/test_obj.lua",
	"status": "sprint tests"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'sprints/object/src/?.lua;'
	.. 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. package.path

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')
local obj                = require('obj')

local SCHEMA_PATH    = 'production/src/engine/cvm/sqlite/schema.sql'
local PREFLIGHT_PATH = 'production/src/engine/cvm/sqlite/preflight.sql'


-- ------------------------------------------------------------
-- Harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local _process_holders = setmetatable({}, {__mode = 'k'})

local function fresh_engine()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')

	local holder = {pk = nil}
	_process_holders[db] = holder
	current_process_pk.register(db, function() return holder.pk end)

	assert(db:exec(slurp(SCHEMA_PATH))    == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	assert(db:exec(slurp(PREFLIGHT_PATH)) == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))

	return {cvm = db}
end

local function seed_user_pk(db)
	for row in db:nrows("select object_pk from objects where role_core = 'u'") do
		return row.object_pk
	end
	error('user seed missing')
end

local function insert_target(engine, owner_pk)
	local pk
	for row in engine.cvm:nrows(
		"insert into objects (base, owner_role) values ('o', '" .. owner_pk .. "') "
		.. "returning object_pk"
	) do
		pk = row.object_pk
	end
	return pk
end


-- ------------------------------------------------------------
-- Assertion helpers
-- ------------------------------------------------------------

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(string.format("  \27[32mok\27[0m   %s", label))
end

local function fail(label, why)
	failed = failed + 1
	print(string.format("  \27[31mFAIL\27[0m %s", label))
	print(string.format("       %s", why))
end

local function assert_eq(actual, expected, label)
	if actual == expected then
		pass(label)
	else
		fail(label, string.format('expected %s, got %s', tostring(expected), tostring(actual)))
	end
end


-- ------------------------------------------------------------
-- Test cases
-- ------------------------------------------------------------

print('== obj.new ==')

do  -- Agent row: correct base + engine_class + inherited owner_role
	local engine   = fresh_engine()
	local user_pk  = seed_user_pk(engine.cvm)
	local target   = insert_target(engine, user_pk)
	local agent    = obj.new(engine, target)

	local row
	for r in engine.cvm:nrows(
		"select base, control, engine_class, owner_role from objects "
		.. "where object_pk = '" .. agent.pk .. "'"
	) do
		row = r
	end

	assert_eq(row and row.base,         'o',      "agent base='o'")
	assert_eq(row and row.control,      nil,      "agent control is null")
	assert_eq(row and row.engine_class, 'obj',    "agent engine_class='obj'")
	assert_eq(row and row.owner_role,   user_pk,  "agent owner_role inherits from target")
end

do  -- Agent's bucket: key='b' ref to a base='h' row
	local engine   = fresh_engine()
	local user_pk  = seed_user_pk(engine.cvm)
	local target   = insert_target(engine, user_pk)
	local agent    = obj.new(engine, target)

	local bucket_pk, bucket_base
	for r in engine.cvm:nrows(
		"select r.child, o.base from refs r "
		.. "join objects o on o.object_pk = r.child "
		.. "where r.parent = '" .. agent.pk .. "' and r.key = 'b'"
	) do
		bucket_pk   = r.child
		bucket_base = r.base
	end

	if bucket_pk and bucket_base == 'h' then
		pass("agent → bucket via key='b' (bucket is base='h')")
	else
		fail("agent → bucket via key='b' (bucket is base='h')",
			string.format('bucket_pk=%s base=%s', tostring(bucket_pk), tostring(bucket_base)))
	end

	-- The target ref lives inside the bucket, keyed 'target', pointing at the parent.
	local target_child
	for r in engine.cvm:nrows(
		"select child from refs "
		.. "where parent = '" .. bucket_pk .. "' and key = 'target'"
	) do
		target_child = r.child
	end

	assert_eq(target_child, target, "bucket → target via key='target'")
end

do  -- Returned wrapper carries pk + engine + db
	local engine   = fresh_engine()
	local user_pk  = seed_user_pk(engine.cvm)
	local target   = insert_target(engine, user_pk)
	local agent    = obj.new(engine, target)

	assert_eq(type(agent.pk),   'string', "wrapper.pk is a string")
	assert_eq(agent.engine,     engine,   "wrapper.engine matches")
	assert_eq(agent.db,         engine.cvm,"wrapper.db is engine.cvm")
end

do  -- Fresh per access: two obj.new calls produce distinct agents
	local engine   = fresh_engine()
	local user_pk  = seed_user_pk(engine.cvm)
	local target   = insert_target(engine, user_pk)

	local a = obj.new(engine, target)
	local b = obj.new(engine, target)

	if a.pk ~= b.pk then
		pass("two obj.new calls for same target produce distinct agents")
	else
		fail("two obj.new calls for same target produce distinct agents",
			'both got pk=' .. tostring(a.pk))
	end
end

do  -- Missing target raises obj_new_target_missing
	local engine  = fresh_engine()
	local ok, err = pcall(function()
		return obj.new(engine, 'no-such-pk')
	end)

	if ok then
		fail('missing target raises obj_new_target_missing', 'call succeeded')
	elseif not err or not err:find('obj_new_target_missing', 1, true) then
		fail('missing target raises obj_new_target_missing',
			'got: ' .. tostring(err))
	else
		pass('missing target raises obj_new_target_missing')
	end
end

do  -- Roll-back: a failure inside the savepoint leaves no partial rows
	local engine   = fresh_engine()
	local user_pk  = seed_user_pk(engine.cvm)
	local target   = insert_target(engine, user_pk)

	-- Count objects before
	local before
	for r in engine.cvm:nrows("select count(*) as n from objects") do
		before = r.n
	end

	-- Sabotage: install a temp trigger that raises on the target-ref
	-- insertion (the last INSERT in obj.new). Everything before it —
	-- agent row, bucket row, agent → bucket ref — should roll back.
	engine.cvm:exec(
		"create temp trigger sabotage_target_ref "
		.. "before insert on refs when new.key = 'target' "
		.. "begin select raise(abort, 'sabotage: no target refs allowed'); end;"
	)

	local ok = pcall(function()
		return obj.new(engine, target)
	end)

	engine.cvm:exec("drop trigger sabotage_target_ref;")

	if ok then
		fail('sabotaged obj.new raises', 'succeeded when it should have failed')
	else
		pass('sabotaged obj.new raises')
	end

	local after
	for r in engine.cvm:nrows("select count(*) as n from objects") do
		after = r.n
	end

	assert_eq(after, before, "no partial rows left after savepoint rollback")
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format('  %d passed, %d failed', passed, failed))

if failed > 0 then
	os.exit(1)
end
