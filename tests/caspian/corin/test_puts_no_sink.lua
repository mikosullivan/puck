--[[
{
  "file":     "tests/caspian/corin/test_puts_no_sink.lua",
  "test_id":  "TC.8",
  "verifies": "puts raises a clear error when engine.std is nil (no silent default to io.stdout). Stdout is a capability, not ambient — per bootstrap.md.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.8 puts_no_sink")

runner.test("engine.run on a puts statement raises when engine.std is nil", function()
    engine.std      = nil
    engine.caspianj = { { { bwc = "puts" }, { value = "hello" } } }

    local ok, err = pcall(function() engine.run() end)
    assert_.is_false(ok, "expected engine.run to raise when engine.std is nil")
    -- Spot-check that the message mentions engine.std so debugging is easy.
    assert_.not_nil(err, "no error message captured")
    assert_.is_true(tostring(err):find("engine%.std") ~= nil,
                    "error message should mention engine.std; got: " .. tostring(err))
end)
