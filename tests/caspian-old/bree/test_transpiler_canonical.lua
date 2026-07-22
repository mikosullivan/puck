--[[
{
  "file":     "tests/caspian/bree/test_transpiler_canonical.lua",
  "test_id":  "TB.2",
  "verifies": "Transpiler output for the bree source fixture deep-equals the Aslan hand-written CaspianJ tree. Load-bearing round-trip equivalence check: proves source-text and JSON paths converge on the same runtime tree.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("bree / TB.2 transpiler_canonical")

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

runner.test("parse_caspian('hello'.to_string) deep-equals Aslan hand-written canonical tree", function()
    local source = read_file("tests/caspian/fixtures/hello_world.casp")
    local got    = engine.parse_caspian(source)

    local aslan_json = read_file("tests/caspian/fixtures/hello_world.caspj")
    local expected   = json.parse(aslan_json)

    assert_.deep_equal(got, expected, "bree transpiler vs aslan fixture")
end)
