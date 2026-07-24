--[[
{
  "file":     "tests/caspian/edmund/test_source_baseline.lua",
  "test_id":  "TE.0.1",
  "verifies": "Source pipeline (lex + parse + transpile via engine.parse_caspian) completes for the Edmund fixture. Since Digory already realigned hash literals to the canonical array-of-pairs shape, the transpiler needs no further work for Edmund's fixture; this test pins the baseline.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.0.1 source_baseline")

runner.test("engine.parse_caspian on Edmund fixture completes without error", function()
    local tree = engine.parse_caspian("{name: 'Picard', rank: 'Captain'}.to_json")
    assert_.not_nil(tree, "parse_caspian returned nil")
    assert_.equal(#tree, 1, "expected 1 top-level statement")
end)

runner.test("baseline statement is .to_json on a hash receiver", function()
    local stmt = engine.parse_caspian("{name: 'Picard', rank: 'Captain'}.to_json")[1]
    assert_.equal(stmt[2], "to_json", "method name")
    assert_.not_nil(stmt[1].hash, "receiver is a hash expression")
end)
