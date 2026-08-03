#!/usr/bin/env lua5.4
--[[
{
	"module": "build",
	"role": "Orchestrator for the Caspian build. Produces the complete distribution at /home/miko/projects/puck/ecoverse/build/. Idempotent (wipes and recreates on every run). Calls sibling tools directly via require() rather than spawning subprocesses. See requirements/core/build.md for the spec.",
	"invocation": "tools/build.lua (from the repo root or anywhere)"
}
]]

local script_dir = arg[0]:match("(.*/)")
package.path = script_dir .. "?.lua;" .. package.path

local build_fiona    = require("build-fiona")
local bundle_caspian = require("bundle-caspian")

local repo    = script_dir .. "../"
local BUILD   = os.getenv("HOME") .. "/projects/puck/ecoverse/build"
local SYMLINK = os.getenv("HOME") .. "/.local/bin/caspian"
local FLOPPY_TARGET = 1474560

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function run(cmd)
	local ok, why, code = os.execute(cmd)
	if not ok then error(string.format("command failed (%s %s): %s", why, code, cmd)) end
end

-- os.execute doesn't distinguish "command not found" from other failures
-- cleanly and doesn't give us stdout. For places where we need the output
-- or want to handle failure gracefully, use popen_read / try_run.
local function popen_read(cmd)
	local p = assert(io.popen(cmd, "r"))
	local out = p:read("*a")
	local ok = p:close()
	return out, ok
end

-- Run a command silently, return success bool. Used for rocks that may
-- legitimately fail (missing system headers etc.) — the build continues.
local function try_run(cmd, log_path)
	local full = cmd .. " > " .. log_path .. " 2>&1"
	local ok = os.execute(full)
	return ok == true or ok == 0
end

local function write_file(path, content)
	local f = assert(io.open(path, "w"))
	f:write(content)
	f:close()
end

local function file_size(path)
	local f, err = io.open(path, "rb")
	if not f then error("cannot stat " .. path .. ": " .. tostring(err)) end
	local size = f:seek("end")
	f:close()
	return size
end

-- ------------------------------------------------------------
-- Temp scratch (deleted on exit).
-- ------------------------------------------------------------
local TMP = popen_read("mktemp -d"):gsub("%s+$", "")

-- Lua 5.4 to-be-closed variable ensures cleanup even on error.
local temp_guard <close> = setmetatable({}, {__close = function() run("rm -rf " .. TMP) end})
_ = temp_guard  -- avoid "unused variable" warning

-- ------------------------------------------------------------
-- Wipe and recreate the build tree.
-- ------------------------------------------------------------
print("==> Wiping and recreating " .. BUILD)
run("rm -rf " .. BUILD)
run("mkdir -p " .. BUILD .. "/bin " .. BUILD .. "/caspian " .. BUILD .. "/external")

-- ------------------------------------------------------------
-- Compile the caspian binary.
-- ------------------------------------------------------------
print("==> Compiling bin/caspian")
run(string.format(
	"gcc -O2 -o %s/bin/caspian %ssrc/cli/caspian.c " ..
	"-I/usr/include/lua5.4 /usr/lib/x86_64-linux-gnu/liblua5.4.a -lm -ldl",
	BUILD, repo))

-- ------------------------------------------------------------
-- Phase 1 + Phase 2: build fiona.lua standalone, then bundle it +
-- engine sources into caspian.lua. No temp file for the intermediate
-- fiona.lua — it lives as a string, handed straight to phase 2.
-- ------------------------------------------------------------
print("==> Phase 1: building standalone fiona.lua")
local fiona_src = build_fiona.build()

print("==> Phase 2: bundling caspian.lua")
local caspian_src = bundle_caspian.bundle(fiona_src)
write_file(BUILD .. "/caspian/caspian.lua", caspian_src)

-- Sanity check: the bundled caspian.lua should parse and populate preload.
do
	local chunk = assert(loadfile(BUILD .. "/caspian/caspian.lua"))
	chunk()
	for _, name in ipairs({"trivet", "normalize", "transpiler", "fiona"}) do
		assert(package.preload[name], "preload missing for " .. name)
		package.preload[name] = nil  -- clean up so build.lua's own state stays clean
	end
