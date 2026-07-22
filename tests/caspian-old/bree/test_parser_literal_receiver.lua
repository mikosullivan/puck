--[[
{
  "file":     "tests/caspian/bree/test_parser_literal_receiver.lua",
  "test_id":  "TB.1",
  "verifies": "Parser accepts a method call on any literal kind as receiver, without the paren'd workaround. Covers string, number, boolean, null, array, hash. Bree only exercises the string case for the fixture; this test exists so later slices inherit a working grammar.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local caspian = require("caspian")

runner.suite("bree / TB.1 literal_as_receiver")

local function method_call(src)
    local ast = caspian.parse(src)
    assert_.kind(ast, "program",   "top-level node for: " .. src)
    assert_.equal(#ast.stmts, 1,   "stmts count for: " .. src)
    local stmt = ast.stmts[1]
    assert_.kind(stmt, "expr_stmt", "stmt wrapper for: " .. src)
    return stmt.expr
end

runner.test("string literal as receiver: 'hello'.to_string", function()
    local m = method_call("'hello'.to_string")
    assert_.kind(m, "method_call", "expression kind")
    assert_.equal(m.name, "to_string")
    assert_.kind(m.object, "string")
    assert_.equal(m.object.value, "hello")
end)

runner.test("integer literal as receiver: 42.to_string", function()
    local m = method_call("42.to_string")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "to_string")
    assert_.kind(m.object, "number")
    assert_.equal(m.object.value, 42)
end)

runner.test("decimal literal as receiver: 3.14.to_string", function()
    local m = method_call("3.14.to_string")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "to_string")
    assert_.kind(m.object, "number")
end)

runner.test("boolean literal as receiver: true.bool", function()
    local m = method_call("true.bool")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "bool")
    assert_.kind(m.object, "bool")
    assert_.equal(m.object.value, true)
end)

runner.test("null literal as receiver: null.flavor", function()
    local m = method_call("null.flavor")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "flavor")
    assert_.kind(m.object, "null")
end)

runner.test("array literal as receiver: [1, 2, 3].length", function()
    local m = method_call("[1, 2, 3].length")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "length")
    assert_.kind(m.object, "array")
    assert_.equal(#m.object.elements, 3)
end)

runner.test("hash literal as receiver: {a: 1}.keys", function()
    local m = method_call("{a: 1}.keys")
    assert_.kind(m, "method_call")
    assert_.equal(m.name, "keys")
    assert_.kind(m.object, "hash")
    assert_.equal(#m.object.pairs, 1)
end)
