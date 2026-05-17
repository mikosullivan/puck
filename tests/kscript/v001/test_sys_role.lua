--[[
{
  "file": "tests/kscript/v001/test_sys_role.lua",
  "test_id": "T1.9",
  "verifies": "the %role system method, listed in V0.01's role footprint, is implemented in engine.materialize and reports the current role at the moment of materialization (both at top level and inside a role transition)",
  "level": "unit",
  "context": "added 2026-05-17 to close the V0.01 footprint gap surfaced in the audit; complements T1.8 (which observes the transition via Lua-level ctx.current_role) by observing it via the KScript-side %role surface"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local engine   = require("kscript.engine")

runner.suite("v0.01 / sys-role")

runner.test("materializing {sys: 'role'} returns a role-typed value", function()
    engine.bootstrap()
    local v = engine.materialize({sys = "role"})
    assert_.not_nil(v,                "materialize returned a value")
    assert_.equal(v.type, "role",     "value type is 'role'")
end)

runner.test("at top level, %role payload is the user role", function()
    engine.bootstrap()
    local v = engine.materialize({sys = "role"})
    assert_.equal(v.payload, engine.roles.user,
        "%role payload equals the user role at top level")
end)

runner.test("inside a transition, %role payload is the new role", function()
    engine.bootstrap()
    local seen
    engine.transition(engine.roles.stdlib, function()
        local v = engine.materialize({sys = "role"})
        seen = v.payload
    end)
    assert_.equal(seen, engine.roles.stdlib,
        "%role inside transition observes the transitioned role")
end)

runner.test("after the transition returns, %role payload is back to user", function()
    engine.bootstrap()
    engine.transition(engine.roles.stdlib, function() return nil end)
    local v = engine.materialize({sys = "role"})
    assert_.equal(v.payload, engine.roles.user,
        "%role returns to user after the cross-role call unwinds")
end)

runner.test("the role value's owning_role is the current role at materialization", function()
    engine.bootstrap()
    local v = engine.materialize({sys = "role"})
    assert_.equal(v.owning_role, engine.roles.user,
        "owning_role matches the materialization context, matching the literal-value pattern")
end)

runner.test("materializing an unsupported sys reference raises", function()
    engine.bootstrap()
    assert_.parse_error(function() engine.materialize({sys = "now"}) end,
        "V0.01 should reject sys references other than 'role'")
end)
