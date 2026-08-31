--[[
{
	"spec": "test_primitive_classes",
	"role": "Tests for the four primitive Caspian classes (Number, String, Boolean, Null). Verifies each descriptor's shape (name, parent=Object, methods table), engine.classes registration, and behavior of each class's method overrides (==, !=, to_s). Direct-invocation testing here — the general mc dispatcher isn't yet built, so we call `Class.methods.NAME(frame, self_pk, ...)` synchronously and inspect the returned scalar's payload.",
	"status": "V0.1"
}
]]

local h       = require('helpers')
local engine  = require('engine')
local Object  = require('classes.object')
local Number  = require('classes.number')
local String  = require('classes.string')
local Boolean = require('classes.boolean')
local Null    = require('classes.null')


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
Build a fresh engine plus a mock frame `{engine = e, owner_role = user_role_pk}`,
so method calls have a valid owner_role for any scalars they materialize.
]]
local function fresh()
	local e = engine.new()
	local user_pk = scalar(e.cvm, "select object_pk from objects where role_core = 'u'")
	local frame = {engine = e, owner_role = user_pk}
	return e, frame, user_pk
end


-- ============================================================
-- Descriptor shape + registration
-- ============================================================

h.test('Number: name, parent, methods', function()
	h.assert_eq(Number.name, 'Number', 'name')
	h.assert_true(Number.parent == Object, 'parent is Object')
	h.assert_true(type(Number.methods.to_s) == 'function', 'to_s method exists')
	h.assert_true(type(Number.methods['==']) == 'function', '== method exists')
	h.assert_true(type(Number.methods['!=']) == 'function', '!= method exists')
end)

h.test('String: name, parent, methods', function()
	h.assert_eq(String.name, 'String', 'name')
	h.assert_true(String.parent == Object, 'parent is Object')
	h.assert_true(type(String.methods.to_s) == 'function', 'to_s method exists')
	h.assert_true(type(String.methods['==']) == 'function', '== method exists')
	h.assert_true(type(String.methods['!=']) == 'function', '!= method exists')
end)

h.test('Boolean: name, parent, methods', function()
	h.assert_eq(Boolean.name, 'Boolean', 'name')
	h.assert_true(Boolean.parent == Object, 'parent is Object')
	h.assert_true(type(Boolean.methods.to_s) == 'function', 'to_s method exists')
	h.assert_true(type(Boolean.methods['==']) == 'function', '== method exists')
	h.assert_true(type(Boolean.methods['!=']) == 'function', '!= method exists')
end)

h.test('Null: name, parent, methods', function()
	h.assert_eq(Null.name, 'Null', 'name')
	h.assert_true(Null.parent == Object, 'parent is Object')
	h.assert_true(type(Null.methods.to_s) == 'function', 'to_s method exists')
	h.assert_true(type(Null.methods['==']) == 'function', '== method exists')
	h.assert_true(type(Null.methods['!=']) == 'function', '!= method exists')
end)

h.test('engine.classes registers all four primitive classes', function()
	local e = engine.new()
	h.assert_true(e.classes.Number  == Number,  'Number registered')
	h.assert_true(e.classes.String  == String,  'String registered')
	h.assert_true(e.classes.Boolean == Boolean, 'Boolean registered')
	h.assert_true(e.classes.Null    == Null,    'Null registered')
end)


-- ============================================================
-- Number:to_s / == / !=
-- ============================================================

h.test('Number:to_s renders 42 as "42" (no trailing .0)', function()
	local e, frame, user_pk = fresh()
	local pk = e.data:add_scalar(42, user_pk)

	local result_pk = Number.methods.to_s(frame, pk)

	local str = scalar(e.cvm, "select scalar_string from objects where object_pk = ?", result_pk)
	h.assert_eq(str, '42', "%g formatting hides the REAL-affinity trailing .0")
end)

h.test('Number:to_s renders 3.14 as "3.14"', function()
	local e, frame, user_pk = fresh()
	local pk = e.data:add_scalar(3.14, user_pk)

	local result_pk = Number.methods.to_s(frame, pk)

	local str = scalar(e.cvm, "select scalar_string from objects where object_pk = ?", result_pk)
	h.assert_eq(str, '3.14', 'fractional number renders faithfully')
end)

h.test('Number:== two 42-holding rows with different pks return true', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar(42, user_pk)
	local b = e.data:add_scalar(42, user_pk)
	h.assert_true(a ~= b, 'add_scalar produces distinct pks per call — precondition')

	local result_pk = Number.methods['=='](frame, a, b)

	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 1, 'value equality is true for same numeric payload')
end)

h.test('Number:== 42 vs 43 returns false', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar(42, user_pk)
	local b = e.data:add_scalar(43, user_pk)

	local result_pk = Number.methods['=='](frame, a, b)

	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'different values compare unequal')
end)

h.test('Number:== against a String returns false (type mismatch)', function()
	local e, frame, user_pk = fresh()
	local n = e.data:add_scalar(42, user_pk)
	local s = e.data:add_scalar('42', user_pk)

	local result_pk = Number.methods['=='](frame, n, s)

	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'Number vs String compares unequal')
