--[[
{
  "file":     "tests/caspian/corin/test_engine_std_writes.lua",
  "test_id":  "TC.4",
  "verifies": "engine.std accepts a function; puts handler writes through it during engine.run() on a hand-built tree.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local capture = require("corin.support.capture")

runner.suite("corin / TC.4 engine_std_writes")

runner.test("engine.std accepted; puts writes through it on engine.run", function()
    local cap = capture.new()
    engine.std      = cap.sink
    engine.caspianj = { { { bwc = "puts" }, { value = "hi" } } }

    engine.run()

    assert_.equal(cap.text(), "hi\n", "capture buffer mismatch")

    engine.std = nil
end)
