--[[
{
  "file":     "tests/caspian/digory/test_insertion_order.lua",
  "test_id":  "TD.3",
  "verifies": "Hash literals materialize preserving insertion order. Load-bearing: Puck hashes have significant key order; a hash that reorders is broken regardless of the rest passing.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("digory / TD.3 insertion_order")

runner.test("materialized hash payload preserves insertion order c, a, b", function()
    engine.bootstrap()
    -- Hand-build the canonical hash expression so we exercise materialize directly.
    -- String values only (Digory's scope adds hashes; numeric materialization is later).
    local hash_expr = { hash = {
        { "c", { value = "one"   } },
        { "a", { value = "two"   } },
        { "b", { value = "three" } },
    } }
    local value = engine.materialize(hash_expr)

    assert_.equal(value.type, "puck.uno/hash", "expected puck.uno/hash")

    local keys = json.hash_keys(value.payload)
    assert_.equal(#keys, 3, "expected 3 keys")
    assert_.equal(keys[1], "c", "first key")
    assert_.equal(keys[2], "a", "second key")
    assert_.equal(keys[3], "b", "third key")
end)
