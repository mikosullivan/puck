--[[
{
  "file":     "tests/caspian/aslan/test_transition.lua",
  "test_id":  "TA.5",
  "verifies": "engine.transition pushes a frame, runs fn, returns its result, and pops the frame.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("aslan / transition")

runner.test("pushes a frame and pops it after fn returns", function()
    engine.bootstrap()
    local depth_before = #engine.state.call_stack
    local depth_inside

    engine.transition(
        {
            action = "method_call",
            role   = engine.state.roles.stdlib,
        },
        function()
            depth_inside = #engine.state.call_stack
        end
    )

    local depth_after = #engine.state.call_stack
    assert_.equal(depth_inside, depth_before + 1, "frame was not pushed")
    assert_.equal(depth_after,  depth_before,     "frame was not popped")
end)

runner.test("returns fn's return value", function()
    engine.bootstrap()
    local result = engine.transition(
        { action = "method_call", role = engine.state.roles.stdlib },
        function() return "result-value" end
    )
    assert_.equal(result, "result-value")
end)

runner.test("pushed frame has the requested role", function()
    engine.bootstrap()
    local observed_role
    engine.transition(
        { action = "method_call", role = engine.state.roles.stdlib },
        function()
            observed_role = engine.state.call_stack[#engine.state.call_stack].role
        end
    )
    assert_.equal(observed_role, engine.state.roles.stdlib)
end)

runner.test("pushed frame has fresh chain with log+misc sub-fields", function()
    engine.bootstrap()
    engine.transition(
        { action = "method_call", role = engine.state.roles.stdlib },
        function()
            local frame = engine.state.call_stack[#engine.state.call_stack]
            assert_.not_nil(frame.chain.log,  "pushed frame missing chain.log")
            assert_.not_nil(frame.chain.misc, "pushed frame missing chain.misc")
        end
    )
end)

runner.test("after pop, the surviving frame is the top_level frame", function()
    engine.bootstrap()
    engine.transition(
        { action = "method_call", role = engine.state.roles.stdlib },
        function() end
    )
    assert_.equal(#engine.state.call_stack, 1)
    assert_.equal(engine.state.call_stack[1].role, engine.state.roles.user)
end)