end

-- ------------------------------------------------------------
-- External libs: download via luarocks. Rocks that fail (missing system
-- headers etc.) are logged and skipped so the build produces a partial
-- picture rather than aborting.
-- ------------------------------------------------------------
print("==> Downloading external libraries into build/external/")

local EXTERNAL_ROCKS = {
	"lsqlite3", "luaexpat", "luasocket", "lpeg",
	"lua-cjson", "pegasus", "luasodium", "dkjson",
}

local failed = {}
for _, rock in ipairs(EXTERNAL_ROCKS) do
	local log = TMP .. "/rock-" .. rock .. ".log"
	local cmd = string.format(
		"luarocks install --tree=%s/external --lua-version 5.4 %s",
		BUILD, rock)
	if try_run(cmd, log) then
		local list = popen_read(string.format(
			"luarocks list --tree=%s/external --lua-version 5.4 --porcelain 2>/dev/null",
			BUILD))
		local version = list:match(rock .. "\t([^\t]+)") or "?"
		print(string.format("    OK  %-15s %s", rock, version))
	else
		print(string.format("    FAIL %-15s (log: %s)", rock, log))
		failed[#failed + 1] = rock
	end
end

-- libsodium is a system C library, not a luarocks rock. Copy the
-- runtime .so from the system into build/external/lib/. Per-arch — this
-- grabs the current build host's copy.
local libsodium_path = popen_read(
	"ldconfig -p 2>/dev/null | awk '/libsodium\\.so\\.[0-9]/ {print $NF; exit}'"
):gsub("%s+$", "")

if libsodium_path ~= "" and io.open(libsodium_path) then
	run("mkdir -p " .. BUILD .. "/external/lib")
	run("cp " .. libsodium_path .. " " .. BUILD .. "/external/lib/")
	print(string.format("    OK  %-15s (system: %s)",
		"libsodium", libsodium_path:match("[^/]+$")))
else
	print(string.format("    FAIL %-15s (system libsodium not installed)", "libsodium"))
	failed[#failed + 1] = "libsodium"
end

if #failed > 0 then
	print()
	print(string.format("    Note: %d external lib(s) missing: %s",
		#failed, table.concat(failed, ", ")))
	print("          Install prerequisite headers/dev packages and rerun to complete.")
end

-- Strip everything luarocks landed that isn't runtime: rock metadata
-- under lib/luarocks and utility executables under bin/. What remains
-- is exactly what `require` reaches for at runtime.
run("rm -rf " .. BUILD .. "/external/lib/luarocks " .. BUILD .. "/external/bin")

-- ------------------------------------------------------------
-- Repoint the shell symlink.
-- ------------------------------------------------------------
run("rm -f " .. SYMLINK)
run("ln -s " .. BUILD .. "/bin/caspian " .. SYMLINK)
print("==> Repointed " .. SYMLINK .. " -> " .. BUILD .. "/bin/caspian")

-- ------------------------------------------------------------
-- Size report. Every file under $BUILD is runtime now that luarocks
-- cruft has been stripped.
-- ------------------------------------------------------------
print()
print("==> Size report")
print(string.format("%-65s %10s", "path", "bytes"))
print(string.format("%-65s %10s", "----", "-----"))

local total = 0
local list = popen_read("find " .. BUILD .. " -type f | sort")
for path in list:gmatch("[^\n]+") do
	local size = file_size(path)
	print(string.format("%-65s %10d", path:sub(#BUILD + 2), size))
	total = total + size
end

print()
print(string.rep("-", 76))
print(string.format("%-65s %10d", "TOTAL", total))
print()
print(string.format("Total vs floppy budget: %d / %d bytes (%d%%)",
	total, FLOPPY_TARGET, math.floor(total * 100 / FLOPPY_TARGET)))
print()
print("Build complete: " .. BUILD)
