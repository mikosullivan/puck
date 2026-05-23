--[[
{
  "module": "tests.support.assert",
  "role": "Assertion helpers for unit tests; every function calls error() on failure with a descriptive message",
  "special": {
    "kind":        "checks node.kind — convenience for AST node tests",
    "count":       "checks #t == n — convenience for sequence length tests",
    "parse_error": "asserts that a function raises — used to verify the parser rejects bad input"
  },
  "note": "All functions accept an optional trailing msg string to override the default failure message"
}
]]
local M = {}

--[[ { "in": {"got": "any", "expected": "any", "msg": "string?"}, "note": "strict equality (==)" } ]]
function M.equal(got, expected, msg)
    if got ~= expected then
        error(string.format("%s\n    expected: %s\n    got:      %s",
            msg or "not equal", tostring(expected), tostring(got)), 2)
    end
end

--[[ { "in": {"got": "any", "expected": "any", "msg": "string?"}, "note": "asserts got ~= expected" } ]]
function M.not_equal(got, expected, msg)
    if got == expected then
        error(string.format("%s: expected values to differ, both are %s",
            msg or "expected not equal", tostring(got)), 2)
    end
end

--[[ { "in": {"got": "any", "msg": "string?"}, "note": "asserts got == nil" } ]]
function M.is_nil(got, msg)
    if got ~= nil then
        error(string.format("%s: expected nil, got %s",
            msg or "expected nil", tostring(got)), 2)
    end
end

--[[ { "in": {"got": "any", "msg": "string?"}, "note": "asserts got ~= nil" } ]]
function M.not_nil(got, msg)
    if got == nil then
        error(string.format("%s: expected non-nil value",
            msg or "expected non-nil"), 2)
    end
end

--[[ { "in": {"got": "any", "msg": "string?"}, "note": "asserts got == true (strictly; not just truthy)" } ]]
function M.is_true(got, msg)
    if got ~= true then
        error(string.format("%s: expected true, got %s",
            msg or "expected true", tostring(got)), 2)
    end
end

--[[ { "in": {"got": "any", "msg": "string?"}, "note": "asserts got == false (strictly; not just falsy)" } ]]
function M.is_false(got, msg)
    if got ~= false then
        error(string.format("%s: expected false, got %s",
            msg or "expected false", tostring(got)), 2)
    end
end

--[[ { "in": {"node": "AST node table", "expected": "string", "msg": "string?"}, "note": "checks node is non-nil then checks node.kind == expected" } ]]
function M.kind(node, expected, msg)
    M.not_nil(node, msg or "node is nil")
    M.equal(node.kind, expected, (msg or "node") .. " kind")
end

--[[ { "in": {"t": "table", "n": "number", "msg": "string?"}, "note": "shorthand for assert.equal(#t, n) with a count-specific message" } ]]
function M.count(t, n, msg)
    M.equal(#t, n, (msg or "count") .. string.format(" (expected %d, got %d)", n, #t))
end

--[[ { "in": {"fn": "function", "msg": "string?"}, "note": "asserts that calling fn() raises an error; fails (errors) if fn returns normally" } ]]
function M.parse_error(fn, msg)
    local ok, err = pcall(fn)
    if ok then
        error(string.format("%s: expected a parse error but got none",
            msg or "parse_error"), 2)
    end
end

return M
