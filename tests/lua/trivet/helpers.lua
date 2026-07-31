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
