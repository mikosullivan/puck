--[[
{
  "file":     "tests/caspian/aslan/test_materialize.lua",
  "test_id":  "TA.3",
  "verifies": "engine.materialize wraps a string literal with the correct type, owning_role, and payload.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / materialize")

runner.test("wraps a string literal with puck.uno/string type", function()
    engine.bootstrap()
    local v = engine.materialize({ value = "hello" })
    assert_.not_nil(v)
    assert_.equal(v.type,        "puck.uno/string")
    assert_.equal(v.payload,     "hello")
    assert_.equal(v.owning_role, engine.state.roles.user)
end)

runner.test("owning_role tracks the current top-frame role", function()
    engine.bootstrap()
    -- Manually push a frame in the stdlib role to verify the rule.
    table.insert(engine.state.call_stack, {
        action = "method_call",
        role   = engine.state.roles.stdlib,
        chain  = { log = {}, misc = {} },
        locals = {},
    })
    local v = engine.materialize({ value = "world" })
    assert_.equal(v.owning_role, engine.state.roles.stdlib)
    table.remove(engine.state.call_stack)
end)

runner.test("raises on an unsupported literal type", function()
    engine.bootstrap()
    -- Numbers / null / true / false are now supported (Edmund). Test with
    -- a Lua type that isn't supported as a literal — function, for example.
    local ok = pcall(function()
        engine.materialize({ value = function() end })
    end)
    assert_.is_false(ok, "materialize should raise on a function payload")
end)

runner.test("raises on an unsupported expression form", function()
    engine.bootstrap()
    local ok = pcall(function()
        engine.materialize({ var = "foo" })
    end)
    assert_.is_false(ok, "materialize should raise on {var:...} expression")
end)
