--[[
{
	"spec": "test_basic",
	"role": "Smoke tests for `engine.new()` — the boot entry point. Confirms the constructor takes no args, returns an instance with no host wiring pre-populated (`stdout`, `debugger` both `nil`), and that assigning to those fields wires them cleanly (single assignment, reassignment, per-instance isolation)."
}
]]

--[[
# `test_basic`

Boot-shape tests for the engine class. Every case here exercises a
single wiring / assignment invariant — the constructor gives you a
bare instance, capabilities attach by plain field assignment, and
two engine instances never share state through class-level
accidents.

The tests use `helpers.FakeOutput` as the host-side stdout so the
`e.stdout = ...` assignments have a concrete object to attach.
]]

local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h = require('helpers')
local engine = require('engine')

h.test('engine.new() takes no args and returns an instance with no wiring', function()
	local e = engine.new()
	h.assert_true(e ~= nil, 'engine instance created')
	h.assert_true(e.stdout == nil, 'no stdout wired at construction')
	h.assert_true(e.debugger == nil, 'no debugger wired at construction')
end)

h.test('engine.stdout = X wires the stdout; engine.stdout reads it back', function()
	local stdout = h.FakeOutput.new()
	local e = engine.new()
	e.stdout = stdout
	h.assert_true(e.stdout == stdout, 'engine.stdout returns the object we assigned')
end)

h.test('engine.stdout can be reassigned', function()
	local s1 = h.FakeOutput.new()
	local s2 = h.FakeOutput.new()
	local e = engine.new()
	e.stdout = s1
	e.stdout = s2
	h.assert_true(e.stdout == s2, 'engine.stdout reflects the last assignment')
end)

h.test('two engines have independent stdout state', function()
	local s1 = h.FakeOutput.new()
	local s2 = h.FakeOutput.new()
	local e1 = engine.new()
	local e2 = engine.new()
	e1.stdout = s1
	e2.stdout = s2
	h.assert_true(e1.stdout == s1, 'e1.stdout is s1')
	h.assert_true(e2.stdout == s2, 'e2.stdout is s2')
end)

h.test('engine:load(source) populates caspm by transpiling + normalizing', function()
	local e = engine.new()
	e:load('$x = 1 + 2')
	h.assert_true(type(e.caspm) == 'table', 'caspm is a Lua table')
	h.assert_true(#e.caspm > 0,             'caspm has at least one statement row')
end)

h.test('engine.debugger = X wires the debugger; engine.debugger reads it back', function()
	local d = {}
	local e = engine.new()
	e.debugger = d
	h.assert_true(e.debugger == d, 'engine.debugger returns the array we assigned')
end)

h.test('engine:load(source) logs a "loaded" entry to the debugger when one is attached', function()
	local e = engine.new()
	e.debugger = {}
	e:load('$x = 1 + 2')
	h.assert_eq(#e.debugger, 1, 'one entry appended')
	h.assert_eq(e.debugger[1].kind, 'loaded', 'entry kind is "loaded"')
	h.assert_eq(e.debugger[1].source_length, 10, 'entry carries source_length')
end)

h.test('engine:load(source) works with no debugger attached', function()
	local e = engine.new()
	e:load('$x = 1 + 2')
	h.assert_true(type(e.caspm) == 'table', 'load succeeded without a debugger being required')
end)

h.test('the debugger can be inspected before AND after running load()', function()
	local e = engine.new()
	e.debugger = {}
	h.assert_eq(#e.debugger, 0, 'debugger empty before load')
	e:load('$x = 1')
	h.assert_eq(#e.debugger, 1, 'debugger has the entry after load')
	e:load('$y = 2')
	h.assert_eq(#e.debugger, 2, 'each subsequent load appends')
end)

h.test('any Lua sequence works as the debugger — no special class required', function()
	-- A plain preseeded sequence should accept engine log entries too.
	local e = engine.new()
	e.debugger = {'not from the engine'}
	e:load('$x = 1')
	h.assert_eq(#e.debugger, 2, 'engine appends to what was already there')
	h.assert_eq(e.debugger[1], 'not from the engine', 'preseeded entry preserved')
	h.assert_eq(e.debugger[2].kind, 'loaded', 'engine entry appended at index 2')
end)
