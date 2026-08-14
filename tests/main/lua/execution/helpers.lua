--[[
{
	"module": "helpers",
	"role": "Shared test harness for the execution test suite. Same minimal runner (`test`, `results`, `reset`) and `FakeOutput` as the engine helpers, with a smaller assertion set — the execution tests currently only lean on `assert_eq`, `assert_true`, and `assert_raises`. Loaded via `require('helpers')` from every `test_*.lua` under `tests/main/lua/execution/` and driven by that directory's `run.lua`.",
	"exports": {
		"reset":         "() — clears the shared `results` accumulator",
		"test":          "(name, fn) — runs `fn` under `xpcall`; bumps `results.passed` or `results.failed`",
		"assert_eq":     "(actual, expected, msg?) — raises when `actual ~= expected`",
		"assert_true":   "(cond, msg?) — raises when `cond` is falsy",
		"assert_raises": "(fn, pattern?, msg?) — raises when `fn` does NOT raise, or when `pattern` isn't a substring of the raised error",
		"FakeOutput":    "class — `.new()` returns an instance supporting `:print` / `:write` / `:puts` / `:get_all` / `:get_lines` / `:clear`"
	}
}
]]

--[[
# `helpers`

Shared test harness for the execution test suite. Every `test_*.lua`
file under `tests/main/lua/execution/` starts with `local h =
require('helpers')` and uses `h.test` to register cases plus the
`h.assert_*` family to check outcomes. The parent `run.lua` in the
same directory calls `h.reset` before each file and reads `h.results`
after to aggregate pass/fail counts.

`FakeOutput` satisfies the host-side stdout contract the engine
expects: a table with `:print(bytes)` — the raw byte-writer, no
newline. Tests wire it in place of the CLI's real stdout so
assertions can look at what the engine actually wrote.
]]

local M = {}

M.results = {passed = 0, failed = 0, failures = {}}

function M.reset()
	M.results = {passed = 0, failed = 0, failures = {}}
	return
end

function M.test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)

	if ok then
		M.results.passed = M.results.passed + 1
	else
		M.results.failed = M.results.failed + 1
		table.insert(M.results.failures, {name = name, err = err})
	end

	return
end

function M.assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format('%s: expected %s, got %s', tostring(msg or 'assert_eq'), tostring(expected), tostring(actual)), 2)
	end

	return
end

function M.assert_true(cond, msg)
	if not cond then
		error(tostring(msg or 'assert_true') .. ': expected truthy, got ' .. tostring(cond), 2)
	end

	return
end

function M.assert_raises(fn, pattern, msg)
	local ok, err = pcall(fn)

	if ok then
		error(tostring(msg or 'assert_raises') .. ': expected raise, got success', 2)
	end

	if pattern and not tostring(err):find(pattern, 1, true) then
		error(string.format('%s: raised the wrong error. expected match /%s/, got: %s', tostring(msg or 'assert_raises'), pattern, tostring(err)), 2)
	end

	return
end

------------------------------------------------------------
-- FakeOutput — captures :print (host-contract primitive), and
-- keeps legacy :puts / :write for older assertions.
--
-- The host-facing shape agreed with the bootstrap spec is a table
-- with a :print(bytes) method — raw byte-writer, no newline. The
-- engine layers Caspian's puts / print semantics on top. Tests
-- wire this FakeOutput; the eventual CLI wires an object over
-- io.stdout with the same shape.
------------------------------------------------------------

local FakeOutput = {}
FakeOutput.__index = FakeOutput

function FakeOutput.new()
	return setmetatable({buffer = {}}, FakeOutput)
end

function FakeOutput:print(text)
	table.insert(self.buffer, tostring(text))
	return
end

function FakeOutput:write(...)
	local args = {...}

	for i = 1, #args do
		table.insert(self.buffer, tostring(args[i]))
	end

	return
end

function FakeOutput:puts(text)
	self:write(tostring(text) .. '\n')
	return
end

function FakeOutput:get_all()
	return table.concat(self.buffer)
end

function FakeOutput:get_lines()
	local text = self:get_all()

	if text == '' then
		return {}
	end

	local lines = {}

	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		table.insert(lines, line)
	end

	if lines[#lines] == '' and text:sub(-1) == '\n' then
		table.remove(lines)
	end

	return lines
end

function FakeOutput:clear()
	self.buffer = {}
	return
end

M.FakeOutput = FakeOutput

return M
