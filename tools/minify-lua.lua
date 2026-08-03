#!/usr/bin/env lua5.4
--[[
{
	"module": "minify-lua",
	"role": "Build-time Lua minifier. Wraps LuaSrcDiet's optimize() with DEFAULT_OPTS. Applied to Caspian-authored source (engine + Fiona + Lua binding wrapper) before it enters the caspian.lua bundle. Third-party externals stay raw — the debug / license / audit cost of minifying upstream code isn't worth the byte savings against 260 kb of budget headroom. See requirements/core/build.md.",
	"exports": {
		"minify": "src (string) -> minified src (string)"
	},
	"cli": "lua5.4 tools/minify-lua.lua < input.lua > output.lua"
}
]]

local home = os.getenv("HOME") or "."
package.path = home .. "/.luarocks/share/lua/5.4/?.lua;"
             .. home .. "/.luarocks/share/lua/5.4/?/init.lua;"
             .. package.path

local M = {}

--[[ {"in": "src (string)", "out": "minified src (string)"} ]]
function M.minify(src)
	local luasrcdiet = require("luasrcdiet")
	return luasrcdiet.optimize(luasrcdiet.DEFAULT_OPTS, src)
end

if arg and arg[0] and arg[0]:match("minify%-lua%.lua$") then
	io.write(M.minify(io.read("*a")))
end

return M
