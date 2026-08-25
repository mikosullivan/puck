--[[
{
	"module": "test_variable_scalar",
	"role": "Numbers sprint: direct unit tests for the variable-scalar handler under the sprint's simplified signature (no scalar_type arg computed by the handler — the value is passed straight through to set_local_to_scalar → add_scalar, which dispatches on Lua type). Covers the handler's dispatch logic — match / no-match, guard clauses, raise sites — that the end-to-end tests in test_x_equals_1 can't reach because they always go through the walker's happy path.",
	"run": "lua5.4 sprints/numbers/tests/test_variable_scalar.lua (from repo root)"
}
]]

local engine         = require('engine')
local VariableScalar = require('handlers.variable-scalar')


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

--[[
Fresh engine wired to the sprint's schema, with cap + frame 0 seeded
and `engine.current_frame_pk` / `engine.current_role_pk` set to frame 0.
The variable-scalar handler needs both fields populated to work.
]]
local function engine_with_live_frame()
	local e = engine.new()

	-- Look up the user role.
	local user_pk
	for row in e.cvm:nrows("select object_pk from objects where role_core = 'u'") do
		user_pk = row.object_pk
	end

	-- Seed a cap frame.
	local cap_pk
	for row in e.cvm:nrows(
		"insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) "
		.. "values ('o', 'f', 1, '[null]', 0, '" .. user_pk .. "') returning object_pk")
	do
		cap_pk = row.object_pk
	end
	e.cap_pk = cap_pk

	-- Seed frame 0 under the cap. Non-empty frame_ast so the frame isn't
	-- born terminal — set_local_to_scalar marks frame_gc=1 and the schema
	-- forbids frame_gc=1 on a terminal frame.
	local frame_pk
	for row in e.cvm:nrows(
		"insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) "
		.. "values ('o', 'f', '[[]]', 0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk")
	do
		frame_pk = row.object_pk
	end

	e.current_frame_pk = frame_pk
	e.current_role_pk  = e.data:role_by_pk(frame_pk)
	return e
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end


local h = require('helpers')
local test = h.test


-- ============================================================
-- Match / no-match dispatch
-- ============================================================

test('handler returns true for {in=\'as\'} row shape', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()
	local row = {{['in'] = 'as'}, 'x', {v = 1}}

	local rc = handler:handle(e, row)
	h.assert_eq(rc, true, 'returned true')

	-- Side effect: scalar row created.
	h.assert_eq(tonumber(first(e.cvm,
		"select count(*) as n from objects where scalar_number is not null").n),
		1, 'a number scalar landed')
end)

test('handler returns false when row[1] is not a table', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {'not-a-table', 'x', {v = 1}}), false,
		'string head returns false')
	h.assert_eq(handler:handle(e, {42, 'x', {v = 1}}), false,
		'number head returns false')
	h.assert_eq(handler:handle(e, {nil, 'x', {v = 1}}), false,
		'nil head returns false')
end)

test('handler returns false when row[1].in is not \'as\'', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'fc'}, 'x', {v = 1}}), false,
		'other in-value returns false')
	h.assert_eq(handler:handle(e, {{other = 'as'}, 'x', {v = 1}}), false,
		'missing in-key returns false')
end)


-- ============================================================
-- Guard clauses — raise sites
-- ============================================================

test('handler raises variable_scalar_no_current_frame when engine.current_frame_pk is unset', function()
	local e = engine.new()
	-- Deliberately don't set e.current_frame_pk.
	local handler = VariableScalar.new()

	local ok, err = pcall(function()
		handler:handle(e, {{['in'] = 'as'}, 'x', {v = 1}})
	end)
	h.assert_true(not ok, 'raised')
	h.assert_true(tostring(err):find('variable_scalar_no_current_frame', 1, true) ~= nil,
		'error id present; got: ' .. tostring(err))
end)

