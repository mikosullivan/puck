--[[
{
  "module": "tests.frank.support.cli",
  "role":   "Subprocess-invoke bin/caspian for Frank tests. Captures stdout, stderr, and exit code separately by redirecting stderr to a per-call tmpfile.",
  "usage":  "local out, err, code = cli.run('tests/caspian/fixtures/exit_zero.casp', 'arg1', 'arg2')"
}
]]
local M = {}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run `bin/caspian <fixture> [args...]` and return (stdout, stderr, exit_code).
function M.run(fixture, ...)
    local parts = { "./bin/caspian", shell_quote(fixture) }
    for _, a in ipairs({ ... }) do
        parts[#parts + 1] = shell_quote(a)
    end

    local stderr_file = os.tmpname()
    local cmd = table.concat(parts, " ") .. " 2> " .. stderr_file

    local h = assert(io.popen(cmd, "r"), "io.popen failed")
    local stdout = h:read("*a") or ""
    -- Lua 5.4 popen handle close() returns (ok_bool, "exit"|"signal", code).
    local _ok, _reason, code = h:close()

    local sf = io.open(stderr_file, "r")
    local stderr = sf and sf:read("*a") or ""
    if sf then sf:close() end
    os.remove(stderr_file)

    return stdout, stderr, code
end

-- Run an already-executable .casp file directly (shebang form), with bin/
-- prepended to PATH so the `caspian` shebang resolves to our launcher.
function M.run_shebang(executable_path, ...)
    local bin_abs = io.popen("pwd"):read("*a"):gsub("\n", "") .. "/bin"
    local parts = { "env", 'PATH="' .. bin_abs .. ':$PATH"', shell_quote(executable_path) }
    for _, a in ipairs({ ... }) do
        parts[#parts + 1] = shell_quote(a)
    end

    local stderr_file = os.tmpname()
    local cmd = table.concat(parts, " ") .. " 2> " .. stderr_file

    local h = assert(io.popen(cmd, "r"), "io.popen failed")
    local stdout = h:read("*a") or ""
    -- Lua 5.4 popen handle close() returns (ok_bool, "exit"|"signal", code).
    local _ok, _reason, code = h:close()

    local sf = io.open(stderr_file, "r")
    local stderr = sf and sf:read("*a") or ""
    if sf then sf:close() end
    os.remove(stderr_file)

    return stdout, stderr, code
end

return M
