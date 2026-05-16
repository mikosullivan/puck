--[[
{
  "file": "tests/kscript/v001/test_materialize.lua",
  "test_id": "T1.3",
  "verifies": "engine.materialize wraps a {value: <string>} literal with the V0.01 value shape {type, owning_role, payload} and stamps owning_role from the current execution context",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("kscript.engine")

runner.suite("v0.01 / engine materialize")

runner.test("wraps a string literal with type, owning_role=user, payload", function()
    engine.bootstrap()
    local v = engine.materialize({value = "hello"})
    assert_.equal(v.type,        "string",            "type")
    assert_.equal(v.owning_role, engine.roles.user,   "owning_role is current (user)")
    assert_.equal(v.payload,     "hello",             "payload")
end)

runner.test("owning_role reflects the current context, not always user", function()
    engine.bootstrap()
    engine.ctx.current_role = engine.roles.string_class
    local v = engine.materialize({value = "x"})
    assert_.equal(v.owning_role, engine.roles.string_class,
                  "owning_role tracks ctx.current_role at materialization time")
end)

runner.test("raises on non-string literal in V0.01", function()
    engine.bootstrap()
    assert_.parse_error(function() engine.materialize({value = 42}) end,
        "V0.01 should reject number literals")
end)

runner.test("raises on non-literal expression forms", function()
    engine.bootstrap()
    assert_.parse_error(function() engine.materialize({var = "foo"}) end,
        "V0.01 should reject variable references")
end)
