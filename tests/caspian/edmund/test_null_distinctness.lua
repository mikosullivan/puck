--[[
{
  "file":     "tests/caspian/edmund/test_null_distinctness.lua",
  "test_id":  "TE.9",
  "verifies": "Each null materialization is a distinct value table (per-call instance identity), but the payload is the same canonical null sentinel.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("edmund / TE.9 null_distinctness")

runner.test("two null materializations are distinct tables, same payload sentinel", function()
    engine.bootstrap()
    local m1 = engine.materialize({ value = json.null })
    local m2 = engine.materialize({ value = json.null })

    assert_.not_equal(m1, m2, "two materializations should be distinct tables")
    assert_.equal(m1.payload, m2.payload, "both payloads should be the same singleton sentinel")
    assert_.equal(m1.payload, json.null,  "payload should be caspian.json.null")
end)
