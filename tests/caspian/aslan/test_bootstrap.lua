--[[
{
  "file":     "tests/caspian/aslan/test_bootstrap.lua",
  "test_id":  "TA.2",
  "verifies": "engine.bootstrap populates engine.state (roles + call_stack) and engine.classes correctly.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / bootstrap")

runner.test("populates roles registry with user and stdlib", function()
    engine.bootstrap()
    assert_.not_nil(engine.state.roles.user,   "user role missing")
    assert_.not_nil(engine.state.roles.stdlib, "stdlib role missing")
    assert_.equal(engine.state.roles.user.name,   "user")
    assert_.equal(engine.state.roles.stdlib.name, "stdlib")
end)

runner.test("populates class registry with puck.uno/string", function()
    engine.bootstrap()
    local string_class = engine.classes["puck.uno/string"]
    assert_.not_nil(string_class, "puck.uno/string class missing")
    assert_.equal(string_class.name, "puck.uno/string")
    assert_.equal(string_class.owning_role, engine.state.roles.stdlib)
    assert_.equal(type(string_class.methods.to_string), "function")
end)

runner.test("call_stack has one top_level frame in user role", function()
    engine.bootstrap()
    assert_.equal(#engine.state.call_stack, 1)
    local top = engine.state.call_stack[1]
    assert_.equal(top.action, "top_level")
    assert_.equal(top.role, engine.state.roles.user)
end)

runner.test("top frame's chain has log and misc sub-fields", function()
    engine.bootstrap()
    local top = engine.state.call_stack[1]
    assert_.not_nil(top.chain,      "chain missing")
    assert_.not_nil(top.chain.log,  "chain.log missing")
    assert_.not_nil(top.chain.misc, "chain.misc missing")
end)

runner.test("classes is NOT a field of engine.state", function()
    engine.bootstrap()
    assert_.is_nil(engine.state.classes,
        "classes should live in engine.classes, not engine.state.classes")
end)

runner.test("bootstrap is idempotent — second call resets state", function()
    engine.bootstrap()
    -- Mutate state to detect reset.
    engine.state.call_stack[1].locals.contamination = "should be wiped"
    engine.bootstrap()
    assert_.is_nil(engine.state.call_stack[1].locals.contamination,
        "second bootstrap did not reset locals")
end)