end)

h.test('Number:!= 42 vs 42 returns false; 42 vs 43 returns true', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar(42, user_pk)
	local b = e.data:add_scalar(42, user_pk)
	local c = e.data:add_scalar(43, user_pk)

	local eq_pk = Number.methods['!='](frame, a, b)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", eq_pk)), 0,
		'!= is false for equal values')

	local ne_pk = Number.methods['!='](frame, a, c)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", ne_pk)), 1,
		'!= is true for different values')
end)


-- ============================================================
-- String:to_s / == / !=
-- ============================================================

h.test('String:to_s returns self_pk unchanged', function()
	local _, frame, user_pk = fresh()
	local pk = frame.engine.data:add_scalar('foo', user_pk)

	local result_pk = String.methods.to_s(frame, pk)
	h.assert_eq(result_pk, pk, 'to_s on a String returns the String itself')
end)

h.test('String:== two "foo"-holding rows with different pks return true', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar('foo', user_pk)
	local b = e.data:add_scalar('foo', user_pk)
	h.assert_true(a ~= b, 'precondition: distinct pks')

	local result_pk = String.methods['=='](frame, a, b)
	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 1, 'value equality is true for same string')
end)

h.test('String:== "foo" vs "bar" returns false', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar('foo', user_pk)
	local b = e.data:add_scalar('bar', user_pk)

	local result_pk = String.methods['=='](frame, a, b)
	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'different strings compare unequal')
end)

h.test('String:== against a Number returns false (type mismatch)', function()
	local e, frame, user_pk = fresh()
	local s = e.data:add_scalar('42', user_pk)
	local n = e.data:add_scalar(42, user_pk)

	local result_pk = String.methods['=='](frame, s, n)
	local val = scalar(e.cvm, "select scalar_bool from objects where object_pk = ?", result_pk)
	h.assert_eq(tonumber(val), 0, 'String vs Number compares unequal')
end)


-- ============================================================
-- Boolean:to_s / == / !=
-- ============================================================

h.test('Boolean:to_s renders true as "true", false as "false"', function()
	local e, frame, user_pk = fresh()
	local t = e.data:add_scalar(true, user_pk)
	local f = e.data:add_scalar(false, user_pk)

	local t_str_pk = Boolean.methods.to_s(frame, t)
	local f_str_pk = Boolean.methods.to_s(frame, f)

	h.assert_eq(scalar(e.cvm, "select scalar_string from objects where object_pk = ?", t_str_pk),
		'true', 'true stringifies to "true"')
	h.assert_eq(scalar(e.cvm, "select scalar_string from objects where object_pk = ?", f_str_pk),
		'false', 'false stringifies to "false"')
end)

h.test('Boolean:== true == true and false == false, both true', function()
	local e, frame, user_pk = fresh()
	local t1 = e.data:add_scalar(true, user_pk)
	local t2 = e.data:add_scalar(true, user_pk)
	local f1 = e.data:add_scalar(false, user_pk)
	local f2 = e.data:add_scalar(false, user_pk)

	local tt_pk = Boolean.methods['=='](frame, t1, t2)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", tt_pk)), 1, 'true == true')

	local ff_pk = Boolean.methods['=='](frame, f1, f2)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", ff_pk)), 1, 'false == false')
end)

h.test('Boolean:== true == false returns false', function()
	local e, frame, user_pk = fresh()
	local t = e.data:add_scalar(true, user_pk)
	local f = e.data:add_scalar(false, user_pk)

	local result_pk = Boolean.methods['=='](frame, t, f)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)), 0, 'true != false')
end)


-- ============================================================
-- Null:to_s / == / !=
-- ============================================================

h.test('Null:to_s always renders "null"', function()
	local e, frame, user_pk = fresh()
	local pk = e.data:add_scalar(nil, user_pk)  -- add_scalar with nil creates a scalar_null

	local result_pk = Null.methods.to_s(frame, pk)
	local str = scalar(e.cvm, "select scalar_string from objects where object_pk = ?", result_pk)
	h.assert_eq(str, 'null', 'null stringifies to "null"')
end)

h.test('Null:== two nulls (different pks) return true', function()
	local e, frame, user_pk = fresh()
	local a = e.data:add_scalar(nil, user_pk)
	local b = e.data:add_scalar(nil, user_pk)
	h.assert_true(a ~= b, 'precondition: distinct null-scalar pks')

	local result_pk = Null.methods['=='](frame, a, b)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)), 1,
		'all nulls are equal')
end)

h.test('Null:== against a non-null (Number) returns false', function()
	local e, frame, user_pk = fresh()
	local n = e.data:add_scalar(nil, user_pk)
	local m = e.data:add_scalar(42, user_pk)

	local result_pk = Null.methods['=='](frame, n, m)
	h.assert_eq(tonumber(scalar(e.cvm,
		"select scalar_bool from objects where object_pk = ?", result_pk)), 0,
		'Null vs Number compares unequal')
end)
