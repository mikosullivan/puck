--[[
{
  "file": "tests/sanity/test_package_path.lua",
  "test_id": "T0.3",
  "verifies": "package.path resolves engine modules via require. tests/kscript/run.lua sets up the path prefix that makes require('kscript.X') resolve under code/kscript/lua/; this test confirms it works for a known engine module.",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local json     = require("kscript.json")
local engine   = require("kscript.engine")

runner.suite("sanity / package path")

runner.test("kscript.json loaded as a table", function()
    assert_.equal(type(json), "table",
        "require('kscript.json') must return a table (the module)")
end)

runner.test("kscript.engine loaded as a table", function()
    assert_.equal(type(engine), "table",
        "require('kscript.engine') must return a table (the module)")
end)
