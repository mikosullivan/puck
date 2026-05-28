--[[
{
  "file":     "tests/caspian/frank/test_launcher_mechanics.lua",
  "test_id":  "TF.0.1, TF.0.2",
  "verifies": "bin/caspian exists, is executable, self-locates correctly, resolves the engine via package.path, and exits cleanly on a trivial fixture. Phase 0 baseline — the launcher itself works.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.0 launcher_mechanics")

runner.test("TF.0.1: bin/caspian is executable and self-locates", function()
    -- Run from the project root with a relative fixture path. If the
    -- launcher self-locates correctly, the engine resolves and the
    -- fixture runs without error.
    local out, _, code = cli.run("tests/caspian/fixtures/exit_zero.casp")
    assert_.equal(code, 0, "exit code should be 0")
    assert_.equal(out,  "ok\n", "stdout should be 'ok\\n'")
end)

runner.test("TF.0.2: launcher resolves the engine and prints to stdout", function()
    local out, err, code = cli.run("tests/caspian/fixtures/exit_zero.casp")
    assert_.equal(code, 0)
    assert_.equal(out,  "ok\n")
    assert_.equal(err,  "", "no stderr output expected on clean run")
end)
