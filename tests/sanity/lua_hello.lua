-- T0.2: Pre-framework sanity check — proves Lua itself runs and can print.
-- Run standalone: `lua tests/sanity/lua_hello.lua`
-- Expected stdout: "hello from lua\n"; exit code 0.
-- Not required from tests/kscript/run.lua (would pollute test-suite stdout).
-- An automated wrapper lives in tests/sanity/test_lua_hello.lua.
print("hello from lua")
