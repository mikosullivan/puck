--[[
{
	"module": "test_add_scalar",
	"role": "Numbers sprint: exercises the polymorphic cvm:add_scalar(value, owner_role_pk) — a single method that infers the scalar type from Lua's type(value) and routes to the right scalar_* column. Covers all four Lua types (string / number / boolean / nil), the integer→float REAL-affinity coercion for number inputs, boolean true/false → 1/0, and the raise for unsupported Lua types (function, thread, userdata, table).",
	"run": "lua5.4 sprints/numbers/tests/test_add_scalar.lua (from repo root)"
}
]]

local SCHEMA_PATH    = 'production/src/engine/cvm/sqlite/schema.sql'
local PREFLIGHT_PATH = 'production/src/engine/cvm/sqlite/preflight.sql'

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')
local Cvm                = require('cvm.sqlite')


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local function fresh_cvm()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')
	current_process_pk.register(db, function() return nil end)

	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))

	rc = db:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))

	return Cvm.new(db), db
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end

local function seed_user(db)
	return first(db, "select object_pk from objects where role_core = 'u'").object_pk
end


local h = require('helpers')
local test = h.test


-- ============================================================
-- Dispatch — one test per Lua type
-- ============================================================

test('add_scalar(string, owner) populates scalar_string', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar('hello', user)

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_eq(row.scalar_string, 'hello', 'scalar_string carries the value')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null')

	db:close()
end)

test('add_scalar(number, owner) populates scalar_number', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(3.14, user)

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_eq(tonumber(row.scalar_number), 3.14, 'scalar_number carries the value')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null')

	db:close()
end)

test('add_scalar(true, owner) stores scalar_bool = 1', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(true, user)

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_eq(tonumber(row.scalar_bool), 1, 'scalar_bool = 1 (true)')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null')

	db:close()
end)

test('add_scalar(false, owner) stores scalar_bool = 0', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(false, user)

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_eq(tonumber(row.scalar_bool), 0, 'scalar_bool = 0 (false)')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null')

	db:close()
end)

test('add_scalar(nil, owner) stores scalar_null = 1', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(nil, user)

	local row = first(db, "select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where object_pk = '" .. pk .. "'")
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_number == nil, 'scalar_number null')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_eq(tonumber(row.scalar_null), 1, 'scalar_null = 1 (marker for the u type)')

	db:close()
end)


-- ============================================================
-- Structural integer→float coercion at add_scalar time
-- ============================================================

test('add_scalar(integer, owner) coerces to REAL storage', function()
	-- The load-bearing test for the sprint. add_scalar passes a Lua
	-- integer to a REAL-affinity column; SQLite converts to REAL at
	-- insert time. Storage typeof should be 'real' regardless of
	-- whether the caller passed an integer or a float.
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(42, user)  -- Lua integer 42 (math.type = integer)

	local ty = first(db, "select typeof(scalar_number) as ty from objects where object_pk = '"
		.. pk .. "'").ty
	h.assert_eq(ty, 'real', 'integer input should land as real storage')

	db:close()
end)

test('add_scalar(float, owner) keeps REAL storage', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local pk = cvm:add_scalar(1.5, user)

	local ty = first(db, "select typeof(scalar_number) as ty from objects where object_pk = '"
		.. pk .. "'").ty
	h.assert_eq(ty, 'real', 'float input keeps real storage')

	db:close()
end)


-- ============================================================
-- Unsupported Lua types
-- ============================================================

test('add_scalar(table, owner) raises add_scalar_unsupported_value_type', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local ok, err = pcall(function() cvm:add_scalar({}, user) end)
	h.assert_true(not ok, 'table value should raise')
	h.assert_true(tostring(err):find('add_scalar_unsupported_value_type', 1, true) ~= nil,
		'error id present in message; got: ' .. tostring(err))
	h.assert_true(tostring(err):find('table', 1, true) ~= nil,
		'error message names the Lua type; got: ' .. tostring(err))

	db:close()
end)

test('add_scalar(function, owner) raises add_scalar_unsupported_value_type', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local ok, err = pcall(function() cvm:add_scalar(function() end, user) end)
	h.assert_true(not ok, 'function value should raise')
	h.assert_true(tostring(err):find('add_scalar_unsupported_value_type', 1, true) ~= nil,
		'error id present in message; got: ' .. tostring(err))

	db:close()
end)


-- ============================================================
-- View round-trip: value out matches value in
-- ============================================================

test('add_scalar values round-trip through the scalars view', function()
	local cvm, db = fresh_cvm()
	local user = seed_user(db)

	local s_pk = cvm:add_scalar('hi', user)
	local n_pk = cvm:add_scalar(42, user)
	local t_pk = cvm:add_scalar(true, user)
	local f_pk = cvm:add_scalar(false, user)
	local u_pk = cvm:add_scalar(nil, user)

	local function row_for(pk)
		return first(db, "select scalar_type, value from scalars where object_pk = '" .. pk .. "'")
	end

	h.assert_eq(row_for(s_pk).scalar_type,   's',  'string type')
	h.assert_eq(row_for(s_pk).value,         'hi', 'string value')
	h.assert_eq(row_for(n_pk).scalar_type,   'n',  'number type')
	h.assert_eq(tonumber(row_for(n_pk).value), 42, 'number value')
	h.assert_eq(row_for(t_pk).scalar_type,   'b',  'boolean type (true)')
	h.assert_eq(tonumber(row_for(t_pk).value), 1,  'boolean value 1')
	h.assert_eq(row_for(f_pk).scalar_type,   'b',  'boolean type (false)')
	h.assert_eq(tonumber(row_for(f_pk).value), 0,  'boolean value 0')
	h.assert_eq(row_for(u_pk).scalar_type,   'u',  'null type')
	h.assert_true(row_for(u_pk).value == nil,      'null value is NULL')

	db:close()
end)

