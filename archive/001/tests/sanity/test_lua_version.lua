--[[
{
  "file": "tests/sanity/test_lua_version.lua",
  "test_id": "T0.1",
  "verifies": "Lua 5.4 is the interpreter running the suite. Phase 0 acceptance: the engine is Lua-5.4-specific (uses bitwise operators, integer division, etc.); earlier versions will silently miscompile or misbehave.",
  "level": "unit",
  "context": "framework-wrapped version of the dev plan's manual `lua -v` step; covered automatically by the test suite"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")

runner.suite("sanity / lua version")

runner.test("running under Lua 5.4", function()
    assert_.equal(_VERSION, "Lua 5.4",
        "engine assumes Lua 5.4 features; suite must run under Lua 5.4")
end)
