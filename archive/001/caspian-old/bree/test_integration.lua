--[[
{
  "file":     "tests/caspian/bree/test_integration.lua",
  "test_id":  "TB.4",
  "verifies": "Full source-side pipeline integration: read fixture, parse_caspian, stage on engine.caspianj, engine.run(), assert payload. This is the Bree end-to-end contract.",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("bree / TB.4 integration")

runner.test("read + parse_caspian + engine.run returns a value with payload 'hello'", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.casp", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = engine.parse_caspian(source)
    local result    = engine.run()

    assert_.not_nil(result, "no value returned")
    assert_.equal(result.payload, "hello", "payload mismatch")
end)
