--[[
{
  "file":     "tests/caspian/corin/test_bootstrap_registry.lua",
  "test_id":  "TC.2",
  "verifies": "After engine.bootstrap, engine.state.roles.stdout exists and engine.bwcs.puts is registered with the correct owning_role.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.2 bootstrap_registry")

runner.test("bootstrap registers stdout role on engine.state.roles", function()
    engine.bootstrap()
    assert_.not_nil(engine.state.roles.stdout, "engine.state.roles.stdout is nil")
    assert_.equal(engine.state.roles.stdout.name, "stdout", "stdout role name")
end)

runner.test("bootstrap registers puts bwc on engine.bwcs", function()
    engine.bootstrap()
    assert_.not_nil(engine.bwcs, "engine.bwcs is nil")
    assert_.not_nil(engine.bwcs.puts, "engine.bwcs.puts is nil")
    assert_.equal(type(engine.bwcs.puts.fn), "function", "puts.fn is not a function")
    assert_.equal(engine.bwcs.puts.owning_role, engine.state.roles.stdout,
                  "puts.owning_role is not the stdout role")
end)
