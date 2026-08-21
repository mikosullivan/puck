--[[
{
	"spec": "test_process_stop",
	"role": "%process.stop end-to-end. Runs `$x = 1\n%process.stop` through the engine and verifies the walker halts in place: run() returns a stopped result (complete=0, stopped=1), engine.stopped is true, frame 0 is still alive under the cap, the cap sits at its born-terminal state, and the `x` binding is still walkable. Also regressions the normal-completion path — a program with no %process.stop still returns complete=1."
}
]]

--[[
# `test_process_stop`

Assertions for the `%process.stop` primitive. The ProcessStop handler flips `engine.stopped`; the walker's per-iteration check exits the dispatch loop before advancing; run() returns a stopped result and run_frame skips the reap.

Program: `$x = 1\n%process.stop`.

- Statement 0 dispatches through the variable-scalar handler → the `x` binding lands via the standard frame-local chain, then advances.
- Statement 1 is `%process.stop` → the ProcessStop handler sets `engine.stopped = true` → the walker breaks BEFORE advancing → run_frame returns without reaping → run() returns `{complete = 0, stopped = 1, cap_pk = ...}`.

Post-halt: frame 0 is still under the cap (walkable via `frame_parent`), the cap sits at its born-terminal state (`frame_stmt_idx = 0, frame_gc = null`), and the `x` binding is still reachable via the ref chain because the frame that owns it never got reaped.
]]

local h      = require('helpers')
local engine = require('engine')


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


local SOURCE = '$x = 1\n%process.stop'


h.test('%process.stop: run() returns a stopped result, not a complete one', function()
	local e = engine.new()
	e:load(SOURCE)
	local result = e:run()

	h.assert_true(type(result) == 'table', 'run() should return a table')
	h.assert_eq(result.complete, 0, 'result.complete should be 0 when %process.stop halted the walker')
	h.assert_eq(result.stopped, 1, 'result.stopped should be 1 when %process.stop halted the walker')
	h.assert_not_nil(result.cap_pk, 'result.cap_pk should be set')
end)

h.test('%process.stop: engine.stopped is true after the halt', function()
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	h.assert_true(e.stopped == true, 'engine.stopped should be true after %process.stop halted the walker')
end)

h.test('%process.stop: frame 0 is still alive at the halt point', function()
	-- Reap was skipped because of the halt. Frame 0 sits under the
	-- cap as its child.
	local e = engine.new()
	e:load(SOURCE)
	local result = e:run()

	local kids = scalar(e.cvm,
		"select count(*) from objects where frame_parent = '" .. result.cap_pk .. "'")
	h.assert_eq(tonumber(kids), 1, 'cap should have frame 0 as its child')
end)

h.test('%process.stop: the `x` binding is walkable at the halt point', function()
	-- $x = 1 dispatched (statement 0), advanced. Then %process.stop
	-- fired (statement 1) and halted. `x` was bound in the first
	-- statement — the ref chain is intact.
	local e = engine.new()
	e:load(SOURCE)
	e:run()

	local binding = first(e.cvm,
		"select s.scalar_type, s.value from scalars s "
		.. "join refs r on r.child = s.object_pk where r.key = 'x'")
	h.assert_not_nil(binding, 'x binding should be walkable via refs')
	h.assert_eq(binding.scalar_type, 'n', 'x should bind to scalar_type=n')
	h.assert_eq(tonumber(binding.value), 1, 'x should bind to value 1')
end)

h.test('%process.stop: the cap sits at its born-terminal state', function()
	local e = engine.new()
	e:load(SOURCE)
	local result = e:run()

	local cap = first(e.cvm,
		"select frame_stmt_idx, frame_gc from objects where object_pk = '" .. result.cap_pk .. "'")
	h.assert_not_nil(cap, 'cap should still exist')
	h.assert_eq(tonumber(cap.frame_stmt_idx), 0, 'cap frame_stmt_idx should be 0')
	h.assert_true(cap.frame_gc == nil, 'cap frame_gc should be null')
end)

h.test('%process.stop regression: a program without %process.stop still returns complete = 1', function()
	local e = engine.new()
	e:load('$x = 1')
	local result = e:run()

	h.assert_eq(result.complete, 1, 'result.complete should be 1 for a normal run')
	h.assert_true(result.stopped == nil, 'result.stopped should be absent on normal completion')
end)
