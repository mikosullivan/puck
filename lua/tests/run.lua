--[[
{
  "file": "tests/run.lua",
  "role": "Test suite entry point — requires all test modules then prints pass/fail summary",
  "usage": "Run from lua/ directory: lua tests/run.lua",
  "exit": "0 on all pass, 1 on any failure"
}
]]
-- Run from the lua/ directory: lua tests/run.lua
package.path = "./?.lua;" .. package.path

require("tests.lexer.test_literals")
require("tests.lexer.test_sigils")
require("tests.lexer.test_operators")
require("tests.parser.test_expressions")
require("tests.parser.test_assignments")
require("tests.parser.test_functions")
require("tests.parser.test_classes")
require("tests.parser.test_control")
require("tests.transpiler.test_expressions")
require("tests.transpiler.test_statements")
require("tests.transpiler.test_examples")

local runner = require("tests.support.runner")
local ok = runner.report()
os.exit(ok and 0 or 1)
