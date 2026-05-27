--[[
{
  "file":     "tests/caspian/aslan/test_transition_observed.lua",
  "test_id":  "TA.8",
  "verifies": "Load-bearing observability check: the cross-role transition is actually observed during dispatch. A spy on to_string records the active frame's role at call time; it must be stdlib, not user.",
  "level":    "unit (observability check)"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / transition observed")

runner.test("to_string runs in the stdlib role, not user", function()
    engine.bootstrap()

    local observed_role = nil
    local original = engine.classes["puck.uno/string"].methods.to_string

    -- Install a spy that records the current top-frame role on entry.
    engine.classes["puck.uno/string"].methods.to_string = function(receiver)
        observed_role = engine.state.call_stack[#engine.state.call_stack].role
        return original(receiver)
    end

    engine.dispatch({ { value = "hello" }, "to_string" })

    assert_.equal(observed_role, engine.state.roles.stdlib,
        "to_string should see the stdlib role on the top of the stack")
    assert_.not_equal(observed_role, engine.state.roles.user,
        "to_string must not see the user role — the cross-role transition would be missing")
end)
