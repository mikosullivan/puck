--[[
{
	"spec": "test_operator_normalization",
	"role": "Verifies that operator expressions (binary and unary) normalize to the mc method_call shape at the CaspM boundary AND that every sugar-derived mc envelope carries `syn = true`. Under Caspian's semantic model the only binary operator is `.`; every other operator symbol (arithmetic, logical, comparison, unary) is a method name dispatched on the left operand (binops) or on the operand (unary). Short-circuit ops (||, &&, and, or) are no different at the CaspM layer — their laziness is the method's implementation concern. The `syn` marker distinguishes these sugar-derived mc rows from directly-written `.method()` calls; readers use it for source-aware error messages and pretty-printing.",
	"status": "V0.1"
}
]]

local h          = require('helpers')
local cjson      = require('cjson')
local transpiler = require('transpiler')
local normalize  = require('normalize')


--[[
Deep structural equality on Lua tables. Hash-key order is not
significant; sequential-array order is. Nil / scalars compare via ==.
]]
local function deep_eq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= 'table' then return a == b end

	local a_keys = 0
	for k, v in pairs(a) do
		a_keys = a_keys + 1
		if not deep_eq(v, b[k]) then return false end
	end

	local b_keys = 0
	for _ in pairs(b) do b_keys = b_keys + 1 end

	return a_keys == b_keys
end


--[[
Load and normalize `src`; assert the resulting CaspM matches `expected`
structurally. Hash-key order in Lua tables is not significant; both
Lua tables and JSON encodings are compared through `deep_eq`, so the
test isn't fragile to cjson's key-iteration order.

The mismatch report includes both JSON encodings for easy diffing.
]]
local function assert_caspm(src, expected)
	local caspj = transpiler.transpile(src)
	local caspm = normalize.normalize(caspj)

	if not deep_eq(caspm, expected) then
		error('CaspM mismatch for source: ' .. src
			.. '\n  expected: ' .. cjson.encode(expected)
			.. '\n  got:      ' .. cjson.encode(caspm), 2)
	end
end


-- ============================================================
-- Binary operators — all method_call form, all with syn=true
-- ============================================================

h.test('1 || 2 normalizes to a `||` method_call with syn=true', function()
	assert_caspm('1 || 2', {
		{
			{cmd = 'mc'},
			{fn = '||', rcvr = {v = 1}, args = {{v = 2}}, syn = true},
		},
	})
end)

h.test('1 && 2 normalizes to a `&&` method_call with syn=true', function()
	assert_caspm('1 && 2', {
		{
			{cmd = 'mc'},
			{fn = '&&', rcvr = {v = 1}, args = {{v = 2}}, syn = true},
		},
	})
end)

h.test('1 or 2 normalizes to an `or` method_call with syn=true', function()
	assert_caspm('1 or 2', {
		{
			{cmd = 'mc'},
			{fn = 'or', rcvr = {v = 1}, args = {{v = 2}}, syn = true},
		},
	})
end)

h.test('1 and 2 normalizes to an `and` method_call with syn=true', function()
	assert_caspm('1 and 2', {
		{
			{cmd = 'mc'},
			{fn = 'and', rcvr = {v = 1}, args = {{v = 2}}, syn = true},
		},
	})
end)

h.test('1 + 2 (arithmetic) also carries syn=true', function()
	assert_caspm('1 + 2', {
		{
			{cmd = 'mc'},
			{fn = '+', rcvr = {v = 1}, args = {{v = 2}}, syn = true},
		},
	})
end)


-- ============================================================
-- Unary operators — receiver-only method_call with syn=true
-- ============================================================

h.test('!1 normalizes to a `!` method_call on {v:1} with syn=true', function()
	assert_caspm('!1', {
		{
			{cmd = 'mc'},
			{fn = '!', rcvr = {v = 1}, syn = true},
		},
	})
end)


-- ============================================================
-- Variable operands
-- ============================================================

h.test('$foo || $bar keeps syn=true', function()
	assert_caspm('$foo || $bar', {
		{
			{cmd = 'mc'},
			{fn = '||', rcvr = {var = 'foo'}, args = {{var = 'bar'}}, syn = true},
		},
	})
end)


-- ============================================================
-- Setvar / setat / bareword call — all sugar → syn=true
-- ============================================================

h.test('$x = 1 (setvar) normalizes to `=` on {sys:frame} with syn=true', function()
	assert_caspm('$x = 1', {
		{
			{cmd = 'mc'},
			{fn = '=', rcvr = {sys = 'frame'}, args = {'x', {v = 1}}, syn = true},
		},
	})
end)

h.test('@x = 1 (setat) normalizes to `[]=` on {sys:bucket} with syn=true', function()
	assert_caspm('@x = 1', {
		{
			{cmd = 'mc'},
			{fn = '[]=', rcvr = {sys = 'bucket'}, args = {{v = 'x'}, {v = 1}}, syn = true},
		},
	})
end)

h.test('@x (@-read) normalizes to `[]` on {sys:bucket} with syn=true', function()
	-- Read `@x` as the RHS of an assignment so it appears in an
	-- expression position where the object-atom @ handler fires.
	assert_caspm('$y = @x', {
		{
			{cmd = 'mc'},
			{
				fn = '=',
				rcvr = {sys = 'frame'},
				args = {
					'y',
					{
						{cmd = 'mc'},
						{fn = '[]', rcvr = {sys = 'bucket'}, args = {{v = 'x'}}, syn = true},
					},
				},
				syn = true,
			},
		},
	})
end)

h.test('foo (bareword call) normalizes to `call` on {var:foo} with syn=true', function()
	assert_caspm('foo', {
		{
			{cmd = 'mc'},
			{fn = 'call', rcvr = {var = 'foo'}, syn = true},
		},
	})
end)

h.test('&foo (amp call) normalizes to `call` on {var:foo} with syn=true', function()
	assert_caspm('&foo', {
		{
			{cmd = 'mc'},
			{fn = 'call', rcvr = {var = 'foo'}, syn = true},
		},
	})
end)


-- ============================================================
-- Directly-written method calls DO NOT carry syn
-- ============================================================
-- `foo.bar` — user literally wrote the dot-method call. The outer `.bar`
-- is a direct call (no syn). The inner receiver is `foo` bareword,
-- which under bwc-sugar becomes an mc that DOES carry syn.

h.test('foo.bar: outer `.bar` mc has NO syn; inner `foo`→call mc has syn=true', function()
	assert_caspm('foo.bar', {
		{
			{cmd = 'mc'},
			{
				fn = 'bar',
				rcvr = {
					{cmd = 'mc'},
					{fn = 'call', rcvr = {var = 'foo'}, syn = true},
				},
			},
		},
	})
end)

h.test('$foo.bar: outer `.bar` mc has NO syn; receiver is {var:foo} atom', function()
	assert_caspm('$foo.bar', {
		{
			{cmd = 'mc'},
			{fn = 'bar', rcvr = {var = 'foo'}},
		},
	})
end)


-- ============================================================
-- Compound setvar (setvar_op) — both outer `=` and inner op carry syn=true
-- ============================================================

h.test('$x += 1 (compound assignment): outer `=` and inner `+` both syn=true', function()
	assert_caspm('$x += 1', {
		{
			{cmd = 'mc'},
			{
				fn = '=',
				rcvr = {sys = 'frame'},
				args = {
					'x',
					{
						{cmd = 'mc'},
						{fn = '+', rcvr = {var = 'x'}, args = {{v = 1}}, syn = true},
					},
				},
				syn = true,
			},
		},
	})
end)
