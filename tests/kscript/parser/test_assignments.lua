--[[
{
  "suite": "parser / assignments",
  "covers": "assign node: $var, @ivar, binop rhs, func_call rhs, method_call rhs, null rhs, catch assignment, multiple stmts"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local ks     = require("kscript")

--[[ { "in": "src: string", "out": "AST node  (first statement)", "note": "parse helper; returns ast.stmts[1]" } ]]
local function stmt(src)
    local ast = ks.parse(src)
    return ast.stmts[1]
end

runner.suite("parser / assignments")

runner.test("simple assignment", function()
    local n = stmt("$x = 42")
    assert.kind(n, "assign")
    assert.kind(n.target, "var")
    assert.equal(n.target.name, "x")
    assert.kind(n.value, "number")
    assert.equal(n.value.value, 42)
end)

runner.test("assign string", function()
    local n = stmt("$x = 'hello'")
    assert.kind(n, "assign")
    assert.kind(n.value, "string")
    assert.equal(n.value.value, "hello")
end)

runner.test("assign binop expression", function()
    local n = stmt("$x = $a + $b")
    assert.kind(n, "assign")
    assert.kind(n.value, "binop")
    assert.equal(n.value.op, "+")
end)

runner.test("assign ivar", function()
    local n = stmt("@rank = 'Captain'")
    assert.kind(n, "assign")
    assert.kind(n.target, "ivar")
    assert.equal(n.target.name, "rank")
end)

runner.test("assign func call result", function()
    local n = stmt("$x = &greet()")
    assert.kind(n, "assign")
    assert.kind(n.value, "func_call")
    assert.equal(n.value.name, "greet")
end)

runner.test("assign method call result", function()
    local n = stmt("$x = $foo.bar")
    assert.kind(n, "assign")
    assert.kind(n.value, "method_call")
    assert.equal(n.value.name, "bar")
end)

runner.test("assign null", function()
    local n = stmt("$x = null")
    assert.kind(n, "assign")
    assert.kind(n.value, "null")
end)

runner.test("catch assignment", function()
    local n = stmt("$x = catch('some.error')\nend")
    assert.kind(n, "catch_stmt")
    assert.kind(n.target, "var")
    assert.equal(n.target.name, "x")
    assert.count(n.classes, 1)
    assert.equal(n.classes[1].value, "some.error")
end)

runner.test("multiple assignments are independent stmts", function()
    local ast = ks.parse("$x = 1\n$y = 2")
    assert.count(ast.stmts, 2)
    assert.kind(ast.stmts[1], "assign")
    assert.kind(ast.stmts[2], "assign")
end)
