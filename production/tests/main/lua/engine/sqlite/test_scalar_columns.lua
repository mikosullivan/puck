--[[
{
	"module": "test_scalar_columns",
	"role": "Numbers sprint: exercises the schema shape change that replaced polymorphic `scalar_value blob` + `scalar_type text` with four typed columns (scalar_null / scalar_string / scalar_number / scalar_bool). Covers column presence and affinity, valid inserts for every scalar type + the plain-object no-scalar case, structural float-coercion via REAL affinity on scalar_number, per-column CHECKs, cross-column constraints (non-'o' rows can't populate scalar columns; 'o' rows populate at most one), per-column immutability triggers, and the `scalars` derived view.",
	"run": "lua5.4 sprints/numbers/tests/test_scalar_columns.lua (from repo root)"
}
]]

local SCHEMA_PATH    = 'production/src/engine/cvm/sqlite/schema.sql'
local PREFLIGHT_PATH = 'production/src/engine/cvm/sqlite/preflight.sql'

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

--[[
Fresh in-memory DB with the sprint's schema applied. Registers a
stub current_process_pk UDF (returns nil) so the schema-side default
expressions can bind without a real engine present. Preflight is
pulled from production — the sprint isn't forking it.
]]
local function fresh_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')
	current_process_pk.register(db, function() return nil end)

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

local function scalar(db, sql)
	for row in db:rows(sql) do
		return row[1]
	end
	return nil
end

local function seed_user(db)
	return first(db, "select object_pk from objects where role_core = 'u'").object_pk
end


local h = require('helpers')
local test = h.test

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


-- ============================================================
-- Column shape
-- ============================================================

test('scalar_null / scalar_string / scalar_number / scalar_bool columns exist with expected affinity', function()
	local db = fresh_db()

	local cols = {}
	for row in db:nrows("pragma table_info(objects)") do
		cols[row.name] = row
	end

	assert(cols.scalar_null ~= nil,   'scalar_null column should exist')
	assert(cols.scalar_string ~= nil, 'scalar_string column should exist')
	assert(cols.scalar_number ~= nil, 'scalar_number column should exist')
	assert(cols.scalar_bool ~= nil,   'scalar_bool column should exist')

	h.assert_eq(cols.scalar_null.type,   'INTEGER', 'scalar_null affinity')
	h.assert_eq(cols.scalar_string.type, 'TEXT',    'scalar_string affinity')
	h.assert_eq(cols.scalar_number.type, 'REAL',    'scalar_number affinity')
	h.assert_eq(cols.scalar_bool.type,   'INTEGER', 'scalar_bool affinity')

	db:close()
end)

test('scalar_type and scalar_value columns are gone', function()
	local db = fresh_db()

	local cols = {}
	for row in db:nrows("pragma table_info(objects)") do
		cols[row.name] = row
	end

	h.assert_true(cols.scalar_type == nil,  'scalar_type should be removed')
	h.assert_true(cols.scalar_value == nil, 'scalar_value should be removed')

	db:close()
end)

test('scalars view exists', function()
	local db = fresh_db()

	h.assert_eq(
		tonumber(scalar(db, "select count(*) from sqlite_master where type = 'view' and name = 'scalars'")),
		1, 'scalars view')

	db:close()
end)


-- ============================================================
-- Valid inserts per scalar type
-- ============================================================

test('inserting a string scalar succeeds and stores under scalar_string', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_string, owner_role) values ('o', 'hello', '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_string, 'hello',    'scalar_string carries payload')
	h.assert_true(row.scalar_number == nil,    'scalar_number null')
	h.assert_true(row.scalar_bool   == nil,    'scalar_bool null')
	h.assert_true(row.scalar_null   == nil,    'scalar_null null')

	db:close()
end)

test('inserting a number scalar succeeds and stores under scalar_number', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_number, owner_role) values ('o', 3.14, '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil,       'scalar_string null')
	h.assert_true(row.scalar_number ~= nil,       'scalar_number carries payload')
	h.assert_eq(tonumber(row.scalar_number), 3.14, 'value matches')
	h.assert_true(row.scalar_bool   == nil,       'scalar_bool null')
	h.assert_true(row.scalar_null   == nil,       'scalar_null null')

	db:close()
end)

