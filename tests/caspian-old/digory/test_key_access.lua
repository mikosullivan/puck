--[[
{
  "file":     "tests/caspian/digory/test_key_access.lua",
  "test_id":  "TD.4",
  "verifies": "Key access on a hash returns the expected value via method_missing fallback. Hand-built canonical hash value, dispatch through engine.lookup_method, assert payload.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.4 key_access")

runner.test("lookup_method falls through to method_missing for hash key access", function()
    engine.bootstrap()

    -- Hand-build the value: a hash whose payload contains a materialized string.
    local string_value = {
        type        = "puck.uno/string",
        owning_role = engine.state.roles.stdlib,
        payload     = "Picard",
    }
    local hash_value = engine.materialize({
        hash = { { "name", { value = "Picard" } } },
    })

    local resolver = engine.lookup_method(hash_value, "name")
    local result   = resolver(hash_value)

    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "Picard")
end)

runner.test("method_missing raises for an unknown key", function()
    engine.bootstrap()
    local hash_value = engine.materialize({
        hash = { { "name", { value = "Picard" } } },
    })

    local resolver = engine.lookup_method(hash_value, "rank")
    assert_.parse_error(function() resolver(hash_value) end,
                        "expected no-such-key error")
end)
