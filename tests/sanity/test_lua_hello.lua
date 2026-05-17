--[[
{
  "file": "tests/sanity/test_lua_hello.lua",
  "test_id": "T0.2",
  "verifies": "tests/sanity/lua_hello.lua exists as a pre-framework smoke-test fixture. The plan calls for a standalone script that proves Lua can run and print; this test confirms the file is present with the expected single-line contents.",
  "level": "unit",
  "context": "the standalone script itself (lua_hello.lua) is run manually with `lua tests/sanity/lua_hello.lua`; this framework test only verifies the fixture exists and is correctly formed so the manual check is reproducible"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")

runner.suite("sanity / lua hello fixture")

runner.test("tests/sanity/lua_hello.lua exists and contains the expected print call", function()
    local f = io.open("tests/sanity/lua_hello.lua", "r")
    assert_.not_nil(f, "lua_hello.lua must exist")
    local content = f:read("*a")
    f:close()
    assert_.not_nil(content:find('print%("hello from lua"%)', 1, false),
        "lua_hello.lua must contain the canonical print call")
end)