test('inserting a boolean scalar succeeds (both 0 and 1)', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk_true = first(db,
		"insert into objects (base, scalar_bool, owner_role) values ('o', 1, '"
		.. user .. "') returning object_pk").object_pk
	local pk_false = first(db,
		"insert into objects (base, scalar_bool, owner_role) values ('o', 0, '"
		.. user .. "') returning object_pk").object_pk

	h.assert_eq(tonumber(scalar(db,
		"select scalar_bool from objects where object_pk = '" .. pk_true  .. "'")), 1, 'true stored as 1')
	h.assert_eq(tonumber(scalar(db,
		"select scalar_bool from objects where object_pk = '" .. pk_false .. "'")), 0, 'false stored as 0')

	db:close()
end)

test('inserting a null scalar (u type) succeeds via scalar_null = 1', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_null, owner_role) values ('o', 1, '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_eq(tonumber(row.scalar_null), 1, 'scalar_null = 1')

	db:close()
end)

test('inserting a plain object with no scalar (all four null) succeeds', function()
	-- A base='o' row that carries no scalar value at all — a
	-- container for methods, refs, whatever. Not the same as a null
	-- scalar (which has scalar_null = 1).
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, owner_role) values ('o', '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null (not a null scalar — no scalar at all)')

	db:close()
end)


-- ============================================================
-- Float coercion via REAL affinity on scalar_number
-- ============================================================

test('binding a Lua integer to scalar_number stores it as REAL', function()
	-- The load-bearing test for the sprint. SQLite's REAL affinity
	-- forces integer inserts to floating-point representation. Bind
	-- Lua integer 1 (Lua 5.4 distinguishes integer from float via
	-- math.type) → storage should land as REAL 1.0.
	local db = fresh_db()
	local user = seed_user(db)

	local stmt = db:prepare(
		"insert into objects (base, scalar_number, owner_role) values ('o', ?, ?) returning object_pk")
	stmt:bind_values(1, user)  -- Lua integer 1
	stmt:step()
	local pk = stmt:get_value(0)
	stmt:reset()

	local ty = scalar(db, "select typeof(scalar_number) from objects where object_pk = '" .. pk .. "'")
	h.assert_eq(ty, 'real', 'integer input should coerce to real storage')

	db:close()
end)

test('binding a Lua float to scalar_number stores it as REAL', function()
	local db = fresh_db()
	local user = seed_user(db)

	local stmt = db:prepare(
		"insert into objects (base, scalar_number, owner_role) values ('o', ?, ?) returning object_pk")
	stmt:bind_values(3.14, user)
	stmt:step()
	local pk = stmt:get_value(0)
	stmt:reset()

	local ty = scalar(db, "select typeof(scalar_number) from objects where object_pk = '" .. pk .. "'")
	h.assert_eq(ty, 'real', 'float input stays real')

	db:close()
end)


-- ============================================================
-- Column-level CHECK constraints
-- ============================================================

test('scalar_null = 0 is rejected (must be 1)', function()
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_null, owner_role) values ('o', 0, '"
			.. user .. "')"),
		db, 'CHECK',
		'scalar_null must be exactly 1')

	db:close()
end)

test('scalar_bool = 2 is rejected (must be in 0 / 1)', function()
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_bool, owner_role) values ('o', 2, '"
			.. user .. "')"),
		db, 'CHECK',
		'scalar_bool out-of-range should be rejected')

	db:close()
end)

test('scalar_bool with a text value is rejected', function()
	-- SQLite's INTEGER affinity converts numeric-looking text; the
	-- CHECK constraint bounds it. Truly-text value like 'true' can't
	-- convert numerically and lands as text — the `in (0, 1)` CHECK
	-- rejects it either way.
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_bool, owner_role) values ('o', 'true', '"
			.. user .. "')"),
		db, 'CHECK',
		'scalar_bool text value should be rejected')

	db:close()
end)


-- ============================================================
-- Cross-column constraints
-- ============================================================

test('non-o row populating a scalar column is rejected', function()
	-- Only base='o' rows can hold scalars. A hash / array /
	-- frame / role row with any scalar_* column populated is a
	-- schema violation.
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_string, owner_role) values ('h', 'oops', '"
			.. user .. "')"),
		db, 'objects_scalar_columns_only_on_objects',
		'hash row with scalar_string should be rejected')

	assert_fails_with(
		db:exec("insert into objects (base, scalar_number, owner_role) values ('a', 42, '"
			.. user .. "')"),
		db, 'objects_scalar_columns_only_on_objects',
		'array row with scalar_number should be rejected')

	assert_fails_with(
		db:exec("insert into objects (base, control, scalar_null, frame_ast, frame_stmt_idx, frame_parent, owner_role) "
			.. "values ('o', 'f', 1, '[null]', 0, null, '" .. user .. "')"),
		db, 'objects_scalar_columns_only_on_objects',
		'frame row with scalar_null should be rejected')

	db:close()
