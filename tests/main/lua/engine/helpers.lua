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
-- FakeStdout — captures :puts and :write for assertion.
--
-- Same call surface tests use to check what the engine wrote (:puts,
-- :write). The eventual real stdout the CLI wires will respond to
-- the same methods; tests substitute this capturing version.
------------------------------------------------------------

local FakeStdout = {}
FakeStdout.__index = FakeStdout

function FakeStdout.new()
	return setmetatable({buffer = {}}, FakeStdout)
end

function FakeStdout:write(...)
	local args = {...}

	for i = 1, #args do
		table.insert(self.buffer, tostring(args[i]))
	end

	return
end

function FakeStdout:puts(text)
	self:write(tostring(text) .. '\n')
	return
end

function FakeStdout:get_all()
	return table.concat(self.buffer)
end

function FakeStdout:get_lines()
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

function FakeStdout:clear()
	self.buffer = {}
	return
end

M.FakeStdout = FakeStdout

return M
