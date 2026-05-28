--[[
{
  "file":     "tests/caspian/edmund/test_regression.lua",
  "test_id":  "TE.8",
  "verifies": "After Edmund's work, prior fixtures still produce their expected outputs: Aslan hello_world.caspj, Bree hello_world.casp, Corin puts_hello.casp, Digory picard_hash.casp.",
  "level":    "regression_check"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")
local capture = require("corin.support.capture")

runner.suite("edmund / TE.8 regression")

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

runner.test("aslan canonical-tree pipeline still returns payload 'hello'", function()
    engine.caspianj = json.parse(read_file("tests/caspian/fixtures/hello_world.caspj"))
    assert_.equal(engine.run().payload, "hello")
end)

runner.test("bree source pipeline still returns payload 'hello'", function()
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/hello_world.casp"))
    assert_.equal(engine.run().payload, "hello")
end)

runner.test("corin source-to-stdout still writes 'hello\\n'", function()
    local cap = capture.new()
    engine.std      = cap.sink
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/puts_hello.casp"))
    engine.run()
    assert_.equal(cap.text(), "hello\n")
    engine.std = nil
end)

runner.test("digory hash key access still returns 'Picard'", function()
    engine.caspianj = engine.parse_caspian(read_file("tests/caspian/fixtures/picard_hash.casp"))
    assert_.equal(engine.run().payload, "Picard")
end)
