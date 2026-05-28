--[[
{
  "file":     "tests/caspian/edmund/test_round_trip.lua",
  "test_id":  "TE.6",
  "verifies": "Round-trip: parse(encode(x)) deep_equals x. Construct a hash containing every primitive type, serialize via to_json, parse the result, and check the payload structure round-trips.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("edmund / TE.6 round_trip")

runner.test("hash with string + number + null + true + false leaves round-trips", function()
    engine.bootstrap()

    -- Hand-build a hash exercising every primitive.
    local hash_value = engine.materialize({ hash = {
        { "s", { value = "hello" } },
        { "n", { value = 42      } },
        { "z", { value = json.null } },
        { "t", { value = true    } },
        { "f", { value = false   } },
    } })

    -- Serialize.
    local resolver = engine.lookup_method(hash_value, "to_json")
    local serial   = resolver(hash_value).payload

    -- Parse the JSON back and compare with the original Lua-level shape.
    local parsed = json.parse(serial)

    local expected = json.new_hash()
    json.hash_set(expected, "s", "hello")
    json.hash_set(expected, "n", 42)
    json.hash_set(expected, "z", json.null)
    json.hash_set(expected, "t", true)
    json.hash_set(expected, "f", false)

    assert_.deep_equal(parsed, expected, "round-trip structural equality")
end)
