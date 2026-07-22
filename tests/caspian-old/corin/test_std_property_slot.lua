--[[
{
  "file":     "tests/caspian/corin/test_std_property_slot.lua",
  "test_id":  "TC.0.2",
  "verifies": "Setting engine.std to a function before running the Bree fixture (which doesn't call puts) does not disturb the result. The property slot exists; Bree-era runs are unaffected.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.0.2 std_property_slot")

runner.test("setting engine.std before running Bree fixture still returns payload hello", function()
    engine.std      = function(_s) end  -- no-op sink
    engine.caspianj = engine.parse_caspian("'hello'.to_string")

    local result = engine.run()
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.payload, "hello")

    engine.std = nil  -- clean up for downstream tests
end)
