--[[
{
  "file": "tests/sanity/test_package_path.lua",
  "test_id": "T0.3",
  "verifies": "package.path resolves engine modules via require. tests/caspian/run.lua sets up the path prefix that makes require('caspian.X') resolve under lib/lua/caspian/; this test confirms it works for a known engine module.",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local json     = require("caspian.json")
local engine   = require("caspian.engine")

runner.suite("sanity / package path")

runner.test("caspian.json loaded as a table", function()
    assert_.equal(type(json), "table",
        "require('caspian.json') must return a table (the module)")
end)

runner.test("caspian.engine loaded as a table", function()
    assert_.equal(type(engine), "table",
        "require('caspian.engine') must return a table (the module)")
end)
