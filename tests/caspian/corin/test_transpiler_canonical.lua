--[[
{
  "file":     "tests/caspian/corin/test_transpiler_canonical.lua",
  "test_id":  "TC.1",
  "verifies": "engine.parse_caspian emits canonical bwc-call shape for the Corin fixture (outer-array-then-bwc-receiver-then-value-arg). Deep-equal check, parallel to Bree TB.2.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.1 transpiler_canonical")

runner.test("parse_caspian(\"puts 'hello'\") deep-equals canonical bwc-call tree", function()
    local got = engine.parse_caspian("puts 'hello'")
    local expected = {
        { { bwc = "puts" }, { value = "hello" } },
    }
    assert_.deep_equal(got, expected, "puts 'hello' canonical")
end)
