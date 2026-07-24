--[[
{
  "file":     "tests/caspian/digory/test_role_transition.lua",
  "test_id":  "TD.5",
  "verifies": "During the hash key-access call, the top frame on the call stack has role 'stdlib' (the hash class's owning role per roles.md). Mirror of Aslan TA.8.",
  "level":    "unit_observability_check"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.5 role_transition")

runner.test("role on top frame is 'stdlib' while hash key access runs", function()
    -- Bootstrap explicitly so we can wrap method_missing before dispatch.
    -- (Don't use engine.run, which re-bootstraps and would wipe the spy.)
    engine.bootstrap()

    local hash_cls = engine.classes["puck.uno/hash"]
    local original = hash_cls.method_missing
    local observed_role_name
    hash_cls.method_missing = function(receiver, name)
        observed_role_name = engine.state.call_stack[#engine.state.call_stack].role.name
        return original(receiver, name)
    end

    local stmt = engine.parse_caspian("{name: 'Picard'}.name")[1]
    engine.dispatch(stmt)

    assert_.equal(observed_role_name, "stdlib", "expected stdlib role mid-dispatch")

    -- Verify frame popped: top is back to user.
    assert_.equal(engine.state.call_stack[#engine.state.call_stack].role.name, "user",
                  "expected user role after dispatch returns")

    -- Restore.
    hash_cls.method_missing = original
end)
