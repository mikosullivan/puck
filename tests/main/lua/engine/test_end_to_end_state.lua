--[[
{
	"spec": "test_end_to_end_state",
	"role": "DB-state assertions for the end-to-end empty-program scenario. Runs an empty program and inspects the resulting CVM tables — with and without keep-alive — to confirm the shutdown behavior lands as designed. The return-hash shape check is in test_end_to_end.lua."
}
]]

--[[
# `test_end_to_end_state`

DB-state suite for the empty-program end-to-end scenario. What does the CVM look like after `e.caspm = {}; e:run()` returns? These tests check the `processes` and `objects` tables in both the auto-delete-default and keep-alive configurations.

The flagship shape check (empty array in → hash with two fields out) lives in [test_end_to_end.lua](https://puck.uno/tests/main/lua/engine/test_end_to_end.lua).
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

h.test('after empty run with keep-alive, the process row has complete = 1', function()
	local e = engine.new()
	e.auto_delete_process = false
	e.caspm = {}
	e:run()

	local count = scalar(e.cvm, 'select count(*) from processes where complete = 1')
	h.assert_eq(count, 1, 'expected exactly one process with complete = 1')

	local total = scalar(e.cvm, 'select count(*) from processes')
	h.assert_eq(total, 1, 'expected exactly one process row total')
end)

h.test('after empty run, the process row is auto-deleted by default', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local total = scalar(e.cvm, 'select count(*) from processes')
	h.assert_eq(total, 0, 'expected the process row to be gone after default auto-delete')
end)

h.test('after empty run, the frame row is gone from objects', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local frame_count = scalar(e.cvm, "select count(*) from objects where primitive = 'f'")
	h.assert_eq(frame_count, 0, 'expected zero frame rows after shutdown')
end)

h.test('after empty run, only the three core-role seeds remain in objects', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local total = scalar(e.cvm, 'select count(*) from objects')
	h.assert_eq(total, 3, 'expected three object rows (engine, cache, user seeds) after shutdown')

	local core_role_count = scalar(e.cvm, 'select count(*) from objects where core_role is not null')
	h.assert_eq(core_role_count, 3, 'expected all three surviving rows to be core-role seeds')
end)

h.test('after empty run, refs is still empty', function()
	local e = engine.new()
	e.caspm = {}
	e:run()

	local refs_count = scalar(e.cvm, 'select count(*) from refs')
	h.assert_eq(refs_count, 0, 'expected refs to remain empty')
end)

h.test('after empty run with keep-alive, message stays null (nothing set it)', function()
	local e = engine.new()
	e.auto_delete_process = false
	e.caspm = {}
	e:run()

	local null_message_count = scalar(e.cvm, 'select count(*) from processes where message is null')
	h.assert_eq(null_message_count, 1, 'expected the process row to have message = null')
end)
