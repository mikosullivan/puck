--[[
{
  "file":     "tests/caspian/frank/test_shebang.lua",
  "test_id":  "TF.3",
  "verifies": "A .casp file with #!/usr/bin/env caspian shebang is directly runnable when bin/ is on PATH. Exercises both the OS-level shebang handling and the launcher's shebang-stripping in source.",
  "level":    "integration"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local cli     = require("frank.support.cli")

runner.suite("frank / TF.3 shebang")

runner.test("shebang fixture runs directly when bin/ is on PATH", function()
    local out, _, code = cli.run_shebang("tests/caspian/fixtures/hello_shebang.casp")
    assert_.equal(code, 0)
    assert_.equal(out, "shebang ok\n")
end)
