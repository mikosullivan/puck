--[[
{
  "file":     "tests/caspian/edmund/test_transpiler_canonical.lua",
  "test_id":  "TE.1",
  "verifies": "engine.parse_caspian for the Edmund fixture deep-equals the canonical .to_json-on-hash tree (built on Digory's array-of-pairs hash shape).",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.1 transpiler_canonical")

runner.test("parse_caspian Edmund fixture deep-equals canonical tree", function()
    local got = engine.parse_caspian("{name: 'Picard', rank: 'Captain'}.to_json")
    local expected = {
        {
            { hash = {
                { "name", { value = "Picard"  } },
                { "rank", { value = "Captain" } },
            } },
            "to_json",
        },
    }
    assert_.deep_equal(got, expected, "Edmund canonical tree")
end)
