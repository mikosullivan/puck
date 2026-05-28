--[[
{
  "file":     "tests/caspian/corin/test_integration.lua",
  "test_id":  "TC.6",
  "verifies": "End-to-end Corin pipeline: read source fixture, parse_caspian, stage on engine.caspianj, set engine.std, engine.run. Captured buffer equals 'hello\\n'.",
  "level":    "integration_end_to_end"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local capture = require("corin.support.capture")

runner.suite("corin / TC.6 integration")

runner.test("read + parse + stage + engine.run produces 'hello\\n' on stdout sink", function()
    local f = assert(io.open("tests/caspian/fixtures/puts_hello.casp", "r"))
    local source = f:read("*a")
    f:close()

    local cap = capture.new()
    engine.std      = cap.sink
    engine.caspianj = engine.parse_caspian(source)

    engine.run()

    assert_.equal(cap.text(), "hello\n", "captured buffer")

    engine.std = nil
end)
