--[[
{
  "file":     "tests/caspian/corin/test_dispatch_bwc.lua",
  "test_id":  "TC.3",
  "verifies": "engine.dispatch routes a bwc-shape statement [{bwc:name}, arg] to the registered handler via the role transition. Hand-built tree; checks the sink-buffer side effect.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local capture = require("corin.support.capture")

runner.suite("corin / TC.3 dispatch_bwc")

runner.test("engine.dispatch on a bwc statement writes via engine.std", function()
    engine.bootstrap()

    local cap = capture.new()
    engine.std = cap.sink

    engine.dispatch({ { bwc = "puts" }, { value = "x" } })

    assert_.equal(cap.text(), "x\n", "capture buffer mismatch")

    engine.std = nil
end)
