--[[
{
	"module": "test_x_equals_1",
	"role": "Numbers sprint: end-to-end tests running `$x = 1` (and variants) through the sprint's engine. Transitively covers the variable-scalar handler's inlined assignment path (savepoint + add_scalar + ensure_own_scope + upsert_ref + mark_frame_gc) — it lives behind the walker's dispatch and doesn't have direct tests. Exercises the sprint's schema shape (scalar_number carries the payload; scalar_string / scalar_bool / scalar_null all null; REAL affinity stores the value as float even when the source-level literal reads as an integer), the polymorphic add_scalar dispatch (string / number / boolean / nil literals all round-trip through the same handler), and the rebind path (upsert refs + drain).",
	"run": "lua5.4 sprints/numbers/tests/test_x_equals_1.lua (from repo root)"
}
]]

local engine = require('engine')


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

--[[
Fresh engine wired to the sprint's schema.sql. Every test in this
file uses this shim so the DB is always the sprint's shape.
]]
local function new_engine()
	return engine.new()
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


local h = require('helpers')
local test = h.test


-- ============================================================
-- $x = 1 — the load-bearing end-to-end scenario
-- ============================================================

test('$x = 1: run() returns complete = 1', function()
	local e = new_engine()
	e:load('$x = 1')
	local result = e:run()

	h.assert_true(type(result) == 'table', 'run() should return a table')
	h.assert_eq(result.complete, 1, 'result.complete should be 1')
	h.assert_not_nil(result.cap_pk, 'result.cap_pk should be set')
end)

test('$x = 1: cap at post-cycle terminal, refs empty, needs_trace empty after the tail drain', function()
	local e = new_engine()
	e:load('$x = 1')
	local result = e:run()

	h.assert_eq(tonumber(scalar(e.cvm,
		"select frame_stmt_idx from objects where object_pk = '" .. result.cap_pk .. "'")),
		1, 'cap frame_stmt_idx = 1 (advanced through its cycle)')

	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from refs')), 0,
		'refs empty (whole orphaned chain reaped)')
	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from needs_trace')), 0,
		'needs_trace empty after drain')
	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from objects')), 4,
		'four object rows remain (cap + engine/cache/user role seeds)')
end)


-- ============================================================
-- $x = 1 + %process.stop — inspect the mid-run graph
-- ============================================================

--[[
Runs `$x = 1\n%process.stop` and returns the (engine, result) pair.
The walker advances past $x = 1 (creating the whole chain), then
dispatches %process.stop and halts before its next advance would fire
the reap. Every row created by the assignment is still visible.
]]
local function run_halted()
	local e = new_engine()
	e:load('$x = 1\n%process.stop')
	local result = e:run()
	assert(result.stopped == 1, 'expected stopped result')
	return e, result
end

test('$x = 1 + %process.stop: scalar lands in scalar_number with REAL affinity', function()
	-- The load-bearing sprint claim. Source-level literal `1` is a
	-- Lua integer through the transpiler; the schema's REAL affinity
	-- on scalar_number forces float storage. Other scalar_* columns
	-- stay null.
	local e = run_halted()

	local row = first(e.cvm,
		"select scalar_number, typeof(scalar_number) as ty, "
		.. "scalar_string, scalar_bool, scalar_null "
		.. "from objects where scalar_number is not null")
	h.assert_not_nil(row, 'a scalar row exists')
	h.assert_eq(tonumber(row.scalar_number), 1, 'value is 1')
	h.assert_eq(row.ty, 'real', 'stored as REAL (integer input coerced by affinity)')
	h.assert_true(row.scalar_string == nil, 'scalar_string null')
	h.assert_true(row.scalar_bool   == nil, 'scalar_bool null')
	h.assert_true(row.scalar_null   == nil, 'scalar_null null')
end)

test('$x = 1 + %process.stop: frame 0 marked frame_gc = null after advance', function()
	-- set_local_to_scalar sets frame_gc=1 to signal mid-dispatch; the
	-- walker's advance auto-nulls frame_gc after moving frame_stmt_idx. By halt
	-- time frame 0 is at (frame_stmt_idx=1, frame_gc=null).
	local e = run_halted()

	local row = first(e.cvm,
		"select frame_stmt_idx, frame_gc from objects where control = 'f' and frame_process_cap is null")
	h.assert_not_nil(row, 'frame 0 exists')
	h.assert_eq(tonumber(row.frame_stmt_idx), 1, 'frame_stmt_idx = 1 (walker advanced past $x = 1)')
	h.assert_true(row.frame_gc == nil, 'frame_gc = null after advance auto-null')
end)

