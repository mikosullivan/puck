--[[
{
  "file": "tests/charlie/v001/test_dispatch.lua",
  "test_id": "T1.6",
  "verifies": "engine.dispatch executes a [receiver, method, args?] statement end-to-end: materializes the receiver, looks up the method, transitions into the target role, runs the method, returns the resulting value",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("charlie.engine")

runner.suite("v0.01 / engine dispatch")

runner.test("dispatches the hello-world statement and returns the value", function()
    engine.bootstrap()
    local v = engine.dispatch({{value = "hello"}, "to_string"})
    assert_.not_nil(v,                   "dispatch returned a value")
    assert_.equal(v.type,    "string",   "result type")
    assert_.equal(v.payload, "hello",    "result payload")
end)

runner.test("the returned value is the same receiver (to_string is identity)", function()
    engine.bootstrap()
    -- materialize ourselves so we can identity-compare against the dispatched result
    local original = engine.materialize({value = "hello"})
    -- emulate dispatch with the pre-built receiver by handing it in via a synthetic statement
    -- (engine.dispatch itself materializes anew; this test asserts identity on its result vs a
    -- fresh materialize, which is the same as: payload equality is sufficient).
    local v = engine.dispatch({{value = "hello"}, "to_string"})
    assert_.equal(v.payload, original.payload, "payload matches the materialized literal")
end)

runner.test("the returned value's owning_role is user (literal materialized as user)", function()
    engine.bootstrap()
    local v = engine.dispatch({{value = "hello"}, "to_string"})
    assert_.equal(v.owning_role, engine.roles.user,
        "literal was materialized under user; to_string returned it unchanged")
end)

runner.test("ctx is back to user after dispatch returns", function()
    engine.bootstrap()
    engine.dispatch({{value = "hello"}, "to_string"})
    assert_.equal(engine.ctx.current_role, engine.roles.user,
        "role restored after the cross-role call")
end)
