--[[
{
  "suite": "parser / functions",
  "covers": "func_def ($name/&name/remote), params, kwparams, body, return, yield, anonymous func_expr, no-paren IDENT calls"
}
]]
local runner = require("tests.support.runner")
local assert = require("tests.support.assert")
local ks     = require("kscript")

--[[ { "in": "src: string", "out": "AST node  (first statement)", "note": "parse helper; returns ast.stmts[1]" } ]]
local function stmt(src)
    local ast = ks.parse(src)
    return ast.stmts[1]
end

runner.suite("parser / functions")

runner.test("function $name", function()
    local n = stmt("function $greet\nend")
    assert.kind(n, "func_def")
    assert.equal(n.name, "greet")
    assert.equal(n.name_type, "var")
    assert.is_false(n.remote)
end)

runner.test("function &name", function()
    local n = stmt("function &format\nend")
    assert.kind(n, "func_def")
    assert.equal(n.name, "format")
    assert.equal(n.name_type, "func")
end)

runner.test("function with positional params", function()
    local n = stmt("function $greet($name, $rank)\nend")
    assert.kind(n, "func_def")
    assert.count(n.params, 2)
    assert.equal(n.params[1], "name")
    assert.equal(n.params[2], "rank")
end)

runner.test("function with keyword params", function()
    local n = stmt("function $promote(new_rank:)\nend")
    assert.kind(n, "func_def")
    assert.count(n.kwparams, 1)
    assert.equal(n.kwparams[1], "new_rank")
end)

runner.test("function with body", function()
    local n = stmt("function $greet($name)\n$result = 'hi'\nend")
    assert.kind(n, "func_def")
    assert.count(n.body, 1)
    assert.kind(n.body[1], "assign")
end)

runner.test("remote function", function()
    local n = stmt("remote function &save\nend")
    assert.kind(n, "func_def")
    assert.is_true(n.remote)
    assert.equal(n.name, "save")
end)

runner.test("anonymous function expression", function()
    local n = stmt("$f = function($x)\nend")
    assert.kind(n, "assign")
    assert.kind(n.value, "func_expr")
    assert.count(n.value.params, 1)
    assert.equal(n.value.params[1], "x")
end)

runner.test("empty params list", function()
    local n = stmt("function $hello()\nend")
    assert.kind(n, "func_def")
    assert.count(n.params, 0)
    assert.count(n.kwparams, 0)
end)

runner.test("function with return", function()
    local n = stmt("function $double($x)\nreturn $x * 2\nend")
    assert.kind(n, "func_def")
    assert.count(n.body, 1)
    assert.kind(n.body[1], "return_stmt")
    assert.kind(n.body[1].value, "binop")
end)

runner.test("yield with value", function()
    local n = stmt("function &apply($value)\nyield $value\nend")
    assert.kind(n, "func_def")
    assert.count(n.body, 1)
    assert.kind(n.body[1], "yield_stmt")
    assert.kind(n.body[1].value, "var")
end)

runner.test("yield with subscript", function()
    local n = stmt("function &gen\nyield %blocks[0]\nend")
    assert.kind(n, "func_def")
    assert.kind(n.body[1], "yield_stmt")
    assert.kind(n.body[1].value, "index")
end)

runner.test("no-paren call: ident followed by func arg", function()
    local n = stmt("puts &greet('Picard')")
    assert.kind(n, "expr_stmt")
    assert.kind(n.expr, "call")
    assert.equal(n.expr.callee.name, "puts")
    assert.count(n.expr.args, 1)
    assert.kind(n.expr.args[1], "func_call")
end)

runner.test("no-paren call: ident followed by var arg", function()
    local n = stmt("puts $v")
    assert.kind(n, "expr_stmt")
    assert.kind(n.expr, "call")
    assert.equal(n.expr.callee.name, "puts")
    assert.kind(n.expr.args[1], "var")
    assert.equal(n.expr.args[1].name, "v")
end)
