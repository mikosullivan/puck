--[[
{
  "file":     "tests/caspian/corin/test_source_baseline.lua",
  "test_id":  "TC.0.1",
  "verifies": "Source pipeline (lex + parse + transpile via engine.parse_caspian) completes for the Corin fixture puts 'hello' without error. The baseline shape today is pre-canonical (with a '&' slot and an {args} wrapper); Phase 1 realigns it to canonical [{bwc:name}, arg]. This test pins the baseline so the realignment is observable.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.0.1 source_baseline")

runner.test("engine.parse_caspian(\"puts 'hello'\") completes without error", function()
    local tree = engine.parse_caspian("puts 'hello'")
    assert_.not_nil(tree, "parse_caspian returned nil")
    assert_.equal(#tree, 1, "expected 1 top-level statement")
end)

runner.test("baseline statement carries the bwc receiver", function()
    local stmt = engine.parse_caspian("puts 'hello'")[1]
    assert_.equal(type(stmt), "table", "statement is not a table")
    assert_.equal(type(stmt[1]), "table", "stmt[1] is not a table")
    assert_.equal(stmt[1].bwc, "puts", "stmt[1].bwc value")
end)
