--[[
{
  "file":     "tests/caspian/digory/test_regression.lua",
  "test_id":  "TD.7",
  "verifies": "After Digory's hash work, prior fixtures still produce their expected values: Aslan hello_world.caspj, Bree hello_world.casp, Corin puts_hello.casp.",
  "level":    "regression_check"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")
local capture = require("corin.support.capture")

runner.suite("digory / TD.7 regression")

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

runner.test("aslan canonical-tree pipeline still returns payload 'hello'", function()
    engine.caspianj = json.parse(read_file("tests/caspian/fixtures/hello_world.caspj"))
    local result = engine.run()
    assert_.equal(result.payload, "hello", "aslan payload")
end)

runner.test("bree source pipeline still returns payload 'hello'", function()
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/hello_world.casp"))
    local result = engine.run()
    assert_.equal(result.payload, "hello", "bree payload")
end)

runner.test("corin source-to-stdout pipeline still writes 'hello\\n'", function()
    local cap = capture.new()
    engine.std      = cap.sink
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/puts_hello.casp"))
    engine.run()
    assert_.equal(cap.text(), "hello\n", "corin captured buffer")
    engine.std = nil
end)
