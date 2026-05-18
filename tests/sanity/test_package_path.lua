--[[
{
  "file": "tests/sanity/test_package_path.lua",
  "test_id": "T0.3",
  "verifies": "package.path resolves engine modules via require. tests/charlie/run.lua sets up the path prefix that makes require('charlie.X') resolve under code/charlie/lua/; this test confirms it works for a known engine module.",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local json     = require("charlie.json")
local engine   = require("charlie.engine")

runner.suite("sanity / package path")

runner.test("charlie.json loaded as a table", function()
    assert_.equal(type(json), "table",
        "require('charlie.json') must return a table (the module)")
end)

runner.test("charlie.engine loaded as a table", function()
    assert_.equal(type(engine), "table",
        "require('charlie.engine') must return a table (the module)")
end)
