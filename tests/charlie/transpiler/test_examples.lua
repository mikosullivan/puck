--[[
{
  "suite": "transpiler / example files",
  "covers": "smoke-tests: parse + transpile all 7 .charlie example files without error; to_json round-trip (compact and pretty)",
  "examples": ["hello", "strings", "pipes", "control_flow", "functions", "system", "lengthy"],
  "source_dir": "../documentation/vscode/syntax/examples/"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local ks     = require("charlie")

runner.suite("transpiler / example files")

local examples = {
    "hello", "strings", "pipes", "control_flow",
    "functions", "system", "lengthy",
}

local base = "./tests/charlie/fixtures/"

--[[ { "in": "path: string", "out": "string?, error?", "note": "reads entire file to string; returns nil + error message on failure" } ]]
local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local src = f:read("*a")
    f:close()
    return src
end

-- Copy example files to a local path the test can read from.
-- The originals live in documentation/vscode/syntax/examples/.
local src_base = "./tests/charlie/fixtures/"

for _, name in ipairs(examples) do
    local path = src_base .. name .. ".charlie"
    runner.test(name .. ".charlie parses and transpiles", function()
        local src, err = read_file(path)
        if not src then
            error("could not read " .. path .. ": " .. tostring(err))
        end
        local ok, result = pcall(ks.transpile, src)
        if not ok then
            error("transpile failed: " .. tostring(result))
        end
        assert.equal(type(result), "table")
        -- Every .charlie file has at least one statement.
        assert.equal(#result > 0, true)
    end)
end

runner.test("to_json round-trips without error", function()
    local src = "$x = 42\n$y = $x + 1\nputs($y)"
    local ok, out = pcall(ks.to_json, src, false)
    if not ok then error("to_json failed: " .. tostring(out)) end
    assert.equal(type(out), "string")
    assert.equal(#out > 0, true)
end)

runner.test("to_json pretty round-trips without error", function()
    local src = "if ($x == 1)\n$y = 2\nend"
    local ok, out = pcall(ks.to_json, src, true)
    if not ok then error("to_json pretty failed: " .. tostring(out)) end
    assert.equal(type(out), "string")
end)
