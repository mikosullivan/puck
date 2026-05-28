--[[
{
  "file":     "tests/caspian/bree/test_call_stack_role.lua",
  "test_id":  "TB.5",
  "verifies": "After the Bree pipeline returns, the top frame on engine.state.call_stack has role 'user'. Mirror of Aslan TA.7's second assertion — confirms transitions push and pop cleanly across the source-side path.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("bree / TB.5 call_stack_role")

runner.test("top call_stack frame's role is 'user' after Bree pipeline returns", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.casp", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = engine.parse_caspian(source)
    engine.run()

    local cs = engine.state.call_stack
    assert_.equal(#cs, 1, "expected exactly one frame (the top_level frame)")

    local top = cs[1]
    assert_.equal(top.action, "top_level", "top frame action")
    assert_.not_nil(top.role, "top frame role is nil")
    assert_.equal(top.role.name, "user", "top frame role name")
end)
