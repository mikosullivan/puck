--[[
{
	"spec": "test_end_to_end_state",
	"role": "DB-state assertions for the end-to-end empty-program scenario. Runs an empty program and inspects the resulting CVM tables to confirm the shutdown behavior. Under the current design, a process is a cap frame in `objects`; the empty-program run leaves the cap in terminal state (stmt_idx=1, gc=null, no children) and frame 0 swept — the cap itself still sits until GC reaps it (GC substrate is out of scope for now)."
}
]]

--[[
# `test_end_to_end_state`

DB-state suite for the empty-program end-to-end scenario. What does the CVM look like after `e.caspm = {}; e:run()` returns? These tests assert the resulting state on `objects` and `refs`.

The return-value shape check (a hash with `complete` and `cap_pk`) lives in [test_end_to_end.lua](https://puck.uno/tests/main/lua/engine/test_end_to_end).
]]

local h      = require('helpers')
local engine = require('engine')

-- Fetch a single scalar from a one-row-one-column query. Returns nil
-- if no rows.
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

h.test('after empty run, the cap is in terminal state (stmt_idx=1, gc=null, no children)', function()
	local e = engine.new()
	e.caspm = {}
	local result = e:run()

	local cap = scalar(e.cvm,
		"select stmt_idx from objects where object_pk = ?",
		result.cap_pk)
	h.assert_eq(cap, 1, 'cap stmt_idx should be 1 (terminal)')

	local gc = scalar(e.cvm,
		"select gc from objects where object_pk = ?",
		result.cap_pk)
	h.assert_true(gc == nil, 'cap gc should be null (terminal); got: ' .. tostring(gc))

	local children = scalar(e.cvm,
		"select count(*) from objects where parent_frame = ?",
		result.cap_pk)
	h.assert_eq(children, 0, 'cap should have no children (frame 0 swept)')
end)

h.test('after empty run, frame 0 is gone from objects', function()
	local e = engine.new()
	e.caspm = {}
	local result = e:run()

	local nested_frame_count = scalar(e.cvm,
		"select count(*) from objects where primitive = 'f' and parent_frame is not null")
	h.assert_eq(nested_frame_count, 0, 'expected zero nested frames after shutdown (frame 0 swept)')

	-- Cap itself is still there — it's the process's row, awaiting reap.
	local cap_count = scalar(e.cvm,
		"select count(*) from objects where primitive = 'f' and process = 1")
	h.assert_eq(cap_count, 1, 'expected the cap to still be present (awaiting GC-substrate reap)')
end)

h.test('after empty run, only the three core-role seeds + the cap remain in objects', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local total = scalar(e.cvm, 'select count(*) from objects')
	h.assert_eq(total, 4, 'expected four object rows (engine/cache/user seeds + cap) after shutdown')

	local core_role_count = scalar(e.cvm, 'select count(*) from objects where core_role is not null')
	h.assert_eq(core_role_count, 3, 'expected the three core-role seeds')

	local cap_count = scalar(e.cvm, "select count(*) from objects where process = 1")
	h.assert_eq(cap_count, 1, 'expected one cap frame (the process anchor)')
end)

h.test('after empty run, refs is still empty', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local refs_count = scalar(e.cvm, 'select count(*) from refs')
	h.assert_eq(refs_count, 0, 'expected refs to remain empty (empty program creates no bindings)')
end)

h.test('after empty run, the return value carries complete=1 and the cap_pk', function()
	local e = engine.new()
	e.caspm = {}
	local result = e:run()

	h.assert_eq(result.complete, 1, 'result.complete should be 1')
	h.assert_true(result.cap_pk ~= nil, 'result.cap_pk should be set')
	h.assert_true(type(result.cap_pk) == 'string', 'result.cap_pk should be a string')
end)
