--[[
{
	"spec": "test_end_to_end",
	"role": "End-to-end tests. Runs Caspian programs through the engine and asserts against the returned hash and resulting DB state. The empty-program case checks the shutdown shape; the `$x = 1` case exercises the whole dispatch chain — variable-scalar handler → set_local_to_scalar → cap advance."
}
]]

--[[
# `test_end_to_end`

End-to-end assertions. Two programs:

- **Empty program** (`engine.caspm = {}`) — `run()` seeds the cap + frame 0, walks the empty ast (nothing to dispatch), advances the cap to close the process_cap. Returns `{complete = 1, cap_pk = ...}`.
- **`$x = 1`** — full dispatch through the handler chain: variable-scalar handler → `frame:set_local_to_scalar('x', 'n', 1)` → scalar + bucket + scopes chain + marker; walker's advance sweeps the marker; cap's advance sweeps frame 0. Post-run: cap terminal, orphaned bucket marked `needs_trace = 1`, the `x` binding still walkable via the surviving ref chain. GC substrate not wired here; the reap of the orphans lands with GC integration.
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
		"select stmt_idx, gc from objects where object_pk = '" .. result.cap_pk .. "'")
	h.assert_true(cap ~= nil, 'cap should still exist (GC-substrate reap out of scope)')
	h.assert_eq(tonumber(cap.stmt_idx), 0, 'cap stmt_idx should be 0 (cap is born terminal — empty ast, terminal = length(ast) = 0)')
	h.assert_true(cap.gc == nil, 'cap gc should be null (caps are exempt from the child-delete → gc=1 cascade)')

	local cap_kids = scalar(e.cvm,
		"select count(*) from objects where parent_frame = '" .. result.cap_pk .. "'")
	h.assert_eq(cap_kids, 0, 'cap should have no children (frame 0 was cascade-swept)')

	-- The x binding survived orphaned. Walkable via the surviving ref chain.
	local binding = first(e.cvm,
		"select o.scalar_type, o.scalar_value from objects o "
		.. "join refs r on r.child = o.object_pk where r.key = 'x'")
	h.assert_true(binding ~= nil, 'x binding should still be walkable via ref chain')
	h.assert_eq(binding.scalar_type, 'n', 'x should bind to scalar_type=n')
	h.assert_eq(tonumber(binding.scalar_value), 1, 'x should bind to value 1')

	-- The orphaned bucket should be in the needs_trace worklist.
	local bucket = first(e.cvm,
		"select nt.object_pk from needs_trace nt "
		.. "join objects o on o.object_pk = nt.object_pk "
		.. "where o.primitive = 'h'")
	h.assert_true(bucket ~= nil, 'bucket should be in the needs_trace table')
end)
