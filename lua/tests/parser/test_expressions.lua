--[[
{
  "suite": "parser / expressions",
  "covers": "all primary types, binop/unop, method_call, subscript, array, hash, pipe, safe_call, func_call with pos/kw args"
}
]]
local runner = require("tests.support.runner")
local assert = require("tests.support.assert")
local ks     = require("kscript")

--[[ { "in": "src: string", "out": "AST node  (expression of first statement)", "note": "parse helper; returns ast.stmts[1].expr" } ]]
local function expr(src)
    local ast = ks.parse(src)
    return ast.stmts[1].expr
end

runner.suite("parser / expressions")

runner.test("string literal", function()
    local n = expr("'hello'")
    assert.kind(n, "string")
    assert.equal(n.value, "hello")
end)

runner.test("symbol is string", function()
    local n = expr(":foo")
    assert.kind(n, "string")
    assert.equal(n.value, "foo")
end)

runner.test("integer", function()
    local n = expr("42")
    assert.kind(n, "number")
    assert.equal(n.value, 42)
end)

runner.test("boolean true", function()
    local n = expr("true")
    assert.kind(n, "bool")
    assert.is_true(n.value)
end)

runner.test("null", function()
    local n = expr("null")
    assert.kind(n, "null")
end)

runner.test("variable", function()
    local n = expr("$foo")
    assert.kind(n, "var")
    assert.equal(n.name, "foo")
end)

runner.test("instance variable", function()
    local n = expr("@rank")
    assert.kind(n, "ivar")
    assert.equal(n.name, "rank")
end)

runner.test("function call", function()
    local n = expr("&greet")
    assert.kind(n, "func_call")
    assert.equal(n.name, "greet")
end)

runner.test("system variable", function()
    local n = expr("%chain")
    assert.kind(n, "sys")
    assert.equal(n.name, "chain")
end)

runner.test("addition", function()
    local n = expr("$a + $b")
    assert.kind(n, "binop")
    assert.equal(n.op, "+")
    assert.kind(n.left,  "var")
    assert.kind(n.right, "var")
end)

runner.test("operator precedence: * before +", function()
    local n = expr("$a + $b * $c")
    assert.kind(n, "binop")
    assert.equal(n.op, "+")
    assert.kind(n.right, "binop")
    assert.equal(n.right.op, "*")
end)

runner.test("unary not", function()
    local n = expr("!$foo")
    assert.kind(n, "unop")
    assert.equal(n.op, "!")
    assert.kind(n.operand, "var")
end)

runner.test("method call", function()
    local n = expr("$foo.bar")
    assert.kind(n, "method_call")
    assert.equal(n.name, "bar")
    assert.kind(n.object, "var")
end)

runner.test("chained method calls", function()
    local n = expr("$foo.bar.baz")
    assert.kind(n, "method_call")
    assert.equal(n.name, "baz")
    assert.kind(n.object, "method_call")
    assert.equal(n.object.name, "bar")
end)

runner.test("subscript", function()
    local n = expr("$foo['key']")
    assert.kind(n, "index")
    assert.kind(n.object, "var")
    assert.kind(n.key, "string")
    assert.equal(n.key.value, "key")
end)

runner.test("array literal", function()
    local n = expr("[1, 2, 3]")
    assert.kind(n, "array")
    assert.count(n.elements, 3)
end)

runner.test("hash literal bare keys", function()
    local n = expr("{name: 'Picard', rank: 'Captain'}")
    assert.kind(n, "hash")
    assert.count(n.pairs, 2)
    assert.equal(n.pairs[1].key.value, "name")
    assert.equal(n.pairs[2].key.value, "rank")
end)

runner.test("pipe operator", function()
    local n = expr("&foo | &bar")
    assert.kind(n, "pipe")
    assert.is_false(n.null_safe)
    assert.kind(n.left,  "func_call")
    assert.kind(n.right, "func_call")
end)

runner.test("null-safe pipe", function()
    local n = expr("&foo |& &bar")
    assert.kind(n, "pipe")
    assert.is_true(n.null_safe)
end)

runner.test("safe navigation", function()
    local n = expr("$foo&.bar")
    assert.kind(n, "safe_call")
    assert.kind(n.object, "var")
    assert.equal(n.name, "bar")
end)

runner.test("function call with positional args", function()
    local n = expr("&greet('hello', 42)")
    assert.kind(n, "func_call")
    assert.count(n.args, 2)
end)

runner.test("function call with keyword args", function()
    local n = expr("&promote(new_rank: 'Captain')")
    assert.kind(n, "func_call")
    assert.count(n.kwargs, 1)
    assert.equal(n.kwargs[1].key, "new_rank")
end)
