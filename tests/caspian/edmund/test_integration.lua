--[[
{
  "file":     "tests/caspian/edmund/test_integration.lua",
  "test_id":  "TE.7",
  "verifies": "End-to-end Edmund pipeline: read source fixture, parse_caspian, stage on engine.caspianj, engine.run. Result has the canonical JSON payload.",
  "level":    "integration_end_to_end"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.7 integration")

runner.test("read + parse + stage + engine.run returns the canonical JSON payload", function()
    local f = assert(io.open("tests/caspian/fixtures/picard_to_json.casp", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = engine.parse_caspian(source)
    local result    = engine.run()

    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, '{"name":"Picard","rank":"Captain"}')
end)
