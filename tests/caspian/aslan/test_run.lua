--[[
{
  "file":     "tests/caspian/aslan/test_run.lua",
  "test_id":  "TA.7",
  "verifies": "engine.run on the hello_world fixture returns a value whose payload is 'hello'. End-to-end integration test.",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / engine.run")

runner.test("running the hello_world fixture returns a value with payload hello", function()
    local result = engine.run("tests/caspian/fixtures/hello_world.caspj")
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("after engine.run, the call stack is back to one top_level frame", function()
    engine.run("tests/caspian/fixtures/hello_world.caspj")
    assert_.equal(#engine.state.call_stack, 1)
    assert_.equal(engine.state.call_stack[1].action, "top_level")
end)
