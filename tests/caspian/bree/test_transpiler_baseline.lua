--[[
{
  "file":     "tests/caspian/bree/test_transpiler_baseline.lua",
  "test_id":  "TB.0.3",
  "verifies": "Transpiler emits canonical CaspianJ for the paren'd workaround form ('hello').to_string today — output is already the canonical receiver-method shape. Phase-0 baseline; once the parser extension lands in Phase 1, the bare form 'hello'.to_string will produce the same tree (TB.2).",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("bree / TB.0.3 transpiler_baseline")

runner.test("transpiler emits canonical CaspianJ for ('hello').to_string", function()
    local tree = engine.parse_caspian("('hello').to_string")
    assert_.not_nil(tree, "transpile returned nil")
    assert_.equal(#tree, 1, "expected 1 top-level statement")

    local stmt = tree[1]
    assert_.equal(type(stmt), "table", "statement is not a table")
    assert_.equal(#stmt,   2,           "statement array length")
    assert_.equal(stmt[2], "to_string", "method name")

    local recv = stmt[1]
    assert_.equal(type(recv),  "table", "receiver is not a table")
    assert_.equal(recv.value,  "hello", "receiver value")
end)