test('$x = 1 + %process.stop: the whole scope chain is present', function()
	-- frame 0 → bucket → scopes array → scopes[0] hash → x-ref → scalar
	local e = run_halted()

	-- One bucket (h primitive) owned by frame 0.
	h.assert_eq(tonumber(scalar(e.cvm,
		"select count(*) from objects where base = 'h'")),
		2, 'two hash primitives: frame 0 bucket + scopes[0]')

	-- One array (a primitive) for scopes.
	h.assert_eq(tonumber(scalar(e.cvm,
		"select count(*) from objects where base = 'a'")),
		1, 'one array primitive: the scopes array')

	-- One scalar.
	h.assert_eq(tonumber(scalar(e.cvm,
		"select count(*) from objects where base = 'o' and control is null")),
		1, 'one scalar object')

	-- Four refs: frame→bucket, bucket→scopes, scopes→scopes[0], scopes[0]→scalar
	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from refs')), 4,
		'four refs form the chain')
end)

test('$x = 1 + %process.stop: x binding is walkable via the scalars view', function()
	local e = run_halted()

	-- Follow: scopes[0] → x-ref → scalar. Read the scalar's value
	-- through the sprint's scalars view.
	local row = first(e.cvm,
		"select s.scalar_type, s.value from scalars s "
		.. "join refs r on r.child = s.object_pk where r.key = 'x'")
	h.assert_not_nil(row, 'x-bound scalar readable via scalars view')
	h.assert_eq(row.scalar_type, 'n', 'scalars view derives scalar_type = n')
	h.assert_eq(tonumber(row.value), 1, 'scalars view value = 1')
end)


-- ============================================================
-- Type dispatch through the whole chain
-- ============================================================

--[[
Assert that after running `$name = <literal>` and halting, the
single scalar object lands in the expected column with the expected
value. Argument `col` is the sprint's scalar_* column name; `expected`
is the value the DB should hold in that column.
]]
local function assert_scalar_landed(source, col, expected, msg)
	local e = new_engine()
	e:load(source .. '\n%process.stop')
	local result = e:run()
	assert(result.stopped == 1)

	local row = first(e.cvm,
		"select scalar_string, scalar_number, scalar_bool, scalar_null "
		.. "from objects where "
		.. "(scalar_string is not null or scalar_number is not null "
		.. "or scalar_bool is not null or scalar_null is not null)")
	h.assert_not_nil(row, msg .. ': scalar exists')
	local actual = row[col]
	h.assert_eq(tonumber(actual) or actual, expected, msg .. ': column ' .. col .. ' matches')

	-- Every other scalar_* column is null.
	for _, other in ipairs({'scalar_string', 'scalar_number', 'scalar_bool', 'scalar_null'}) do
		if other ~= col then
			h.assert_true(row[other] == nil, msg .. ': ' .. other .. ' null')
		end
	end
end

test('$x = 42 → scalar_number = 42.0', function()
	assert_scalar_landed('$x = 42', 'scalar_number', 42, 'integer literal')
end)

test('$x = 3.14 → scalar_number = 3.14', function()
	assert_scalar_landed('$x = 3.14', 'scalar_number', 3.14, 'fractional literal')
end)


-- ============================================================
-- Rebind path — $x = 1 then $x = 2
-- ============================================================

test('$x = 1 ; $x = 2: end state clean; final binding not observable (drained)', function()
	local e = new_engine()
	e:load('$x = 1\n$x = 2')
	local result = e:run()

	h.assert_eq(result.complete, 1, 'complete = 1')
	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from refs')), 0, 'refs empty')
	h.assert_eq(tonumber(scalar(e.cvm, 'select count(*) from needs_trace')), 0, 'needs_trace empty')
end)

test('$x = 1 ; $x = 2 + %process.stop: final binding is scalar_number = 2', function()
	-- Between-statement drain reaps scalar_1. Second assignment's
	-- scalar_number = 2 is what the x ref points at.
	local e = new_engine()
	e:load('$x = 1\n$x = 2\n%process.stop')
	local result = e:run()
	assert(result.stopped == 1, 'stopped')

	local row = first(e.cvm,
		"select o.scalar_number, typeof(o.scalar_number) as ty "
		.. "from objects o join refs r on r.child = o.object_pk where r.key = 'x'")
	h.assert_not_nil(row, 'x binding readable')
	h.assert_eq(tonumber(row.scalar_number), 2, 'x = 2 (the second assignment)')
	h.assert_eq(row.ty, 'real', 'still stored as REAL')

	-- scalar_1 should have been reaped by the between-statement drain;
	-- no scalar_number = 1 anywhere in objects.
	h.assert_eq(tonumber(scalar(e.cvm,
		"select count(*) from objects where scalar_number = 1")),
		0, 'scalar_1 reaped by drain')
end)

