--[[
{
  "file":     "tests/caspian/edmund/test_materialize_primitives.lua",
  "test_id":  "TE.3",
  "verifies": "engine.materialize produces correct {type, payload} pairs for each new literal type: number, null, true, false. Strings already covered by Aslan tests.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("edmund / TE.3 materialize_primitives")

runner.test("materialize a number literal", function()
    engine.bootstrap()
    local v = engine.materialize({ value = 42 })
    assert_.equal(v.type,    "puck.uno/number")
    assert_.equal(v.payload, 42)
end)

runner.test("materialize a JSON null literal", function()
    engine.bootstrap()
    local v = engine.materialize({ value = json.null })
    assert_.equal(v.type,    "puck.uno/null")
    assert_.equal(v.payload, json.null, "payload should be the canonical null sentinel")
end)

runner.test("materialize a true literal", function()
    engine.bootstrap()
    local v = engine.materialize({ value = true })
    assert_.equal(v.type,    "puck.uno/true")
    assert_.equal(v.payload, true)
end)

runner.test("materialize a false literal", function()
    engine.bootstrap()
    local v = engine.materialize({ value = false })
    assert_.equal(v.type,    "puck.uno/false")
    assert_.equal(v.payload, false)
end)
