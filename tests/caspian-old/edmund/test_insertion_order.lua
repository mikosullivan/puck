--[[
{
  "file":     "tests/caspian/edmund/test_insertion_order.lua",
  "test_id":  "TE.5",
  "verifies": "to_json on a hash preserves insertion order. Load-bearing — significant key order is a Puck-hash invariant, and JSON serialization must respect it.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.5 insertion_order")

runner.test("to_json on {c:1, a:2} returns {\"c\":1,\"a\":2} (insertion order, not alphabetical)", function()
    engine.bootstrap()

    -- Hand-build the canonical hash expression and materialize it.
    local hash_value = engine.materialize({ hash = {
        { "c", { value = 1 } },
        { "a", { value = 2 } },
    } })

    local resolver = engine.lookup_method(hash_value, "to_json")
    local result   = resolver(hash_value)

    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, '{"c":1,"a":2}')
end)
