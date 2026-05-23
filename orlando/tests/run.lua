--[[
{
  "file": "orlando/tests/run.lua",
  "role": "Test suite entry point — requires all test modules then prints pass/fail summary",
  "usage": "Run from project root: lua orlando/tests/run.lua",
  "exit": "0 on all pass, 1 on any failure"
}
]]
package.path = "./orlando/lua/?.lua;./orlando/lua/?/init.lua;"
            .. "./orlando/tests/?.lua;./orlando/tests/?/init.lua;"
            .. package.path

-- luarocks --local installs (lunamark and its deps) live under ~/.luarocks/share/lua/5.1.
local home = os.getenv("HOME")
if home then
    package.path  = home .. "/.luarocks/share/lua/5.1/?.lua;"
                 .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
                 .. package.path
    package.cpath = home .. "/.luarocks/lib/lua/5.1/?.so;" .. package.cpath
end

local runner = require("support.runner")

require("content_type.test_content_type")
require("quick_builder.test_quick_builder")
require("json_highlight.test_json_highlight")
require("route.test_route")
require("hello.test_hello")
require("search.test_search")
require("random.test_random")
require("sections.test_sections")
require("config.test_config")

os.exit(runner.report() and 0 or 1)
