--[[
{
	"spec": "test_end_to_end",
	"role": "End-to-end tests. Runs Caspian programs through the engine and asserts against the returned hash and resulting DB state. The empty-program case checks the shutdown shape; the `$x = 1` case exercises the whole dispatch chain — variable-scalar handler → set_local_to_scalar → cap advance."
}
]]

--[[
# `test_end_to_end`

End-to-end assertions. Two programs:

- **Empty program** (`engine.caspm = {}`) — `run()` seeds the cap + frame 0, walks the empty frame_ast (nothing to dispatch), advances the cap to close the frame_process_cap. Returns `{complete = 1, cap_pk = ...}`.
- **`$x = 1`** — full dispatch through the handler chain: variable-scalar handler inlines savepoint + add_scalar + ensure_own_scope + upsert_ref + mark_frame_gc → scalar + bucket + scopes chain + marker; walker's advance sweeps the marker; frame 0's reap orphans the whole chain; the tail drain unwinds bucket → scopes → scopes[0] → scalar_1 via successive reap-and-cascade cycles. Post-run: cap terminal, `refs` empty, `needs_trace` empty, only the cap and the three core-role seeds remain in `objects`.
]]

local h      = require('helpers')
local engine = require('engine')


-- Fetch a single scalar from a one-row-one-column query.
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

-- Fetch the first row (nrows shape) or nil.
local function first(cvm, sql, ...)
	local stmt = cvm:prepare(sql)

	if select('#', ...) > 0 then
		stmt:bind_values(...)
	end

	local out

	for row in stmt:nrows() do
		out = row
		break
	end

	stmt:reset()
	return out
end


h.test('empty program: run() returns {complete = 1, cap_pk = ...}', function()
	local e = engine.new()
	e.caspm = {}

	local returned = e:run()

	h.assert_true(type(returned) == 'table', 'expected run() to return a table')
	h.assert_eq(returned.complete, 1, 'expected returned.complete to be 1')
	h.assert_true(returned.cap_pk ~= nil, 'expected returned.cap_pk to be set')
end)

h.test('$x = 1: runs end-to-end through the dispatch chain', function()
	local e = engine.new()
	e:load('$x = 1')
	local result = e:run()

	-- Completion signal: cap in terminal shape.
	h.assert_eq(result.complete, 1, 'result.complete should be 1')

	local cap = first(e.cvm,
		"select frame_stmt_idx, frame_gc from objects where object_pk = '" .. result.cap_pk .. "'")
	h.assert_true(cap ~= nil, 'cap should still exist (the cap is the process anchor)')
	h.assert_eq(tonumber(cap.frame_stmt_idx), 1, 'cap frame_stmt_idx should be 1 (advanced through its cycle: frame 0 reap set cap.gc=1, run() ran gc + advanced)')
	h.assert_true(cap.frame_gc == nil, 'cap frame_gc should be null (auto-nulled by the advance-fires-set-null trigger)')

	local cap_kids = scalar(e.cvm,
		"select count(*) from objects where frame_parent = '" .. result.cap_pk .. "'")
	h.assert_eq(cap_kids, 0, 'cap should have no children (frame 0 reaped)')

	-- The whole orphaned chain (bucket → scopes → scopes[0] → x → scalar_1)
	-- was reaped by the tail drain after frame 0 went. refs is empty.
	local refs_count = scalar(e.cvm, 'select count(*) from refs')
	h.assert_eq(refs_count, 0, 'refs should be empty (whole orphaned chain reaped)')

	-- Nothing left in the drain worklist.
	local marks = scalar(e.cvm, 'select count(*) from needs_trace')
	h.assert_eq(marks, 0, 'needs_trace should be empty after the drain sweeps everything orphaned')

	-- Only the cap and the three core-role seeds remain in objects.
	local total = scalar(e.cvm, 'select count(*) from objects')
	h.assert_eq(total, 4, 'expected four object rows (engine/cache/user seeds + cap)')
end)
