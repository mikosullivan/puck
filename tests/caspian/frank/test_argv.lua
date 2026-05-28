--[[
{
  "file":     "tests/caspian/frank/test_argv.lua",
  "test_id":  "TF.4",
  "verifies": "Command-line arguments reach the Caspian program via %argv. For Frank, %argv resolves to a space-joined string of all args (proper array form arrives in a later slice).",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.4 argv")

runner.test("argv passes 'foo bar baz' through to %argv", function()
    local out, _, code = cli.run("tests/caspian/fixtures/echo_argv.casp",
                                 "foo", "bar", "baz")
    assert_.equal(code, 0)
    assert_.equal(out, "foo bar baz\n")
end)

runner.test("argv is empty when no args passed", function()
    local out, _, code = cli.run("tests/caspian/fixtures/echo_argv.casp")
    assert_.equal(code, 0)
    assert_.equal(out, "\n", "empty argv prints just the newline from puts")
end)
