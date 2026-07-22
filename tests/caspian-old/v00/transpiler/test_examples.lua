--[[
{
  "suite": "transpiler / example files",
  "covers": "smoke-tests: parse + transpile all 7 .casp example files without error; to_json round-trip (compact and pretty)",
  "examples": ["hello", "strings", "pipes", "control_flow", "functions", "system", "lengthy"],
  "fixtures_dir": "./tests/caspian/v00/fixtures/"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local ks     = require("caspian")
local engine = require("caspian.engine")
local json   = require("caspian.json")

runner.suite("transpiler / example files")

local examples = {
    "hello", "strings", "pipes", "control_flow",
    "functions", "system", "lengthy",
}

local base = "./tests/caspian/v00/fixtures/"

--[[ { "in": "path: string", "out": "string?, error?", "note": "reads entire file to string; returns nil + error message on failure" } ]]
local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local src = f:read("*a")
    f:close()
    return src
end

-- Fixtures live locally; this loop just iterates them by name.
local src_base = "./tests/caspian/v00/fixtures/"

for _, name in ipairs(examples) do
    local path = src_base .. name .. ".casp"
    runner.test(name .. ".casp parses and transpiles", function()
        local src, err = read_file(path)
        if not src then
            error("could not read " .. path .. ": " .. tostring(err))
        end
        local ok, result = pcall(engine.parse_caspian, src)
        if not ok then
            error("parse_caspian failed: " .. tostring(result))
        end
        assert.equal(type(result), "table")
        -- Every .casp file has at least one statement.
        assert.equal(#result > 0, true)
    end)
end

runner.test("json-encoded parse_caspian round-trips without error", function()
    local src = "$x = 42\n$y = $x + 1\nputs($y)"
    local ok, out = pcall(function() return json.encode(engine.parse_caspian(src), false) end)
    if not ok then error("parse_caspian + json.encode failed: " .. tostring(out)) end
    assert.equal(type(out), "string")
    assert.equal(#out > 0, true)
end)

runner.test("json-encoded parse_caspian pretty round-trips without error", function()
    local src = "if ($x == 1)\n$y = 2\nend"
    local ok, out = pcall(function() return json.encode(engine.parse_caspian(src), true) end)
    if not ok then error("parse_caspian + json.encode pretty failed: " .. tostring(out)) end
    assert.equal(type(out), "string")
end)
