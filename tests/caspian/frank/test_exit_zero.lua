--[[
{
  "file":     "tests/caspian/frank/test_exit_zero.lua",
  "test_id":  "TF.1",
  "verifies": "A successful Caspian program exits with code 0.",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.1 exit_zero")

runner.test("clean program run exits 0", function()
    local _, _, code = cli.run("tests/caspian/fixtures/exit_zero.casp")
    assert_.equal(code, 0)
end)
