--[[
{
	"spec": "test_process_stop",
	"role": "%process.stop end-to-end. Runs programs that halt via %process.stop and asserts the shape of the halt: Engine:run returns {stopped=1, cap_pk=...}; a stop frame gets inserted with the right shape (engine_class='stop', empty ast, parent = the frame that dispatched %process.stop); state before the halt is preserved. Companion file test_restart.lua covers the resume path."
}
]]

--[[
# `test_process_stop`

Assertions for the `%process.stop` primitive.

The `handlers.process-stop` core handler (registered ahead of `MainHandler` in the stock chain) claims the `%process.stop` row shape via the normal dispatch pipeline. On match it inserts a stop frame under the currently-walking frame, then raises the HALT sentinel via `halt.raise()`. HALT unwinds through `dispatch` → `Frame:run_row` → `Frame:run` back to `Engine:run`'s xpcall, which catches it and returns `{stopped = 1, cap_pk = <pk>}`.

Post-halt: the stop frame is under whatever frame dispatched `%process.stop`; any state established by earlier statements in the same frame is preserved (variables bound before the halt are still walkable); a second `run` call resumes the process (see test_restart.lua).
]]

local h      = require('helpers')
local engine = require('engine')
local halt   = require('halt')


local function first(cvm, sql)
	for row in cvm:nrows(sql) do
		return row
	end
	return nil
end

local function scalar(cvm, sql)
	for row in cvm:rows(sql) do
		return row[1]
	end
	return nil
end


-- ============================================================
-- Halt shape
-- ============================================================

h.test('%process.stop halts the run and returns a stopped hash', function()
	local e = engine.new()
	e:load('%process.stop')
	local result = e:run()

	h.assert_eq(result.stopped, 1, 'result.stopped == 1')
	h.assert_true(result.complete == nil, 'result.complete is absent (halt, not completion)')
	h.assert_true(type(result.cap_pk) == 'string', 'result.cap_pk is a string')
end)

h.test('%process.stop inserts a stop frame with engine_class=stop', function()
	local e = engine.new()
	e:load('%process.stop')
	e:run()

	local row = first(e.cvm,
		"select base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent "
		.. "from objects where engine_class = 'stop'")

	h.assert_not_nil(row, 'stop frame exists after halt')
	h.assert_eq(row.base,         'o',    "stop frame base='o'")
	h.assert_eq(row.control,      'f',    "stop frame control='f'")
	h.assert_eq(row.engine_class, 'stop', "stop frame engine_class='stop'")
	h.assert_eq(row.frame_ast,    '[]',   "stop frame frame_ast='[]' (empty; terminal at birth)")
	h.assert_eq(tonumber(row.frame_stmt_idx), 0, "stop frame frame_stmt_idx=0")

	-- Parent is frame 0 (the only non-cap non-stop frame in this program).
	local frame_0 = first(e.cvm,
		"select object_pk from objects "
		.. "where control = 'f' and frame_process_cap is null and engine_class is null")
	h.assert_not_nil(frame_0, "frame 0 identifiable (non-cap, non-stop)")
	h.assert_eq(row.frame_parent, frame_0.object_pk, "stop frame's parent is frame 0")
end)

h.test("state established before %process.stop is preserved", function()
	local e = engine.new()
	e:load("$foo = 'bar'\n%process.stop")
	local result = e:run()

	h.assert_eq(result.stopped, 1, 'halted after the assignment')

	-- $foo binding survives — the walker never got past the halt to
	-- reap frame 0, so the whole ref chain is intact.
	local foo_scalar = scalar(e.cvm, "select r.child from refs r where r.key = 'foo'")
	h.assert_not_nil(foo_scalar, "$foo binding survives the halt")

	local bar_val = scalar(e.cvm,
		"select scalar_string from objects where object_pk = '" .. foo_scalar .. "'")
	h.assert_eq(bar_val, 'bar', "$foo still points at scalar_string='bar'")
end)


-- ============================================================
-- Halt is exception-based
-- ============================================================

h.test('halt.raise() raises the HALT sentinel; halt.is_halt recognizes it', function()
	local ok, err = pcall(function() halt.raise() end)

	h.assert_eq(ok, false, 'halt.raise() raises')
	h.assert_eq(halt.is_halt(err), true, 'the raised value is our sentinel')
end)

h.test('non-halt errors do not match halt.is_halt', function()
	local ok, err = pcall(function() error("something else") end)

	h.assert_eq(ok, false, 'raised non-halt error')
	h.assert_eq(halt.is_halt(err), false, 'is_halt correctly says NO')
end)

h.test('halt.is_halt identity check rejects shape-matched imposters', function()
	-- Constructing a table with the same {__signal=...} shape but a
	-- different sentinel table doesn't count as a halt. Identity, not shape.
	local fake = {__signal = {}}
	h.assert_eq(halt.is_halt(fake), false, 'identity check rejects shape-matched imposter')
end)


-- ============================================================
-- No `self.stopped` under HALT-as-sentinel
-- ============================================================

h.test('the engine has no self.stopped field under HALT-as-sentinel', function()
	local e = engine.new()
	h.assert_true(e.stopped == nil, 'e.stopped is nil at construction (field does not exist)')

	e:load('%process.stop')
	e:run()

	h.assert_true(e.stopped == nil, 'e.stopped is nil after halt (still no such field)')
end)


-- ============================================================
-- Normal completion regression
-- ============================================================

h.test('a program without %process.stop returns complete=1', function()
	local e = engine.new()
	e:load('$x = 1')
	local result = e:run()

	h.assert_eq(result.complete, 1, 'result.complete=1 on normal completion')
	h.assert_true(result.stopped == nil, 'result.stopped absent on normal completion')
end)
