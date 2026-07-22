--[[
{
  "file":     "tests/caspian/digory/test_integration.lua",
  "test_id":  "TD.6",
  "verifies": "End-to-end Digory pipeline: read source fixture, parse_caspian, stage on engine.caspianj, engine.run. Result has payload 'Picard'.",
  "level":    "integration_end_to_end"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.6 integration")

runner.test("read + parse + stage + engine.run returns payload 'Picard'", function()
    local f = assert(io.open("tests/caspian/fixtures/picard_hash.casp", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = engine.parse_caspian(source)
    local result    = engine.run()

    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "Picard")
end)
