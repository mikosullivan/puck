#!/usr/bin/env lua5.4
--[[
{
	"module": "bundle-caspian",
	"role": "Phase-2 of the build. Concatenates the Caspian-authored Lua modules into one caspian.lua by wrapping each in a `package.preload[name] = function() ... end` block. Consumers do require('trivet') / require('fiona') / etc. and Lua finds each in package.preload without touching the filesystem. Takes the phase-1 fiona.lua source string (from tools/build-fiona.lua) directly.",
	"exports": {
		"bundle": "fiona_src (string) -> caspian.lua source (string)"
	},
	"cli": "lua5.4 tools/bundle-caspian.lua <path-to-phase-1-fiona.lua> > caspian.lua — same output as .bundle(), written to stdout"
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

--[[ {"in": {"fiona_src": "string — phase-1 fiona.lua source (from build-fiona.build())"}, "out": "bundled caspian.lua source (string)"} ]]
function M.bundle(fiona_src)
	local modules = {
		{name = "trivet",     src = slurp(repo .. "src/engine/trivet.lua")},
		{name = "normalize",  src = slurp(repo .. "src/engine/normalize.lua")},
		{name = "transpiler", src = slurp(repo .. "src/engine/transpiler.lua")},
		{name = "fiona",      src = fiona_src},
	}

	local parts = {[[
-- caspian.lua — bundled Caspian distribution.
-- Assembled by tools/bundle-caspian.lua at build time. Each source
-- module is wrapped in `package.preload[name] = function() ... end`
-- so `require("trivet")`, `require("fiona")`, etc. resolve from
-- memory rather than hitting the filesystem. Sourced from:
--   src/engine/trivet.lua
--   src/engine/normalize.lua
--   src/engine/transpiler.lua
--   src/fiona/fiona.lua (schemas inlined by tools/build-fiona.lua)

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

-- CLI shim: takes a path to phase-1 fiona.lua, calls .bundle() on it,
-- writes to stdout.
if arg and arg[0] and arg[0]:match("bundle%-caspian%.lua$") then
	local path = arg[1]
	if not path then
		io.stderr:write("bundle-caspian: missing argument (path to phase-1 fiona.lua)\n")
		os.exit(1)
	end
	io.write(M.bundle(slurp(path)))
end

return M
