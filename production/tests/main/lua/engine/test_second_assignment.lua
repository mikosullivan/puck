--[[
{
	"spec": "test_second_assignment",
	"role": "End-to-end tests for rebinding a local. Runs `$x = 1\\n$x = 2` and asserts that the walker drains the orphaned first-assignment scalar between statements, then drains the whole graph after frame 0's tail reap. Post-run: run() returns complete=1, the cap sits at its born-terminal state, refs is empty, and needs_trace is empty."
}
]]

--[[
# `test_second_assignment`

Assertions for the rebind path — `$x = 1` followed by `$x = 2`.

- Statement 0: `$x = 1` dispatches. Handler materializes scalar_1 and adds the frame_0 → bucket → scopes → scopes[0] → (key `x`) → scalar_1 chain. Nothing is orphaned yet; needs_trace stays empty.
- Statement 1: `$x = 2` dispatches. The upsert_ref path UPDATEs the existing `x` ref's `child` column from scalar_1 to scalar_2. The `refs_mark_needs_trace_after_child_update` trigger inserts scalar_1 into needs_trace.
- Between-statement drain (in `run_frame`): scalar_1 has no incoming refs (the ref was updated to point at scalar_2, not deleted, but the OLD child is what got marked and it now has no incoming ref). The drain reaps scalar_1; the needs_trace row cascades away with the objects row.
- Frame 0 hits terminal, `run_frame` reaps it, and the tail drain unwinds the orphaned bucket → scopes → scopes[0] → scalar_2 chain via successive reap-and-cascade cycles.
- End state: cap alone at (`stmt_idx = 0`, `gc = null`, no children); refs empty; needs_trace empty.
]]

local h      = require('helpers')
local engine = require('engine')


-- Fetch a single scalar from a one-row-one-column query. Returns nil if
-- no rows.
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


local SOURCE = '$x = 1\n$x = 2'


h.test('$x = 1 ; $x = 2: run() returns complete = 1', function()
	local e = engine.new()
	e:load(SOURCE)
	local result = e:run()

	h.assert_true(type(result) == 'table', 'run() should return a table')
	h.assert_eq(result.complete, 1, 'result.complete should be 1')
	h.assert_not_nil(result.cap_pk, 'result.cap_pk should be set')
end)

h.test('$x = 1 ; $x = 2: cap sits at its born-terminal state', function()
	local e = engine.new()
	e:load(SOURCE)
	local result = e:run()

	local stmt_idx = scalar(e.cvm,
		"select stmt_idx from objects where object_pk = ?",
		result.cap_pk)
	h.assert_eq(tonumber(stmt_idx), 0, 'cap stmt_idx should be 0')

	local gc = scalar(e.cvm,
		"select gc from objects where object_pk = ?",
		result.cap_pk)
	h.assert_true(gc == nil, 'cap gc should be null')

	local kids = scalar(e.cvm,
		"select count(*) from objects where parent_frame = ?",
		result.cap_pk)
	h.assert_eq(kids, 0, 'cap should have no children (frame 0 reaped)')
end)

h.test('$x = 1 ; $x = 2: needs_trace is empty at end of run', function()
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	local marks = scalar(e.cvm, 'select count(*) from needs_trace')
	h.assert_eq(marks, 0, 'needs_trace should have no rows after the drain sweeps the orphaned graph')
end)

h.test('$x = 1 ; $x = 2: refs is empty at end of run', function()
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	local refs = scalar(e.cvm, 'select count(*) from refs')
	h.assert_eq(refs, 0, 'refs should be empty after the drain reaps the whole orphaned chain')
end)

h.test('$x = 1 ; $x = 2: only cap + three core-role seeds remain in objects', function()
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	local total = scalar(e.cvm, 'select count(*) from objects')
	h.assert_eq(total, 4, 'expected four object rows (engine/cache/user seeds + cap) after the drain')

	local core_role_count = scalar(e.cvm, 'select count(*) from objects where core_role is not null')
	h.assert_eq(core_role_count, 3, 'expected the three core-role seeds')

	local cap_count = scalar(e.cvm, "select count(*) from objects where process_cap = 1")
	h.assert_eq(cap_count, 1, 'expected one cap frame (the process anchor)')
end)

h.test('$x = 1 ; $x = 2: both scalar values are gone from objects', function()
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	local ones = scalar(e.cvm,
		"select count(*) from objects where scalar_type = 'n' and scalar_value = 1")
	h.assert_eq(ones, 0, 'scalar_1 (the orphaned first-assignment value) should be reaped')

	local twos = scalar(e.cvm,
		"select count(*) from objects where scalar_type = 'n' and scalar_value = 2")
	h.assert_eq(twos, 0, 'scalar_2 (the surviving second-assignment value) should be reaped when frame 0 is')
end)
