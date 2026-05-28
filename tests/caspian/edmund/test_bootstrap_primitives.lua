--[[
{
  "file":     "tests/caspian/edmund/test_bootstrap_primitives.lua",
  "test_id":  "TE.2",
  "verifies": "After bootstrap, every primitive class is registered with a to_json method, owned by stdlib.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("edmund / TE.2 bootstrap_primitives")

local PRIMITIVE_CLASSES = {
    "puck.uno/string",
    "puck.uno/hash",
    "puck.uno/number",
    "puck.uno/null",
    "puck.uno/true",
    "puck.uno/false",
}

runner.test("every primitive class is registered with to_json and owned by stdlib", function()
    engine.bootstrap()
    for _, name in ipairs(PRIMITIVE_CLASSES) do
        local cls = engine.classes[name]
        assert_.not_nil(cls, name .. " not registered")
        assert_.equal(cls.owning_role, engine.state.roles.stdlib,
                      name .. " owning_role should be stdlib")
        assert_.equal(type(cls.methods.to_json), "function",
                      name .. " is missing to_json")
    end
end)