test('handler raises variable_scalar_unsupported_value_atom when value atom is malformed', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	-- Missing v field.
	local ok, err = pcall(function()
		handler:handle(e, {{['in'] = 'as'}, 'x', {other = 1}})
	end)
	h.assert_true(not ok, 'raised on missing v field')
	h.assert_true(tostring(err):find('variable_scalar_unsupported_value_atom', 1, true) ~= nil,
		'error id present; got: ' .. tostring(err))

	-- value_atom not a table.
	ok, err = pcall(function()
		handler:handle(e, {{['in'] = 'as'}, 'x', 'raw-string'})
	end)
	h.assert_true(not ok, 'raised on non-table value atom')
	h.assert_true(tostring(err):find('variable_scalar_unsupported_value_atom', 1, true) ~= nil,
		'error id present; got: ' .. tostring(err))
end)


-- ============================================================
-- Value dispatch through the handler — each Lua type routes to its
-- own scalar_* column
-- ============================================================

test('number literal routes to scalar_number (REAL storage)', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 'n', {v = 42}}), true)

	local row = first(e.cvm,
		"select scalar_number, typeof(scalar_number) as ty from objects "
		.. "where scalar_number is not null")
	h.assert_not_nil(row, 'scalar landed')
	h.assert_eq(tonumber(row.scalar_number), 42, 'value 42')
	h.assert_eq(row.ty, 'real', 'REAL affinity (integer input coerced)')
end)

test('string literal routes to scalar_string (TEXT storage)', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 's', {v = 'hello'}}), true)

	local row = first(e.cvm,
		"select scalar_string, typeof(scalar_string) as ty from objects "
		.. "where scalar_string is not null")
	h.assert_not_nil(row, 'scalar landed')
	h.assert_eq(row.scalar_string, 'hello', 'value carried')
	h.assert_eq(row.ty, 'text', 'TEXT affinity')
end)

test('boolean true routes to scalar_bool = 1', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 'b', {v = true}}), true)

	local row = first(e.cvm,
		"select scalar_bool from objects where scalar_bool is not null")
	h.assert_not_nil(row, 'scalar landed')
	h.assert_eq(tonumber(row.scalar_bool), 1, 'true stored as 1')
end)

test('boolean false routes to scalar_bool = 0', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 'b', {v = false}}), true)

	local row = first(e.cvm,
		"select scalar_bool from objects where scalar_bool is not null")
	h.assert_not_nil(row, 'scalar landed')
	h.assert_eq(tonumber(row.scalar_bool), 0, 'false stored as 0')
end)


-- ============================================================
-- Chain construction — the handler's whole successful path
-- ============================================================

test('successful dispatch builds bucket → scopes → scopes[0] → x → scalar', function()
	local e = engine_with_live_frame()
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 'x', {v = 7}}), true)

	-- One bucket, one scopes array, one scopes[0] hash.
	h.assert_eq(tonumber(first(e.cvm,
		"select count(*) as n from objects where base = 'h'").n),
		2, 'two hash primitives: bucket + scopes[0]')
	h.assert_eq(tonumber(first(e.cvm,
		"select count(*) as n from objects where base = 'a'").n),
		1, 'one array primitive: scopes')

	-- x-ref lands in scopes[0].
	local ref = first(e.cvm,
		"select r.key, r.idx from refs r "
		.. "join objects o on o.object_pk = r.child where o.scalar_number = 7")
	h.assert_not_nil(ref, 'x → scalar ref exists')
	h.assert_eq(ref.key, 'x', 'ref key is x')
end)

test('successful dispatch marks the current frame frame_gc = 1', function()
	local e = engine_with_live_frame()
	local frame_pk = e.current_frame_pk
	local handler = VariableScalar.new()

	h.assert_eq(handler:handle(e, {{['in'] = 'as'}, 'x', {v = 1}}), true)

	local frame_gc = first(e.cvm,
		"select frame_gc from objects where object_pk = '" .. frame_pk .. "'").frame_gc
	h.assert_eq(tonumber(frame_gc), 1, 'frame marked frame_gc = 1 (mid-dispatch signal)')
end)

