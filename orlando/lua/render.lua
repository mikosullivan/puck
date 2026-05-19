--[[
{
  "file":  "orlando/lua/render.lua",
  "role":  "CLI: render a Markdown file to a minimal HTML page on stdout. Same rendering pipeline as the server uses, just dumped to stdout instead of sent over HTTP.",
  "usage": "lua orlando/lua/render.lua [path]   (defaults to README.md)"
}
]]

-- Add orlando module path + luarocks --local path (where lunamark lives).
package.path = "./orlando/lua/?.lua;./orlando/lua/?/init.lua;" .. package.path
local home = os.getenv("HOME")
if home then
    package.path  = home .. "/.luarocks/share/lua/5.1/?.lua;"
                 .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
                 .. package.path
    package.cpath = home .. "/.luarocks/lib/lua/5.1/?.so;" .. package.cpath
end

local page = require("orlando.page")

local path = (arg and arg[1]) or "README.md"
io.write(page.render_file(path))
