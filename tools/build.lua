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
local minify_lua     = require("minify-lua")

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

local function slurp(path)
	local f, err = io.open(path, "r")
	if not f then error("cannot open " .. path .. ": " .. tostring(err)) end
	local s = f:read("*a")
	f:close()
	return s
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
-- External libs: download via luarocks. Rocks that fail (missing system
-- headers etc.) are logged and skipped so the build produces a partial
-- picture rather than aborting. Runs before phase 2 so the bundler can
-- fold the pure-Lua wrappers from external/share into caspian.lua.
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
-- Collect external pure-Lua modules for folding into caspian.lua.
-- Walks external/share/lua/5.4/, converts each path to a module name
-- (foo/bar.lua → foo.bar; foo/init.lua → foo), and reads the source.
-- json2lua.lua / lua2json.lua are CLI utility scripts that landed in
-- share by luarocks — filtered out here rather than bundled.
-- ------------------------------------------------------------
local external_share = BUILD .. "/external/share/lua/5.4"
local excluded_modules = {["json2lua"] = true, ["lua2json"] = true}
local external_modules = {}

local pipe = io.popen("find " .. external_share .. " -type f -name '*.lua' 2>/dev/null | sort")
if pipe then
	for path in pipe:lines() do
		local rel = path:sub(#external_share + 2):sub(1, -5)  -- strip prefix + ".lua"
		rel = rel:gsub("/init$", "")
		local module_name = rel:gsub("/", ".")
		if not excluded_modules[module_name] then
			local f = io.open(path, "r")
			local src = f:read("*a")
			f:close()
			external_modules[#external_modules + 1] = {name = module_name, src = src}
		end
	end
	pipe:close()
end

print(string.format("==> Collected %d external Lua modules for bundling", #external_modules))

-- ------------------------------------------------------------
-- Phase 1: build fiona.lua standalone (with SQL inlined). No temp file
-- for the intermediate — it lives as a string, handed straight to
-- phase 2.
-- ------------------------------------------------------------
print("==> Phase 1: building standalone fiona.lua")
local fiona_src = build_fiona.build()

-- ------------------------------------------------------------
-- Minify Caspian-authored code. LuaSrcDiet on the engine modules
-- and Fiona takes them from ≈182 kb of source down to ≈100 kb.
-- Externals stay raw — see requirements/core/build.md.
-- ------------------------------------------------------------
print("==> Minifying Caspian-authored code (LuaSrcDiet)")

local function minify_with_size(label, src)
	local mini = minify_lua.minify(src)
	print(string.format("    %-15s %d → %d (%d%%)",
		label, #src, #mini, math.floor(#mini * 100 / #src)))
	return mini
end

local caspian_modules = {
	{name = "trivet",     src = minify_with_size("trivet",     slurp(repo .. "src/engine/trivet.lua"))},
	{name = "normalize",  src = minify_with_size("normalize",  slurp(repo .. "src/engine/normalize.lua"))},
	{name = "transpiler", src = minify_with_size("transpiler", slurp(repo .. "src/engine/transpiler.lua"))},
	{name = "fiona",      src = minify_with_size("fiona",      fiona_src)},
}

-- ------------------------------------------------------------
-- Phase 2: bundle Caspian-authored + external Lua into caspian.lua.
-- Order: our own modules first (deterministic ordering), external
-- modules after (from luarocks tree walk in sorted order).
-- ------------------------------------------------------------
print("==> Phase 2: bundling caspian.lua")

local all_modules = {}
for _, mod in ipairs(caspian_modules) do
	all_modules[#all_modules + 1] = mod
end
for _, mod in ipairs(external_modules) do
	all_modules[#all_modules + 1] = mod
end

local caspian_src = bundle_caspian.bundle(all_modules)
write_file(BUILD .. "/caspian/caspian.lua", caspian_src)

-- Sanity check: the bundled caspian.lua should parse and populate preload.
do
	local chunk = assert(loadfile(BUILD .. "/caspian/caspian.lua"))
	chunk()
	for _, name in ipairs({"trivet", "normalize", "transpiler", "fiona"}) do
		assert(package.preload[name], "preload missing for " .. name)
	end
	-- Clean up so build.lua's own state stays clean.
	for _, mod in ipairs(external_modules) do
		package.preload[mod.name] = nil
	end
	for _, name in ipairs({"trivet", "normalize", "transpiler", "fiona"}) do
		package.preload[name] = nil
	end
end

-- Every pure-Lua external module is now inside caspian.lua's preload —
-- external/share/ has no runtime role and gets removed.
run("rm -rf " .. BUILD .. "/external/share")

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
