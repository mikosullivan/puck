--[[
{
  "file":     "tests/caspian/digory/test_transpiler_canonical.lua",
  "test_id":  "TD.1",
  "verifies": "engine.parse_caspian emits canonical hash-literal shape for the Digory fixture: a hash payload as an array-of-pairs, then a method call on it. Deep-equal check.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.1 transpiler_canonical")

runner.test("parse_caspian(\"{name: 'Picard'}.name\") deep-equals canonical tree", function()
    local got = engine.parse_caspian("{name: 'Picard'}.name")
    local expected = {
        {
            { hash = { { "name", { value = "Picard" } } } },
            "name",
        },
    }
    assert_.deep_equal(got, expected, "Digory canonical hash-literal tree")
end)
