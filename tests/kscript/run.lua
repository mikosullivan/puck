--[[
{
  "file": "tests/kscript/run.lua",
  "role": "Test suite entry point — requires all test modules then prints pass/fail summary",
  "usage": "Run from project root: lua tests/kscript/run.lua",
  "exit": "0 on all pass, 1 on any failure"
}
]]
-- Run from the project root: lua tests/kscript/run.lua
-- The package.path additions:
--   ./code/kscript/lua/?.lua and ./code/kscript/lua/?/init.lua
--     resolve `require("kscript")` and `require("kscript.lexer")` against the
--     Lua reference implementation at code/kscript/lua/kscript/.
--   ./tests/kscript/?.lua resolves test-side requires (lexer.test_literals,
--     support.runner, etc.) against this directory.
package.path = "./code/kscript/lua/?.lua;./code/kscript/lua/?/init.lua;"
            .. "./tests/kscript/?.lua;./tests/kscript/?/init.lua;"
            .. package.path

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

local runner = require("support.runner")
local ok = runner.report()
os.exit(ok and 0 or 1)
