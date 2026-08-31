--[[
{
	"spec": "test_object_class",
	"role": "Tests for the Caspian root Object class. Verifies the class descriptor shape (name, parent, methods), the engine.classes registry wiring, and the behavior of each minimal-set method (==, !=, to_s) when invoked directly against a live engine. Direct-invocation testing here — the general mc dispatcher isn't yet built, so we call `Object.methods.NAME(frame, self_pk, ...)` synchronously and inspect the returned scalar's payload.",
	"status": "V0.1"
}
]]

local h      = require('helpers')
local engine = require('engine')
local Object = require('classes.object')


local function scalar(cvm, sql, ...)
	local stmt = cvm:prepare(sql)

	if select('#', ...) > 0 then
		stmt:bind_values(...)
	end

	local out

	for row in stmt:rows() do
		out = row[1]
	end

	stmt:reset()

	return out
end


--[[
Return a fresh engine plus a mock frame `{engine = e, owner_role = user_role_pk}`.
The user_role is one of the three seeded roles (engine / cache / user);
it's a valid owner_role for scalars created during test dispatch.
]]
local function fresh()
	local e = engine.new()
	local user_pk = scalar(e.cvm, "select object_pk from objects where role_core = 'u'")
	local frame = {engine = e, owner_role = user_pk}
	return e, frame, user_pk
end


-- ============================================================
-- Class descriptor shape
-- ============================================================

h.test('Object.name is the string "Object"', function()
	h.assert_eq(Object.name, 'Object', 'Object class carries its name')
end)

h.test('Object.parent is nil (Object is the root of the hierarchy)', function()
	h.assert_true(Object.parent == nil, 'Object has no parent class')
end)

h.test('Object.methods is a table', function()
	h.assert_true(type(Object.methods) == 'table', 'methods is a table')
end)

h.test('Object.methods contains ==, !=, and to_s', function()
	h.assert_true(type(Object.methods['==']) == 'function', '== method exists')
	h.assert_true(type(Object.methods['!=']) == 'function', '!= method exists')
	h.assert_true(type(Object.methods.to_s) == 'function', 'to_s method exists')
end)


-- ============================================================
-- engine.classes registry
-- ============================================================

h.test('engine.new() populates engine.classes.Object', function()
	local e = engine.new()
	h.assert_true(e.classes ~= nil, 'engine.classes exists')
	h.assert_true(e.classes.Object == Object,
		'engine.classes.Object is the shared class descriptor')
end)


-- ============================================================
-- Object:== — identity equality
-- ============================================================

h.test('==: same pk returns scalar_bool = 1 (true)', function()
	local e, frame, some_pk = fresh()

	local result_pk = Object.methods['=='](frame, some_pk, some_pk)

	local val = scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 1, 'scalar_bool = 1 (true) when pks match')
end)

h.test('==: different pks return scalar_bool = 0 (false)', function()
	local e, frame, user_pk = fresh()
	local engine_role_pk = scalar(e.cvm, "select object_pk from objects where role_core = 'e'")

	local result_pk = Object.methods['=='](frame, user_pk, engine_role_pk)

	local val = scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'scalar_bool = 0 (false) when pks differ')
end)


-- ============================================================
-- Object:!= — negated identity equality
-- ============================================================

h.test('!=: same pk returns scalar_bool = 0 (false)', function()
	local e, frame, some_pk = fresh()

	local result_pk = Object.methods['!='](frame, some_pk, some_pk)

	local val = scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'scalar_bool = 0 (false) when pks match')
end)

h.test('!=: different pks return scalar_bool = 1 (true)', function()
	local e, frame, user_pk = fresh()
	local engine_role_pk = scalar(e.cvm, "select object_pk from objects where role_core = 'e'")

	local result_pk = Object.methods['!='](frame, user_pk, engine_role_pk)

	local val = scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 1, 'scalar_bool = 1 (true) when pks differ')
end)


-- ============================================================
-- Object:to_s — default string representation
-- ============================================================

h.test('to_s: returns a scalar_string containing "#<Object " and the pk', function()
	local e, frame, some_pk = fresh()

	local result_pk = Object.methods.to_s(frame, some_pk)

	local str = scalar(e.cvm,
		"select scalar_string from objects where object_pk = ?", result_pk)
	h.assert_true(type(str) == 'string', 'result is a scalar_string')
	h.assert_true(str:find('#<Object ', 1, true) ~= nil,
		'string contains the "#<Object " prefix; got: ' .. tostring(str))
	h.assert_true(str:find(tostring(some_pk), 1, true) ~= nil,
		"string contains the object's pk; got: " .. tostring(str))
end)
