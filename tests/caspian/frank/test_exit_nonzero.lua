--[[
{
  "file":     "tests/caspian/frank/test_exit_nonzero.lua",
  "test_id":  "TF.2",
  "verifies": "An uncaught error exits non-zero and writes a diagnostic to stderr (not stdout).",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.2 exit_nonzero")

runner.test("uncaught hash-method-missing exits non-zero, diagnostic on stderr", function()
    local out, err, code = cli.run("tests/caspian/fixtures/raise.casp")
    assert_.not_equal(code, 0, "exit code should be non-zero")
    assert_.equal(out, "", "stdout should be empty")
    assert_.not_equal(err, "", "stderr should contain a diagnostic")
    -- Spot-check that the error mentions the missing key.
    assert_.is_true(err:find("missing_key", 1, true) ~= nil,
                    "stderr should mention the missing key; got: " .. err)
end)
