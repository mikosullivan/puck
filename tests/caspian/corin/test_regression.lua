--[[
{
  "file":     "tests/caspian/corin/test_regression.lua",
  "test_id":  "TC.7",
  "verifies": "After Corin's transpiler + engine changes, the Aslan canonical-tree pipeline and Bree source pipeline still produce a value with payload 'hello'. Independent regression at the Corin boundary.",
  "level":    "regression_check"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("corin / TC.7 regression")

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

runner.test("aslan canonical-tree pipeline still returns payload 'hello'", function()
    engine.caspianj = json.parse(read_file("tests/caspian/fixtures/hello_world.caspj"))
    local result = engine.run()
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.payload, "hello", "aslan payload")
end)

runner.test("bree source pipeline still returns payload 'hello'", function()
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/hello_world.casp"))
    local result = engine.run()
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.payload, "hello", "bree payload")
end)
