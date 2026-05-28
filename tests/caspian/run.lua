--[[
{
  "file": "tests/caspian/run.lua",
  "role": "Test suite entry point — requires all test modules then prints pass/fail summary",
  "usage": "Run from project root: lua tests/caspian/run.lua",
  "exit": "0 on all pass, 1 on any failure"
}
]]
-- Run from the project root: lua tests/caspian/run.lua
-- The package.path additions:
--   ./lib/lua/?.lua and ./lib/lua/?/init.lua
--     resolve `require("caspian")` and `require("caspian.lexer")` against the
--     Lua reference implementation (Lucy) at lib/lua/caspian/.
--   ./tests/caspian/?.lua resolves test-side requires (lexer.test_literals,
--     support.runner, etc.) against this directory.
package.path = "./lib/lua/?.lua;./lib/lua/?/init.lua;"
            .. "./tests/caspian/?.lua;./tests/caspian/?/init.lua;"
            .. "./tests/sanity/?.lua;"
            .. package.path

-- Phase 0 sanity tests — must pass before any engine tests have meaning
-- (T0.1-T0.6 per documentation/development/index.md Pike section)
require("test_lua_version")
require("test_lua_hello")
require("test_package_path")
require("test_framework_sanity")
require("test_json_parse")
require("test_file_read")

require("v00.lexer.test_literals")
require("v00.lexer.test_sigils")
require("v00.lexer.test_operators")
require("v00.parser.test_expressions")
require("v00.parser.test_assignments")
require("v00.parser.test_functions")
require("v00.parser.test_classes")
require("v00.parser.test_control")
require("v00.transpiler.test_expressions")
require("v00.transpiler.test_statements")
require("v00.transpiler.test_examples")

-- Aslan: hello-world in canonical CaspianJ
require("aslan.test_fixture_parse")
require("aslan.test_bootstrap")
require("aslan.test_materialize")
require("aslan.test_lookup_method")
require("aslan.test_transition")
require("aslan.test_dispatch")
require("aslan.test_run")
require("aslan.test_transition_observed")

-- Bree: hello-world from Caspian source
-- Phase 0: source-side workbench
require("bree.test_lexer_check")
require("bree.test_parser_check")
require("bree.test_transpiler_baseline")
require("bree.test_engine_run_tree")
-- Phase 1: hello-world from source + load-bearing extensions
require("bree.test_parser_literal_receiver")
require("bree.test_transpiler_canonical")
require("bree.test_engine_run_returns_hello")
require("bree.test_integration")
require("bree.test_call_stack_role")
require("bree.test_aslan_regression")
require("bree.test_end_marker")

-- Corin: puts-hello from Caspian source, observed on a host-installed stdout sink
-- Phase 0
require("corin.test_source_baseline")
require("corin.test_std_property_slot")
-- Phase 1
require("corin.test_transpiler_canonical")
require("corin.test_bootstrap_registry")
require("corin.test_dispatch_bwc")
require("corin.test_engine_std_writes")
require("corin.test_role_transition")
require("corin.test_integration")
require("corin.test_regression")
require("corin.test_puts_no_sink")

-- Digory: hashes (literal materialization, method_missing key access)
-- Phase 0
require("digory.test_source_baseline")
-- Phase 1
require("digory.test_transpiler_canonical")
require("digory.test_bootstrap_hash_class")
require("digory.test_insertion_order")
require("digory.test_key_access")
require("digory.test_role_transition")
require("digory.test_integration")
require("digory.test_regression")

-- Edmund: JSON serialization (.to_json on every primitive class)
-- Phase 0
require("edmund.test_source_baseline")
-- Phase 1
require("edmund.test_transpiler_canonical")
require("edmund.test_bootstrap_primitives")
require("edmund.test_materialize_primitives")
require("edmund.test_to_json_string")
require("edmund.test_insertion_order")
require("edmund.test_round_trip")
require("edmund.test_integration")
require("edmund.test_regression")
require("edmund.test_null_distinctness")

-- Frank: CLI launcher + stderr + argv
-- Phase 0
require("frank.test_launcher_mechanics")
-- Phase 1
require("frank.test_exit_zero")
require("frank.test_exit_nonzero")
require("frank.test_shebang")
require("frank.test_argv")
require("frank.test_stderr_routing")

local runner = require("support.runner")
local ok = runner.report()
os.exit(ok and 0 or 1)
