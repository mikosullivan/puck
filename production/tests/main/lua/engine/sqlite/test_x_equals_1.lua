--[[
{
	"module": "test_x_equals_1",
	"role": "End-to-end tests running `$x = 1` (and rebind) through the engine. Verifies `run()` returns complete=1, cap advances through its cycle, and post-completion state is clean (refs empty, needs_trace empty, only the cap + core-role seeds remain in objects). Previously included a batch of halted-flavor tests (`\\n%process.stop` appended to inspect the mid-run graph before frame 0 reaped); those were removed when the ProcessStop handler was retired. They come back once %process.stop returns as a method on the process object under the core-method registry.",
	"run": "lua5.4 production/tests/main/lua/engine/run.lua (from repo root)"
}
]]

local engine = require('engine')


--[[
Fresh engine constructor — a thin shim so the test file has a single
place to touch if engine construction ever needs additional wiring.
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


local h    = require('helpers')
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
