--[[
{
  "file": "orlando/lua/serve.lua",
  "role": "Command-line entry point; sets package.path then launches orlando.serve()",
  "usage": "lua orlando/lua/serve.lua [port]",
  "naming": "Named `serve.lua` (not `orlando.lua`) so it does not shadow the `orlando` package in require's search path."
}
]]
package.path = "./orlando/lua/?.lua;./orlando/lua/?/init.lua;" .. package.path

-- luarocks --local installs (lunamark and its deps) under ~/.luarocks/share/lua/5.1.
-- The code is 5.1/5.4 compatible; we just need to add the path so require() finds it.
local home = os.getenv("HOME")
if home then
    package.path  = home .. "/.luarocks/share/lua/5.1/?.lua;"
                 .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
                 .. package.path
    package.cpath = home .. "/.luarocks/lib/lua/5.1/?.so;" .. package.cpath
end

local orlando = require("orlando")

local port = tonumber(arg and arg[1]) or 8181
orlando.serve({ port = port })
