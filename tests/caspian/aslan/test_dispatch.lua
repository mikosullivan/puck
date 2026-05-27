--[[
{
  "file":     "tests/caspian/aslan/test_dispatch.lua",
  "test_id":  "TA.6",
  "verifies": "engine.dispatch handles one [receiver, method] statement end-to-end and returns the method's return value.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / dispatch")

runner.test("dispatching a string literal to_string returns a value with payload hello", function()
    engine.bootstrap()
    local result = engine.dispatch({ { value = "hello" }, "to_string" })
    assert_.not_nil(result)
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("dispatch pops the method_call frame on return", function()
    engine.bootstrap()
    local depth_before = #engine.state.call_stack
    engine.dispatch({ { value = "hello" }, "to_string" })
    local depth_after = #engine.state.call_stack
    assert_.equal(depth_after, depth_before,
        "dispatch should leave the call stack unchanged after returning")
end)
