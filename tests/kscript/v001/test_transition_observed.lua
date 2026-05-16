--[[
{
  "file": "tests/kscript/v001/test_transition_observed.lua",
  "test_id": "T1.8",
  "level": "unit_observability_check",
  "verifies": "the role transition actually happened during dispatch — the to_string method, when called, observes ctx.current_role == string_class (not user); load-bearing for the role system: without it, all role machinery could be missing entirely and the rest of the V0.01 tests would still pass",
  "tactic": "replace to_string with a spy that records ctx.current_role at call time, dispatch, then assert on what the spy saw"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("kscript.engine")

runner.suite("v0.01 / engine transition observed during dispatch")

runner.test("inside to_string, current_role is string_class — not user", function()
    engine.bootstrap()
    local seen_role
    local seen_chain
    -- Install a spy that records what the runtime sees at method-call time, then
    -- defers to the identity-return contract so dispatch's normal assertions still hold.
    local original_to_string = engine.classes.string.methods.to_string
    engine.classes.string.methods.to_string = function(receiver, args)
        seen_role  = engine.ctx.current_role
        seen_chain = engine.ctx.chain
        return original_to_string(receiver, args)
    end

    engine.dispatch({{value = "hello"}, "to_string"})

    assert_.equal(seen_role, engine.roles.string_class,
        "method body must execute under the string_class role, not user")
    assert_.not_equal(seen_chain, nil,
        "chain visible inside the method must be a fresh table, not nil")
end)
