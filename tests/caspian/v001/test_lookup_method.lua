--[[
{
  "file": "tests/caspian/v001/test_lookup_method.lua",
  "test_id": "T1.4",
  "verifies": "engine.lookup_method walks value.type → classes[type] → class.methods[name] and returns the Lua function; raises a clear error when the class or method is missing",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("caspian.engine")

runner.suite("v0.01 / engine lookup_method")

runner.test("finds to_string on a string value", function()
    engine.bootstrap()
    local v = engine.materialize({value = "hello"})
    local fn = engine.lookup_method(v, "to_string")
    assert_.equal(type(fn), "function", "returns a function")
    assert_.equal(fn, engine.classes.string.methods.to_string,
                  "returns the same function registered on the class")
end)

runner.test("raises when the class is unknown", function()
    engine.bootstrap()
    local fake = {type = "nonesuch", owning_role = engine.roles.user, payload = nil}
    assert_.parse_error(function() engine.lookup_method(fake, "to_string") end,
        "should raise for unknown class")
end)

runner.test("raises when the method is unknown on a known class", function()
    engine.bootstrap()
    local v = engine.materialize({value = "hello"})
    assert_.parse_error(function() engine.lookup_method(v, "no_such_method") end,
        "should raise for unknown method")
end)
