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

--[[
{
  "in":   {"got": "any", "expected": "any", "msg": "string?"},
  "note": "Recursive structural equality for Lua tables; primitive equality (==) at leaves. On mismatch raises an error naming the first divergent path in the form `mismatch at [k1][k2]...: expected X, got Y`. String keys are quoted (e.g. [\"foo\"]); numeric keys are bare (e.g. [1]). When msg is provided it prefixes the mismatch line: `<msg>: mismatch at ...`."
}
]]
local function format_key(k)
    if type(k) == "string" then
        return string.format("[%q]", k)
    else
        return "[" .. tostring(k) .. "]"
    end
end

local function format_value(v)
    if type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "table" then
        return "<table>"
    else
        return tostring(v)
    end
end

local function deep_diff(got, expected, path)
    if type(got) ~= "table" or type(expected) ~= "table" then
        if got == expected then return true end
        return false, path, got, expected
    end

    local seen = {}
    for k, v in pairs(expected) do
        seen[k] = true
        local ok, p, g, e = deep_diff(got[k], v, path .. format_key(k))
        if not ok then return false, p, g, e end
    end
    for k, v in pairs(got) do
        if not seen[k] then
            local ok, p, g, e = deep_diff(v, expected[k], path .. format_key(k))
            if not ok then return false, p, g, e end
        end
    end
    return true
end

function M.deep_equal(got, expected, msg)
    local ok, path, g, e = deep_diff(got, expected, "")
    if not ok then
        local where = (path == "") and "<root>" or path
        local line  = string.format("mismatch at %s: expected %s, got %s",
            where, format_value(e), format_value(g))
        if msg then line = msg .. ": " .. line end
        error(line, 2)
    end
end

return M
