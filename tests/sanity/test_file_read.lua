--[[
{
  "file": "tests/sanity/test_file_read.lua",
  "test_id": "T0.6",
  "verifies": "io.open + read('*a') returns the expected bytes from a KSJ-style fixture file. The engine reads KSJ files from disk via this exact pattern (see engine.run in engine.lua); this test confirms it works on the host filesystem.",
  "level": "unit",
  "fixture": "tests/kscript/fixtures/_sanity_text.txt (contains 'ok\\n')"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")

runner.suite("sanity / file read")

runner.test("io.open + read('*a') returns expected bytes", function()
    local f, err = io.open("tests/kscript/fixtures/_sanity_text.txt", "r")
    assert_.not_nil(f, "fixture must open: " .. tostring(err))
    local content = f:read("*a")
    f:close()
    assert_.equal(content, "ok\n",
        "fixture must contain exactly 'ok' plus newline")
end)
