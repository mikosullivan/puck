--[[
{
  "file":     "tests/caspian/edmund/test_to_json_string.lua",
  "test_id":  "TE.4",
  "verifies": "to_json on a string value returns a JSON-quoted string. Hand-built value to isolate the method-level behavior.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.4 to_json_string")

runner.test("to_json on a string value returns the JSON-quoted form", function()
    engine.bootstrap()
    local value = {
        type        = "puck.uno/string",
        owning_role = engine.state.roles.stdlib,
        payload     = "hi",
    }
    local resolver = engine.lookup_method(value, "to_json")
    local result   = resolver(value)

    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, '"hi"')
end)
