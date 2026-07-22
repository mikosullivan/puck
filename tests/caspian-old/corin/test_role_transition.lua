--[[
{
  "file":     "tests/caspian/corin/test_role_transition.lua",
  "test_id":  "TC.5",
  "verifies": "Mid-dispatch, the top frame on the call stack has role 'stdout' when puts runs. Mirror of Aslan TA.8. Load-bearing: proves the cross-role machinery actually fires for the bwc path.",
  "level":    "unit_observability_check"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("corin / TC.5 role_transition")

runner.test("role on top frame is 'stdout' while puts handler is running", function()
    engine.bootstrap()

    -- Wrap puts to spy on the role at call time.
    local original = engine.bwcs.puts.fn
    local observed_role_name
    engine.bwcs.puts.fn = function(value)
        observed_role_name = engine.state.call_stack[#engine.state.call_stack].role.name
        -- Don't call original (it would need engine.std); spy is enough.
    end

    engine.dispatch({ { bwc = "puts" }, { value = "x" } })

    assert_.equal(observed_role_name, "stdout", "expected stdout role mid-dispatch")

    -- Verify frame popped: top is back to user.
    assert_.equal(engine.state.call_stack[#engine.state.call_stack].role.name, "user",
                  "expected user role after dispatch returns")

    -- Restore.
    engine.bwcs.puts.fn = original
end)

runner.test("bwc_call frame carries bwc field (not receiver_type/method)", function()
    engine.bootstrap()

    local observed_frame
    engine.bwcs.puts.fn = function(_v)
        observed_frame = engine.state.call_stack[#engine.state.call_stack]
    end

    engine.dispatch({ { bwc = "puts" }, { value = "x" } })

    assert_.equal(observed_frame.action, "bwc_call", "frame action")
    assert_.equal(observed_frame.bwc,    "puts",     "frame bwc")
    assert_.is_nil(observed_frame.receiver_type, "bwc_call frame should not have receiver_type")
    assert_.is_nil(observed_frame.method,        "bwc_call frame should not have method")
end)
