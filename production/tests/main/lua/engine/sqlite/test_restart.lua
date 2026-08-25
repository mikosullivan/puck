--[[
{
	"spec": "test_restart",
	"role": "Restart end-to-end. A halted process (from %process.stop) continues via a subsequent Engine:run call. Optional restart_value is materialized as the leaf frame's rv and propagates up through the frame chain via frames_child_delete_propagates_rv, landing on the cap's rv slot. Bare restart, mid-program restart, string injection, number injection, and the wrong-leaf injection error path."
}
]]

--[[
# `test_restart`

Assertions for the restart-after-halt path.

`Engine:run` is the single entry point for both first-time execution and continuation-after-halt. First call bootstraps cap + frame 0; subsequent calls skip bootstrap and continue whatever the DB has. The recursion inside `restart_frame` descends from the cap through any halt chain, reaps leaf-up, and picks up past the halted statement.

Optional `restart_value` injects a reply into the leaf's rv before the descent kicks off. Only valid when the leaf is a stop frame (`engine_class = 'stop'`); other leaf states raise `engine_run_inject_requires_stop_frame`. The injected scalar propagates up via `frames_child_delete_propagates_rv` as each frame reaps, eventually landing in cap's bucket's `rv` ref.
]]

local h      = require('helpers')
local engine = require('engine')


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
-- Bare restart
-- ============================================================

h.test('bare restart completes a program that only had %process.stop', function()
	local e = engine.new()
	e:load('%process.stop')

	local halted = e:run()
	h.assert_eq(halted.stopped, 1, 'program halted first')

	local finished = e:run()
	h.assert_eq(finished.complete, 1, 'second run() returns complete=1')
	h.assert_true(finished.stopped == nil, 'second run() has no stopped field')

	-- Stop frame is gone (reaped by the descent).
	local stop_count = scalar(e.cvm,
		"select count(*) from objects where engine_class = 'stop'")
	h.assert_eq(tonumber(stop_count), 0, 'stop frame reaped on restart')
end)


-- ============================================================
-- Mid-program restart
-- ============================================================

h.test('restart resumes past the halted statement (mid-program)', function()
	-- Two-halt program so we can observe the DB in the middle: after
	-- the first halt, $foo is bound; after the second halt, both are
	-- bound. If restart went back to the start we'd never see $bar.
	local e = engine.new()
	e:load("$foo = 'before'\n%process.stop\n$bar = 'after'\n%process.stop")

	local halted = e:run()
	h.assert_eq(halted.stopped, 1, 'halted mid-program (first stop)')

	-- Before restart: $foo bound, $bar NOT yet bound.
	local foo = scalar(e.cvm, "select child from refs where key = 'foo'")
	local bar = scalar(e.cvm, "select child from refs where key = 'bar'")
	h.assert_not_nil(foo, "$foo bound at first halt")
	h.assert_true(bar == nil, "$bar NOT bound at first halt")

	local halted2 = e:run()
	h.assert_eq(halted2.stopped, 1, 'halted again after $bar (second stop)')

	local bar_after = scalar(e.cvm,
		"select scalar_string from objects where object_pk = "
		.. "(select r.child from refs r where r.key = 'bar')")
	h.assert_eq(bar_after, 'after', "$bar bound to 'after' after restart")
end)


-- ============================================================
-- Value injection: string
-- ============================================================

h.test("restart with a string value: cap's rv holds the injected scalar", function()
	local e = engine.new()
	e:load('%process.stop')

	e:run()
	e:run("hello from the host")

	-- Walk cap → bucket → rv → scalar
	local rv_string = scalar(e.cvm,
		"select o.scalar_string from objects o "
		.. "join refs rv_ref on rv_ref.child = o.object_pk and rv_ref.key = 'rv' "
		.. "join refs b_ref on b_ref.child = rv_ref.parent and b_ref.key = 'b' "
		.. "where b_ref.parent = '" .. e.cap_pk .. "'")

	h.assert_eq(rv_string, "hello from the host",
		"cap's rv holds the injected string after restart")
end)


-- ============================================================
-- Value injection: number
-- ============================================================

h.test("restart with a numeric value: cap's rv holds scalar_number", function()
	local e = engine.new()
	e:load('%process.stop')

	e:run()
	e:run(42)

	local rv_number = scalar(e.cvm,
		"select o.scalar_number from objects o "
		.. "join refs rv_ref on rv_ref.child = o.object_pk and rv_ref.key = 'rv' "
		.. "join refs b_ref on b_ref.child = rv_ref.parent and b_ref.key = 'b' "
		.. "where b_ref.parent = '" .. e.cap_pk .. "'")

	h.assert_eq(tonumber(rv_number), 42,
		"cap's rv holds the injected number after restart")
end)


-- ============================================================
-- Wrong-leaf injection
-- ============================================================

h.test("injecting on a non-halted process raises engine_run_inject_requires_stop_frame", function()
	-- Value injection only makes sense on a leaf that's a stop frame.
	-- A crash-restart or already-completed leaf has no stop marker to
	-- interpret the value as a reply for.
	local e = engine.new()
	e:load("$foo = 'plain'")
	e:run()  -- Completes normally; no stop frame in the DB.

	local ok, err = pcall(function() return e:run("some value") end)

	h.assert_eq(ok, false, "run(value) raised on a non-halted process")
	h.assert_true(
		err and tostring(err):find('engine_run_inject_requires_stop_frame', 1, true) ~= nil,
		'error message identifies engine_run_inject_requires_stop_frame; got: ' .. tostring(err))
end)
