--[[ {
	"vibecode": {
		"role": "minimal test helpers for the drinian-with-sqlite prototype tests. Mirrors the shape of tests/main/lua/engine/helpers.lua so patterns stay consistent, but lives here because this tree is self-contained per the spec-before-implementation rule."
	}
} ]]

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

return M
