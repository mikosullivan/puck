--[[
{
  "file": "tests/charlie/run.lua",
  "role": "Test suite entry point — requires all test modules then prints pass/fail summary",
  "usage": "Run from project root: lua tests/charlie/run.lua",
  "exit": "0 on all pass, 1 on any failure"
}
]]
-- Run from the project root: lua tests/charlie/run.lua
-- The package.path additions:
--   ./code/charlie/lua/?.lua and ./code/charlie/lua/?/init.lua
--     resolve `require("charlie")` and `require("charlie.lexer")` against the
--     Lua reference implementation at code/charlie/lua/charlie/.
--   ./tests/charlie/?.lua resolves test-side requires (lexer.test_literals,
--     support.runner, etc.) against this directory.
package.path = "./code/charlie/lua/?.lua;./code/charlie/lua/?/init.lua;"
            .. "./tests/charlie/?.lua;./tests/charlie/?/init.lua;"
            .. "./tests/sanity/?.lua;"
            .. package.path

-- Phase 0 sanity tests — must pass before any engine tests have meaning
-- (T0.1-T0.6 per documentation/development/development.md Pike section)
require("test_lua_version")
require("test_lua_hello")
require("test_package_path")
require("test_framework_sanity")
require("test_json_parse")
require("test_file_read")

require("lexer.test_literals")
require("lexer.test_sigils")
require("lexer.test_operators")
require("parser.test_expressions")
require("parser.test_assignments")
require("parser.test_functions")
require("parser.test_classes")
require("parser.test_control")
require("transpiler.test_expressions")
require("transpiler.test_statements")
require("transpiler.test_examples")

-- V0.01 phase 1: hello-world in canonical CharlieJSON
require("v001.test_json_parse")
require("v001.test_bootstrap")
require("v001.test_materialize")
require("v001.test_lookup_method")
require("v001.test_transition")
require("v001.test_dispatch")
require("v001.test_run")
require("v001.test_transition_observed")
require("v001.test_sys_role")

local runner = require("support.runner")
local ok = runner.report()
os.exit(ok and 0 or 1)
