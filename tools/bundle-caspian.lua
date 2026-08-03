#!/usr/bin/env lua5.4
--[[
{
	"module": "bundle-caspian",
	"role": "Phase-2 of the build. Wraps each module in the input list inside a `package.preload[name] = function() ... end` block and concatenates them into a single caspian.lua source string. Callers compose the module list — that's where minification / Caspian-vs-external decisions live. Consumers of the output do `require('trivet')` / `require('socket.http')` etc. and Lua finds each in preload without touching the filesystem.",
	"exports": {
		"bundle": "modules (list of {name, src}) -> caspian.lua source (string)"
	},
	"cli": "lua5.4 tools/bundle-caspian.lua > caspian.lua — reads engine sources from src/engine/, bundles them, writes to stdout. No minification. Used for standalone bundle-only invocations."
}
]]

local script_dir = arg[0]:match("(.*/)")
local repo = script_dir .. "../"

local function slurp(path)
	local f, err = io.open(path, "r")
	if not f then error("cannot open " .. path .. ": " .. tostring(err)) end
	local s = f:read("*a")
	f:close()
	return s
end

local M = {}

--[[ {"in": {"modules": "list of {name, src} tuples — every module to bundle (Caspian-authored + external), in the order they should appear in caspian.lua"}, "out": "bundled caspian.lua source (string)"} ]]
function M.bundle(modules)
	local parts = {[[
-- caspian.lua — bundled Caspian distribution.
-- Assembled by tools/bundle-caspian.lua at build time. Each source
-- module is wrapped in `package.preload[name] = function() ... end`
-- so `require("trivet")`, `require("socket.http")`, etc. resolve from
-- memory rather than hitting the filesystem. Includes Caspian's own
-- engine modules (trivet, normalize, transpiler) plus every pure-Lua
-- wrapper from the External tier — pegasus, luasocket's Lua side,
-- dkjson, etc. C bindings (.so) stay on disk under external/lib/.

]]}

	for _, mod in ipairs(modules) do
		parts[#parts + 1] = string.format(
			"------------------------------------------------------------\n" ..
			"-- module: %s\n" ..
			"------------------------------------------------------------\n\n" ..
			"package.preload[%q] = function(...)\n%s\nend\n\n",
			mod.name, mod.name, mod.src)
	end

	parts[#parts + 1] = "return true\n"

	return table.concat(parts)
end

-- CLI shim: reads engine sources from src/engine/, composes the module
-- list, calls .bundle(), writes to stdout. No minification (that's
-- build.lua's job).
if arg and arg[0] and arg[0]:match("bundle%-caspian%.lua$") then
	local modules = {
		{name = "trivet",     src = slurp(repo .. "src/engine/trivet.lua")},
		{name = "normalize",  src = slurp(repo .. "src/engine/normalize.lua")},
		{name = "transpiler", src = slurp(repo .. "src/engine/transpiler.lua")},
	}
	io.write(M.bundle(modules))
end

return M
