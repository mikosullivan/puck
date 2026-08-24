#!/usr/bin/env lua5.4

--[[
{
	"module": "test_process_stop",
	"role": "Tests for the stop sprint's rewritten ProcessStop handler + StopLarry.run override. Loads sprint's Larry (which loads production Engine + swaps in the sprint's ProcessStop). Runs small programs that halt via %process.stop and asserts the shape of the halt: run() returns stopped-hash; a stop frame gets inserted with the right shape (engine_class='stop', empty ast, parent = the frame that called it); state before the halt is preserved.",
	"invoke": "lua5.4 sprints/stop/tests/test_process_stop.lua"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'sprints/stop/src/?.lua;'
	.. 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. 'production/tests/main/lua/engine/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local StopLarry = require('stop_larry')
local halt      = require('halt')


-- ------------------------------------------------------------
-- Assertion helpers
-- ------------------------------------------------------------

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(string.format("  \27[32mok\27[0m   %s", label))
end

local function fail(label, why)
	failed = failed + 1
	print(string.format("  \27[31mFAIL\27[0m %s", label))
	print(string.format("       %s", why))
end

local function assert_eq(actual, expected, label)
	if actual == expected then
		pass(label)
	else
		fail(label, string.format('expected %s, got %s', tostring(expected), tostring(actual)))
	end
end

local function scalar(db, sql)
	for r in db:rows(sql) do
		return r[1]
	end
	return nil
end

local function first(db, sql)
	for r in db:nrows(sql) do
		return r
	end
	return nil
end


-- ============================================================
-- Halt shape
-- ============================================================

print("== halt shape ==")

do  -- %process.stop halts the run and returns a stopped hash
	local e = StopLarry.new()
	e:load("%process.stop")

	local result = e:run()

	assert_eq(result.stopped,   1,        "result.stopped == 1")
	assert_eq(type(result.cap_pk), 'string', "result.cap_pk is a string")
end

do  -- A stop frame gets inserted with engine_class='stop'
	local e = StopLarry.new()
	e:load("%process.stop")

	local result = e:run()

	local row = first(e.cvm,
		"select base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent "
		.. "from objects where engine_class = 'stop'")

	if row then
		pass("stop frame exists after halt")
	else
		fail("stop frame exists after halt", "no row with engine_class='stop'")
		os.exit(1)
	end

	assert_eq(row.base,           'o',   "stop frame base='o'")
	assert_eq(row.control,        'f',   "stop frame control='f'")
	assert_eq(row.engine_class,   'stop', "stop frame engine_class='stop'")
	assert_eq(row.frame_ast,      '[]',  "stop frame frame_ast='[]' (empty; terminal at birth)")
	assert_eq(tonumber(row.frame_stmt_idx), 0, "stop frame frame_stmt_idx=0")

	-- Parent is frame 0 (the only nested frame in this trivial program)
	local frame_0 = first(e.cvm,
		"select object_pk from objects "
		.. "where control = 'f' and frame_process_cap is null and engine_class is null")

	if frame_0 then
		assert_eq(row.frame_parent, frame_0.object_pk,
			"stop frame's parent is frame 0")
	else
		fail("stop frame's parent identifiable", "no non-cap non-stop frame found")
	end
end

do  -- State BEFORE the stop is preserved: `$foo = 'bar'; %process.stop`
	local e = StopLarry.new()
	e:load("$foo = 'bar'\n%process.stop")

	local result = e:run()

	assert_eq(result.stopped, 1, "halted after the assignment")

	-- Verify $foo = 'bar' is still in the scope chain
	local foo_val = scalar(e.cvm,
		"select r.child from refs r where r.key = 'foo'")

	if foo_val then
		pass("$foo scope binding survives the halt")
	else
		fail("$foo scope binding survives the halt", "no ref with key='foo'")
		os.exit(1)
	end

	local bar = first(e.cvm,
		"select scalar_string from objects where object_pk = '" .. foo_val .. "'")

	assert_eq(bar and bar.scalar_string, 'bar', "$foo still points at scalar_string='bar'")
end


-- ============================================================
-- Halt is exception-based
-- ============================================================

print()
print("== halt is exception-based ==")

do  -- halt.is_halt recognizes the sentinel
	local ok, err = pcall(function() halt.raise() end)

	assert_eq(ok,               false, "halt.raise() raises")
	assert_eq(halt.is_halt(err), true, "the raised value is our sentinel")
end

do  -- Non-halt errors don't match is_halt
	local ok, err = pcall(function() error("something else") end)

	assert_eq(ok,               false, "raised non-halt error")
	assert_eq(halt.is_halt(err), false, "is_halt correctly says NO")
end

do  -- Shape-matched but wrong-identity table doesn't match is_halt
	-- Constructing a table with the same shape but a different __signal
	-- object should NOT be recognized as a halt. Identity, not shape.
	local fake = {__signal = {}}
	assert_eq(halt.is_halt(fake), false, "identity check rejects shape-matched imposter")
end


-- ============================================================
-- pcall discipline: catching handler must re-raise unknown errors
-- ============================================================

print()
print("== pcall re-raise discipline ==")

do  -- A hypothetical handler that wraps in pcall and DOESN'T re-raise
	-- would swallow the halt. Verify the sprint's actual code doesn't
	-- do that: end-to-end halt still propagates all the way to run().
	--
	-- (This exercises the full path: handler raises → run_row → run_frame
	-- → Engine.run → StopLarry.run's xpcall catches. If any intermediate
	-- layer had a pcall that swallowed our sentinel, we'd see complete=1
	-- instead of stopped=1.)
	local e = StopLarry.new()
	e:load("%process.stop")

	local result = e:run()

	assert_eq(result.stopped, 1,
		"halt propagates cleanly through all Lua frames (no swallowing)")
end


-- ============================================================
-- engine.stopped flag is NOT set under the sprint's handler
-- ============================================================

print()
print("== engine.stopped is unused under sprint's model ==")

do  -- The sprint's handler doesn't touch engine.stopped; the halt
	-- signal is entirely exception-based. The field can still exist
	-- on the engine (initialized by production's Engine.new) but is
	-- never flipped to true.
	local e = StopLarry.new()
	e:load("%process.stop")

	e:run()

	assert_eq(e.stopped, false,
		"engine.stopped stays false (sprint's handler doesn't set it)")
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format("  %d passed, %d failed", passed, failed))

if failed > 0 then
	os.exit(1)
end
