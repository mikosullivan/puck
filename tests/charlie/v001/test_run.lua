--[[
{
  "file": "tests/charlie/v001/test_run.lua",
  "test_id": "T1.7",
  "level": "integration_end_to_end",
  "verifies": "engine.run reads tests/charlie/fixtures/hello_world.ksj, parses the canonical CharlieJSON, dispatches the single statement, and returns a value whose payload == 'hello' to the host"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("charlie.engine")

runner.suite("v0.01 / engine run (end-to-end)")

runner.test("hello-world fixture returns a string value with payload 'hello'", function()
    local v = engine.run("tests/charlie/fixtures/hello_world.ksj")
    assert_.not_nil(v,                            "run returned a value")
    assert_.equal(v.type,        "string",        "result type")
    assert_.equal(v.payload,     "hello",         "result payload")
    assert_.equal(v.owning_role, engine.roles.user,
        "literal materialized under user, returned by identity to_string")
end)

runner.test("bootstrap state is in place after run completes", function()
    engine.run("tests/charlie/fixtures/hello_world.ksj")
    assert_.equal(engine.ctx.current_role, engine.roles.user,
        "ctx restored to user after the cross-role call")
end)
