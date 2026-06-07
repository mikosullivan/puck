--[[
{
  "file":     "tests/caspian/frank/test_admin_flags.lua",
  "test_id":  "TF.A.1 — TF.A.7",
  "verifies": "Admin-flag dispatch in the CLI launcher: --version, --help, --update-cache stub, --clear-cache stub (with and without -y bypass, with and without cancelled prompt), unknown-flag error. The cache subsystem itself is a future slice (Gabbo); these tests cover the dispatch shape and exit codes that will stay stable when the underlying ops land.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")

-- Local CLI helper extended to support stdin piping (the standard cli.run
-- helper doesn't, and --clear-cache prompts on stdin).
local M = {}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run bin/caspian with optional stdin and capture stdout/stderr/exit.
local function run_with_stdin(stdin_text, ...)
    local parts = { "./bin/caspian" }
    for _, a in ipairs({ ... }) do
        parts[#parts + 1] = shell_quote(a)
    end

    local stdin_file = nil
    if stdin_text then
        stdin_file = os.tmpname()
        local sf = assert(io.open(stdin_file, "w"))
        sf:write(stdin_text)
        sf:close()
    end

    local stderr_file = os.tmpname()
    local cmd = table.concat(parts, " ") .. " 2> " .. stderr_file
    if stdin_file then cmd = cmd .. " < " .. stdin_file end

    local h = assert(io.popen(cmd, "r"), "io.popen failed")
    local stdout = h:read("*a") or ""
    local _ok, _reason, code = h:close()

    local ef = io.open(stderr_file, "r")
    local stderr = ef and ef:read("*a") or ""
    if ef then ef:close() end
    os.remove(stderr_file)
    if stdin_file then os.remove(stdin_file) end

    return stdout, stderr, code
end

runner.suite("frank / TF.A admin_flags")

runner.test("TF.A.1: --version prints the version and exits 0", function()
    local out, err, code = run_with_stdin(nil, "--version")
    assert_.equal(code, 0, "--version should exit 0")
    assert_.not_nil(out:match("^caspian %S+\n$"), "stdout should be 'caspian <version>\\n', got: " .. out)
    assert_.equal(err, "", "no stderr")
end)

runner.test("TF.A.2: --help prints usage and exits 0", function()
    local out, _, code = run_with_stdin(nil, "--help")
    assert_.equal(code, 0)
    assert_.not_nil(out:match("^Usage:"), "stdout should start with 'Usage:'")
    assert_.not_nil(out:match("%-%-update%-cache"), "help should mention --update-cache")
    assert_.not_nil(out:match("%-%-clear%-cache"), "help should mention --clear-cache")
end)

runner.test("TF.A.3: --update-cache (stub) exits 1 with not-implemented message", function()
    local out, err, code = run_with_stdin(nil, "--update-cache")
    assert_.equal(code, 1, "stub should exit 1 (operation didn't actually run)")
    assert_.equal(out, "", "no stdout for the stub")
    assert_.not_nil(err:match("not yet implemented"), "stderr should explain")
end)

runner.test("TF.A.4: --clear-cache --yes (stub) skips prompt, exits 1", function()
    local out, err, code = run_with_stdin(nil, "--clear-cache", "--yes")
    assert_.equal(code, 1)
    assert_.equal(out, "", "no prompt when --yes is passed")
    assert_.not_nil(err:match("not yet implemented"))
end)

runner.test("TF.A.5: --clear-cache -y (short form) also skips prompt", function()
    local out, _, code = run_with_stdin(nil, "--clear-cache", "-y")
    assert_.equal(code, 1)
    assert_.equal(out, "", "no prompt when -y is passed")
end)

runner.test("TF.A.6: --clear-cache with 'n' cancels (exit 130)", function()
    local out, _, code = run_with_stdin("n\n", "--clear-cache")
    assert_.equal(code, 130, "cancel should exit 130 (SIGINT-style)")
    assert_.not_nil(out:match("Cancelled"), "should report cancellation")
end)

runner.test("TF.A.7: unknown flag exits 2 with helpful error", function()
    local _, err, code = run_with_stdin(nil, "--bogus")
    assert_.equal(code, 2, "usage errors exit 2")
    assert_.not_nil(err:match("unknown flag"), "stderr should say 'unknown flag'")
end)

runner.test("TF.A.8: --yes alone (no command) is a usage error", function()
    local _, err, code = run_with_stdin(nil, "--yes")
    assert_.equal(code, 2)
    assert_.not_nil(err:match("modifier, not a command"), "should explain the misuse")
end)

return M
