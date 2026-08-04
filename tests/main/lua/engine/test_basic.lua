local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;' .. package.path

local h = require('helpers')
local engine = require('engine')

h.test('engine.new() takes no args and returns an instance with no stdout wired', function()
	local e = engine.new()
	h.assert_true(e ~= nil, 'engine instance created')
	h.assert_true(e.stdout == nil, 'no stdout wired at construction')
end)

h.test('engine.stdout = X wires the stdout; engine.stdout reads it back', function()
	local stdout = h.FakeStdout.new()
	local e = engine.new()
	e.stdout = stdout
	h.assert_true(e.stdout == stdout, 'engine.stdout returns the object we assigned')
end)

h.test('engine.stdout can be reassigned', function()
	local s1 = h.FakeStdout.new()
	local s2 = h.FakeStdout.new()
	local e = engine.new()
	e.stdout = s1
	e.stdout = s2
	h.assert_true(e.stdout == s2, 'engine.stdout reflects the last assignment')
end)

h.test('two engines have independent stdout state', function()
	local s1 = h.FakeStdout.new()
	local s2 = h.FakeStdout.new()
	local e1 = engine.new()
	local e2 = engine.new()
	e1.stdout = s1
	e2.stdout = s2
	h.assert_true(e1.stdout == s1, 'e1.stdout is s1')
	h.assert_true(e2.stdout == s2, 'e2.stdout is s2')
end)

h.test('engine:load(source) accepts a Caspian source string', function()
	local e = engine.new()
	e:load('$x = 1 + 2')
	h.assert_eq(e.source, '$x = 1 + 2', 'source stashed on engine')
end)
