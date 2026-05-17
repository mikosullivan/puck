--[[
{
  "file": "tests/kscript/v001/test_transition.lua",
  "test_id": "T1.5",
  "verifies": "engine.transition sets current_role and a fresh chain for the duration of fn(), then restores both; returns fn's return value; nests via Lua's call stack",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("kscript.engine")

runner.suite("v0.01 / engine transition")

runner.test("sees the new role inside fn", function()
    engine.bootstrap()
    local observed = engine.transition(engine.roles.stdlib, function()
        return engine.ctx.current_role
    end)
    assert_.equal(observed, engine.roles.stdlib, "fn sees the new role")
end)

runner.test("restores the prior role after fn returns", function()
    engine.bootstrap()
    engine.transition(engine.roles.stdlib, function() return nil end)
    assert_.equal(engine.ctx.current_role, engine.roles.user, "role restored")
end)

runner.test("wipes the chain inside fn and restores the original on return", function()
    engine.bootstrap()
    local original_chain = engine.ctx.chain
    original_chain["caller_key"] = "caller_value"  -- mutate before transition
    local inner_chain
    engine.transition(engine.roles.stdlib, function()
        inner_chain = engine.ctx.chain
        engine.ctx.chain["inner_key"] = "inner_value"
    end)
    assert_.not_equal(inner_chain, original_chain, "chain inside is a fresh table")
    assert_.equal(engine.ctx.chain, original_chain, "outer chain restored by reference")
    assert_.equal(engine.ctx.chain.caller_key, "caller_value", "outer chain content intact")
    assert_.is_nil(engine.ctx.chain.inner_key, "inner writes did not leak into outer chain")
end)

runner.test("returns fn's return value to the caller", function()
    engine.bootstrap()
    local r = engine.transition(engine.roles.stdlib, function() return 42 end)
    assert_.equal(r, 42)
end)

runner.test("nests cleanly via Lua's call stack", function()
    engine.bootstrap()
    local depth_role
    engine.transition(engine.roles.stdlib, function()
        engine.transition(engine.roles.user, function()
            depth_role = engine.ctx.current_role
        end)
    end)
    assert_.equal(depth_role, engine.roles.user, "innermost role observed")
    assert_.equal(engine.ctx.current_role, engine.roles.user, "fully unwound to user")
end)
