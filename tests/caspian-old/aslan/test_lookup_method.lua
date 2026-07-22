--[[
{
  "file":     "tests/caspian/aslan/test_lookup_method.lua",
  "test_id":  "TA.4",
  "verifies": "engine.lookup_method finds to_string on the puck.uno/string class.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / lookup_method")

runner.test("finds to_string on a string value's class", function()
    engine.bootstrap()
    local v  = engine.materialize({ value = "hello" })
    local fn = engine.lookup_method(v, "to_string")
    assert_.equal(type(fn), "function")
end)

runner.test("to_string returns the receiver unchanged", function()
    engine.bootstrap()
    local v  = engine.materialize({ value = "hello" })
    local fn = engine.lookup_method(v, "to_string")
    local result = fn(v)
    assert_.equal(result, v, "to_string should be identity on a string value")
end)

runner.test("raises on a missing class", function()
    engine.bootstrap()
    local bogus = { type = "no.such/class", payload = "x" }
    local ok = pcall(function() engine.lookup_method(bogus, "to_string") end)
    assert_.is_false(ok, "lookup should raise on an unregistered class")
end)

runner.test("raises on a missing method", function()
    engine.bootstrap()
    local v = engine.materialize({ value = "hello" })
    local ok = pcall(function() engine.lookup_method(v, "no_such_method") end)
    assert_.is_false(ok, "lookup should raise on an unknown method")
end)
