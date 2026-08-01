--[[
{
	"module": "helpers",
	"role": "Test helpers for the Fiona Lua-interface tests. Wires lsqlite3 (per-user luarocks install) and adds the sibling src/ to package.path so tests can require the fiona module. Exposes assert helpers and a test-registration + reporting harness.",
	"exports": {
		"test":          "name, fn -> nil (registers a test)",
		"reset":         "() -> nil (clears results between files)",
		"results":       "{passed, failed, failures} — mutated by test()",
		"assert_eq":     "actual, expected, msg? -> nil (raises on mismatch)",
		"assert_true":   "value, msg? -> nil",
		"assert_raises": "fn, pattern?, label? -> nil"
	}
}
]]

-- Wire the per-user luarocks install so lsqlite3 resolves.
local home = os.getenv("HOME") or "."
package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath
package.path  = home .. "/.luarocks/share/lua/5.4/?.lua;" .. package.path

-- Add the sibling src/ dir to package.path so tests can require("fiona").
local script_dir = arg[0] and arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "../src/?.lua;" .. package.path

local H = {}

--[[ {"in": {"actual": "any", "expected": "any", "msg": "string?"}, "out": "nil"} ]]
function H.assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s",
			msg or "assert_eq", tostring(expected), tostring(actual)), 2)
	end
end

--[[ {"in": {"value": "any", "msg": "string?"}, "out": "nil"} ]]
function H.assert_true(value, msg)
	if not value then
		error((msg or "assert_true") .. ": expected truthy, got " .. tostring(value), 2)
	end
end

--[[ {"in": {"fn": "function", "pattern": "string?", "label": "string?"}, "out": "nil — raises if fn() didn't raise or if pattern didn't match"} ]]
function H.assert_raises(fn, pattern, label)
	local ok, err = pcall(fn)

	if ok then
		error((label or "assert_raises") .. ": expected raise, got success", 2)
	end

	if pattern and not tostring(err):find(pattern, 1, true) then
		error(string.format("%s: raised the wrong error. expected match /%s/, got: %s",
			label or "assert_raises", pattern, tostring(err)), 2)
	end
end

-- ------------------------------------------------------------
-- Test registration + reporting
-- ------------------------------------------------------------

H.results = {passed = 0, failed = 0, failures = {}}

function H.reset()
	H.results.passed = 0
	H.results.failed = 0
	H.results.failures = {}
end

--[[ {"in": {"name": "string", "fn": "function"}, "out": "nil (updates H.results)"} ]]
function H.test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)

	if ok then
		H.results.passed = H.results.passed + 1
	else
		H.results.failed = H.results.failed + 1
		table.insert(H.results.failures, {name = name, err = err})
	end
end

return H
