--[[
{
	"module": "helpers",
	"role": "Shared test harness for the Trivet test suite. Exposes the minimal test runner (`test`, `results`, `reset`), assertion helpers (`assert_eq`, `assert_true`, `assert_false`, `assert_nil`, `assert_raises`, `assert_seq`), and Trivet-specific utilities (`dump`, `collect`, `values_of`) for extracting node values from Trivet iterators. Loaded via `require('helpers')` from every `test_*.lua` under `tests/main/lua/trivet/` and driven by that directory's `run.lua`.",
	"exports": {
		"reset":         "() — clears the shared `results` accumulator",
		"test":          "(name, fn) — runs `fn` under `xpcall`; bumps `results.passed` or `results.failed`",
		"assert_eq":     "(actual, expected, msg?) — raises when `actual ~= expected`",
		"assert_true":   "(cond, msg?) — raises when `cond` is falsy",
		"assert_false":  "(cond, msg?) — raises when `cond` is truthy",
		"assert_nil":    "(v, msg?) — raises when `v ~= nil`",
		"assert_raises": "(fn, pattern?, msg?) — raises when `fn` does NOT raise, or when `pattern` isn't a substring of the raised error",
		"assert_seq":    "(actual, expected, msg?) — raises when the two arrays differ in length or in any element",
		"dump":          "(t) -> string — renders a Lua sequence as `{v1, v2, ...}` for error text",
		"collect":       "(iter) -> array — collects every value the iterator yields",
		"values_of":     "(iter) -> array — collects `node.value` for every node the iterator yields; the Trivet-specific counterpart of `collect`"
	}
}
]]

--[[
# `helpers`

Shared test harness for the Trivet test suite. Every `test_*.lua`
file under `tests/main/lua/trivet/` starts with `local h =
require('helpers')` and uses `h.test` to register cases plus the
`h.assert_*` family to check outcomes. The parent `run.lua` in the
same directory calls `h.reset` before each file and reads `h.results`
after to aggregate pass/fail counts.

`values_of` is the Trivet-specific convenience: every Trivet
iterator yields Nodes, and assertions usually care about the Node's
wrapped value, not its identity. `h.assert_seq(h.values_of(iter),
{'a', 'b', 'c'})` is the standard traversal-order check.
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

function M.assert_false(cond, msg)
	if cond then
		error(tostring(msg or 'assert_false') .. ': expected falsy, got ' .. tostring(cond), 2)
	end

	return
end

function M.assert_nil(v, msg)
	if v ~= nil then
		error(tostring(msg or 'assert_nil') .. ': expected nil, got ' .. tostring(v), 2)
	end

	return
end

function M.assert_raises(fn, pattern, msg)
	local ok, err = pcall(fn)

	if ok then
		error(tostring(msg or 'assert_raises') .. ': did not raise', 2)
	end

	if pattern and not tostring(err):find(pattern, 1, true) then
		error(string.format('%s: raised but message %q did not contain %q', tostring(msg or 'assert_raises'), tostring(err), pattern), 2)
	end

	return
end

function M.assert_seq(actual, expected, msg)
	local prefix = tostring(msg or 'assert_seq')

	if #actual ~= #expected then
		error(string.format('%s: length mismatch (actual %d, expected %d): actual=%s expected=%s', prefix, #actual, #expected, M.dump(actual), M.dump(expected)), 2)
	end

	for i = 1, #expected do
		if actual[i] ~= expected[i] then
			error(string.format('%s: element %d mismatch (actual %s, expected %s)', prefix, i, tostring(actual[i]), tostring(expected[i])), 2)
		end
	end

	return
end

function M.dump(t)
	if type(t) ~= 'table' then
		return tostring(t)
	end

	local parts = {}

	for i, v in ipairs(t) do
		parts[i] = tostring(v)
	end

	return '{' .. table.concat(parts, ', ') .. '}'
end

function M.collect(iter)
	local out = {}

	for v in iter do
		table.insert(out, v)
	end

	return out
end

function M.values_of(iter)
	local out = {}

	for node in iter do
		table.insert(out, node.value)
	end

	return out
end

return M
