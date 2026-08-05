--[[
{
	"spec": "execution/test_puts",
	"role": "Walking-skeleton execution tests for the puts bwc. Feeds raw Caspian source into engine:load(source) — which transpiles + normalizes to CaspM under the hood — then engine:run() walks the tree. Asserts observable side effects on a wired FakeStdout, plus specific raise text on the paths that shouldn't succeed. As the engine grows one construct at a time, more test files land in this dir following the same feed-source / run / observe shape."
}
]]

--[[
# puts execution tests

First walking-skeleton tests for the engine's execution path. Each test
feeds a raw Caspian source string into `engine:load(source)`, then calls
`engine:run()` and asserts one of two things:

- **Observable side effects.** A wired FakeStdout captures writes; tests
  match `stdout:get_all()` against the expected byte sequence.
- **Specific raise text.** An unrecognized construct or a missing
  prerequisite (unset stdout, unloaded engine) raises a message that
  names the missing piece; tests match the raise text so the iteration
  loop gets a clear signal about what to build next.

Debugger-hook tests also confirm that dispatch and raise events land in
the wired debugger sequence with the expected shape.
]]

local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h = require('helpers')
local engine = require('engine')

--[[
## Single puts

Smallest end-to-end Caspian execution: source → CaspJ → CaspM → dispatch
→ wired stdout receives the arg's bytes followed by `\n`.
]]

h.test("engine:run() executes a single puts and writes the arg + newline via :print", function()
	local stdout = h.FakeStdout.new()
	local e = engine.new()
	e.stdout = stdout
	e:load("puts 'hello'")
	e:run()
	h.assert_eq(stdout:get_all(), 'hello\n', "stdout received 'hello\\n'")
end)

--[[
## Multi-arg puts

`puts 'a', 'b'` writes a newline after each arg, producing `a\nb\n`.
Confirms the handler iterates and writes per arg — not concatenating
with a separator, not adding one newline at the end.
]]

h.test("engine:run() with multi-arg puts writes newline after each arg", function()
	local stdout = h.FakeStdout.new()
	local e = engine.new()
	e.stdout = stdout
	e:load("puts 'a', 'b'")
	e:run()
	h.assert_eq(stdout:get_all(), 'a\nb\n', "stdout received 'a\\nb\\n'")
end)

--[[
## Run before load

Calling `engine:run()` before `engine:load()` raises a specific error
naming `load()` as the missing prerequisite. Prevents a silent no-op
that would look like a working program.
]]

h.test("engine:run() called before engine:load() raises a specific error", function()
	local e = engine.new()
	h.assert_raises(function() e:run() end, 'engine:run() called before engine:load()',
		'raises with a message that names load() as the missing prerequisite')
end)

--[[
## `puts` with no stdout wired

The `puts` handler consults `engine.stdout` before writing; unset
stdout raises a message naming the missing wiring. Matches the
bootstrap spec's "capability withheld" rule — reaching for an unwired
capability raises rather than silently swallowing.
]]

h.test("engine:run() with no stdout wired raises when a puts fires", function()
	local e = engine.new()
	e:load("puts 'hi'")
	h.assert_raises(function() e:run() end, 'puts: no stdout wired',
		'raises with a message that names the missing stdout wiring')
end)

--[[
## Unrecognized bwc

An unknown bareword-command name raises `unrecognized_bwc: no handler
registered for bareword command '<name>'`. The raise names the specific
missing bwc so the walking-skeleton iteration loop knows exactly which
handler to add next.
]]

h.test("engine:run() on an unknown bwc raises unrecognized_bwc naming the bwc", function()
	local e = engine.new()
	e:load("no_such_bwc")
	h.assert_raises(function() e:run() end, "unrecognized_bwc: no handler registered for bareword command 'no_such_bwc'",
		'raises with unrecognized_bwc + the bwc name')
end)

--[[
## Debugger records dispatch

A successful bwc dispatch appends `{kind = 'bwc', name = '<bwc>'}` to
the wired debugger sequence. Lets a coder trace which handlers actually
fired during execution.
]]

h.test("engine:run() logs a 'bwc' entry to the debugger on dispatch", function()
	local stdout = h.FakeStdout.new()
	local e = engine.new()
	e.stdout = stdout
	e.debugger = {}
	e:load("puts 'x'")
	e:run()
	-- Debugger has: {loaded}, {bwc: puts}
	h.assert_eq(#e.debugger, 2, 'two debugger entries: loaded + bwc puts')
	h.assert_eq(e.debugger[2].kind, 'bwc', 'entry 2 kind is bwc')
	h.assert_eq(e.debugger[2].name, 'puts', 'entry 2 names the bwc')
end)

--[[
## Debugger records raise

A raise from the bwc dispatcher appends `{kind = 'raised', reason =
'unrecognized_bwc', name = '<name>'}` to the debugger BEFORE the error
propagates. The error path still leaves a diagnostic trail.
]]

h.test("engine:run() logs a 'raised' entry to the debugger when an unrecognized_bwc fires", function()
	local e = engine.new()
	e.debugger = {}
	e:load("no_such_bwc")
	pcall(function() e:run() end)
	h.assert_eq(#e.debugger, 2, 'two debugger entries: loaded + raised')
	h.assert_eq(e.debugger[2].kind, 'raised', 'entry 2 records a raise')
	h.assert_eq(e.debugger[2].reason, 'unrecognized_bwc', 'entry 2 reason is unrecognized_bwc')
	h.assert_eq(e.debugger[2].name, 'no_such_bwc', 'entry 2 names the missing bwc')
end)
