--[[
{
  "file":     "tests/caspian/bree/test_parser_check.lua",
  "test_id":  "TB.0.2",
  "verifies": "Parser handles a method-call-on-literal expression via the paren'd workaround ('hello').to_string. Phase-0 baseline: the bare form 'hello'.to_string is rejected today and parsed natively only after the TB.1 parser extension lands.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local caspian = require("caspian")

runner.suite("bree / TB.0.2 parser_check")

runner.test("parser accepts ('hello').to_string (paren'd workaround) without error", function()
    local ast = caspian.parse("('hello').to_string")
    assert_.not_nil(ast, "parser returned nil")
    assert_.kind(ast, "program", "top-level node")
    assert_.not_nil(ast.stmts, "program has no stmts")
    assert_.equal(#ast.stmts, 1, "expected 1 statement in stmts")

    local stmt = ast.stmts[1]
    assert_.kind(stmt, "expr_stmt", "wrapper stmt")
    assert_.kind(stmt.expr, "method_call", "expression")
    assert_.equal(stmt.expr.name, "to_string", "method name")
    assert_.kind(stmt.expr.object, "string", "receiver kind")
    assert_.equal(stmt.expr.object.value, "hello", "receiver value")
end)
