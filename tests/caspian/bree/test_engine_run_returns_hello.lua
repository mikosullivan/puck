--[[
{
  "file":     "tests/caspian/bree/test_engine_run_returns_hello.lua",
  "test_id":  "TB.3",
  "verifies": "Engine.run on the bree source fixture's transpiled tree returns a value whose payload is 'hello'. Verifies engine + transpiler integration end-to-end at the tree level.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local caspian = require("caspian")
local engine  = require("caspian.engine")

runner.suite("bree / TB.3 engine_run_returns_hello")

runner.test("engine.run on transpiled bree fixture returns payload 'hello'", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.casp", "r"))
    local source = f:read("*a")
    f:close()

    local tree   = caspian.transpile(source)
    local result = engine.run(tree)

    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)
