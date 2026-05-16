--[[
{
  "file": "tests/kscript/v001/test_bootstrap.lua",
  "test_id": "T1.2",
  "verifies": "engine.bootstrap populates the role registry (user + string_class), the class registry (string with to_string), and the execution context (current_role=user, chain={})",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("kscript.engine")

runner.suite("v0.01 / engine bootstrap")

runner.test("populates the role registry with user and string-class roles", function()
    engine.bootstrap()
    assert_.not_nil(engine.roles,              "engine.roles exists")
    assert_.not_nil(engine.roles.user,         "engine.roles.user exists")
    assert_.not_nil(engine.roles.string_class, "engine.roles.string_class exists")
    assert_.equal(engine.roles.user.name,         "user")
    assert_.equal(engine.roles.string_class.name, "string_class_role")
end)

runner.test("populates the class registry with the string class + to_string", function()
    engine.bootstrap()
    assert_.not_nil(engine.classes,                       "engine.classes exists")
    assert_.not_nil(engine.classes.string,                "engine.classes.string exists")
    assert_.equal(engine.classes.string.name, "string",   "class name")
    assert_.equal(engine.classes.string.owning_role,
                  engine.roles.string_class,
                  "string class is owned by string_class role")
    assert_.equal(type(engine.classes.string.methods.to_string), "function",
                  "to_string is a function")
end)

runner.test("execution context starts in user role with an empty chain", function()
    engine.bootstrap()
    assert_.not_nil(engine.ctx,                       "engine.ctx exists")
    assert_.equal(engine.ctx.current_role, engine.roles.user, "current_role == user")
    assert_.equal(type(engine.ctx.chain), "table",    "chain is a table")
    assert_.equal(next(engine.ctx.chain), nil,        "chain is empty")
end)

runner.test("bootstrap is idempotent (re-running gives fresh state)", function()
    engine.bootstrap()
    engine.ctx.current_role = engine.roles.string_class  -- mutate
    engine.bootstrap()
    assert_.equal(engine.ctx.current_role, engine.roles.user, "current_role reset")
end)
