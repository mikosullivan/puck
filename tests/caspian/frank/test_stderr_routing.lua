--[[
{
  "file":     "tests/caspian/frank/test_stderr_routing.lua",
  "test_id":  "TF.5",
  "verifies": "Load-bearing routing check: program output (puts) goes to stdout; engine error goes to stderr. The two streams do not interleave.",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.5 stderr_routing")

runner.test("puts goes to stdout, engine error goes to stderr — no interleaving", function()
    local out, err, code = cli.run("tests/caspian/fixtures/mixed_io.casp")

    assert_.not_equal(code, 0, "exit code should be non-zero (error raised)")
    -- Program output landed on stdout, NOT mixed with stderr.
    assert_.equal(out, "program-output-line\n",
                  "stdout should contain only the puts output")
    -- Diagnostic landed on stderr, NOT on stdout.
    assert_.not_equal(err, "", "stderr should contain the engine error")
    assert_.is_true(out:find("missing_key", 1, true) == nil,
                    "stdout must not contain the engine error text")
end)