end)

test('o row populating two scalar columns is rejected', function()
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_string, scalar_number, owner_role) "
			.. "values ('o', 'x', 3.14, '" .. user .. "')"),
		db, 'objects_scalar_at_most_one_column',
		'two scalar_* columns should be rejected')

	assert_fails_with(
		db:exec("insert into objects (base, scalar_null, scalar_bool, owner_role) "
			.. "values ('o', 1, 1, '" .. user .. "')"),
		db, 'objects_scalar_at_most_one_column',
		'scalar_null + scalar_bool together should be rejected')

	db:close()
end)

test('o row populating all four scalar columns is rejected', function()
	local db = fresh_db()
	local user = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, scalar_null, scalar_string, scalar_number, scalar_bool, owner_role) "
			.. "values ('o', 1, 'x', 3.14, 1, '" .. user .. "')"),
		db, 'objects_scalar_at_most_one_column',
		'all four populated should be rejected')

	db:close()
end)


-- ============================================================
-- Immutability triggers
-- ============================================================

test('scalar_string is immutable after insert', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_string, owner_role) values ('o', 'first', '"
		.. user .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set scalar_string = 'second' where object_pk = '" .. pk .. "'"),
		db, 'objects_scalar_string_immutable',
		'scalar_string update should be rejected')

	db:close()
end)

test('scalar_number is immutable after insert', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_number, owner_role) values ('o', 1.0, '"
		.. user .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set scalar_number = 2.0 where object_pk = '" .. pk .. "'"),
		db, 'objects_scalar_number_immutable',
		'scalar_number update should be rejected')

	db:close()
end)

test('scalar_bool is immutable after insert', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_bool, owner_role) values ('o', 0, '"
		.. user .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set scalar_bool = 1 where object_pk = '" .. pk .. "'"),
		db, 'objects_scalar_bool_immutable',
		'scalar_bool update should be rejected')

	db:close()
end)

test('scalar_null is immutable after insert', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_null, owner_role) values ('o', 1, '"
		.. user .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set scalar_null = null where object_pk = '" .. pk .. "'"),
		db, 'objects_scalar_null_immutable',
		'scalar_null update should be rejected')

	db:close()
end)


-- ============================================================
-- scalars view
-- ============================================================

test('scalars view derives scalar_type and value for a string scalar', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_string, owner_role) values ('o', 'hi', '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_type, 's', 'string scalar type')
	h.assert_eq(row.value,       'hi', 'string scalar value')

	db:close()
end)

test('scalars view derives scalar_type and value for a number scalar', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_number, owner_role) values ('o', 2.5, '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_type,   'n', 'number scalar type')
	h.assert_eq(tonumber(row.value), 2.5, 'number scalar value')

	db:close()
end)

test('scalars view derives scalar_type and value for a boolean scalar', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_bool, owner_role) values ('o', 1, '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_type,   'b', 'boolean scalar type')
	h.assert_eq(tonumber(row.value), 1, 'boolean scalar value 1 = true')

	db:close()
end)

test('scalars view derives scalar_type u and value null for a null scalar', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, scalar_null, owner_role) values ('o', 1, '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_type, 'u', 'null scalar type')
	h.assert_true(row.value == nil,   'null scalar value is NULL')

	db:close()
end)

test('scalars view excludes plain o rows with no scalar assigned', function()
	local db = fresh_db()
	local user = seed_user(db)

	local pk = first(db,
		"insert into objects (base, owner_role) values ('o', '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	h.assert_true(row == nil, 'plain object should not show up in scalars view')

	db:close()
end)

test('scalars view excludes non-o rows', function()
	local db = fresh_db()
	local user = seed_user(db)

	local hash_pk = first(db,
		"insert into objects (base, owner_role) values ('h', '"
		.. user .. "') returning object_pk").object_pk

	local row = first(db, "select scalar_type, value from scalars where object_pk = '" .. hash_pk .. "'")
	h.assert_true(row == nil, 'hash row should not show up in scalars view')

	db:close()
end)

