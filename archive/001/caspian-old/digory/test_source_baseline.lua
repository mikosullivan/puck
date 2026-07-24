--[[
{
  "file":     "tests/caspian/digory/test_source_baseline.lua",
  "test_id":  "TD.0.1",
  "verifies": "Source pipeline (tokenize + parse + transpile via engine.parse_caspian) completes for the Digory fixture string. The baseline shape today emits the unordered-object hash form; Phase 1 realigns it to the canonical array-of-pairs form. This test pins the baseline so the realignment is observable.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.0.1 source_baseline")

runner.test("engine.parse_caspian(\"{name: 'Picard'}.name\") completes without error", function()
    local tree = engine.parse_caspian("{name: 'Picard'}.name")
    assert_.not_nil(tree, "parse_caspian returned nil")
    assert_.equal(#tree, 1, "expected 1 top-level statement")
end)

runner.test("baseline statement is a method call on a hash receiver", function()
    local stmt = engine.parse_caspian("{name: 'Picard'}.name")[1]
    assert_.equal(type(stmt),     "table",  "statement is not a table")
    assert_.equal(stmt[2],        "name",   "method name")
    assert_.equal(type(stmt[1]),  "table",  "receiver is not a table")
    assert_.not_nil(stmt[1].hash, "receiver should be a hash expression")
end)
