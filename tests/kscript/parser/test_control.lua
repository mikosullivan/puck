--[[
{
  "suite": "parser / control flow",
  "covers": "if_stmt (simple, body, else, elsif, elsif+else), do-blocks (no params, params, body, before, after), as implicit blocks",
  "note": "do-blocks attach to the method_call node inside expr_stmt; access via n.expr.block, not n.block"
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

runner.suite("parser / control flow")

runner.test("simple if", function()
    local n = stmt("if ($x == 1)\nend")
    assert.kind(n, "if_stmt")
    assert.kind(n.cond, "binop")
    assert.equal(n.cond.op, "==")
    assert.count(n.then_body, 0)
end)

runner.test("if with body", function()
    local n = stmt("if ($x == 1)\n$y = 2\nend")
    assert.kind(n, "if_stmt")
    assert.count(n.then_body, 1)
    assert.kind(n.then_body[1], "assign")
end)

runner.test("if-else", function()
    local n = stmt("if ($x == 1)\n$y = 2\nelse\n$y = 3\nend")
    assert.kind(n, "if_stmt")
    assert.count(n.then_body, 1)
    assert.not_nil(n.else_body)
    assert.count(n.else_body, 1)
end)

runner.test("if-elsif", function()
    local n = stmt("if ($x == 1)\nelsif ($x == 2)\n$y = 9\nend")
    assert.kind(n, "if_stmt")
    assert.count(n.elsifs, 1)
    assert.kind(n.elsifs[1].cond, "binop")
    assert.count(n.elsifs[1].body, 1)
end)

runner.test("if-elsif-else", function()
    local n = stmt("if ($x == 1)\nelsif ($x == 2)\nelse\nend")
    assert.kind(n, "if_stmt")
    assert.count(n.elsifs, 1)
    assert.not_nil(n.else_body)
end)

-- do-blocks parsed via parse_postfix attach the block to the method_call node,
-- not the enclosing expr_stmt. Access via n.expr.block.
runner.test("do block with no params", function()
    local n = stmt("$list.each do\nend")
    assert.kind(n, "expr_stmt")
    local blk = n.expr.block
    assert.not_nil(blk)
    assert.count(blk.params, 0)
end)

runner.test("do block with params", function()
    local n = stmt("$list.each do($item)\nend")
    assert.kind(n, "expr_stmt")
    local blk = n.expr.block
    assert.not_nil(blk)
    assert.count(blk.params, 1)
    assert.equal(blk.params[1], "item")
end)

runner.test("do block with body", function()
    local n = stmt("$list.each do($x)\n$x.save\nend")
    local blk = n.expr.block
    assert.count(blk.body, 1)
    assert.kind(blk.body[1], "expr_stmt")
end)

runner.test("do block with before clause", function()
    local n = stmt("$list.each do($x)\nbefore\n$total = 0\nend")
    local blk = n.expr.block
    assert.not_nil(blk.before)
    assert.count(blk.before, 1)
end)

runner.test("do block with after clause", function()
    local n = stmt("$list.each do($x)\nafter\n$total.save\nend")
    local blk = n.expr.block
    assert.not_nil(blk.after)
    assert.count(blk.after, 1)
end)

-- 'as $name' implicit blocks: block is on expr_stmt directly
runner.test("as implicit block", function()
    local n = stmt("$list.each($item) as $loop\n$item.save\nend")
    assert.kind(n, "expr_stmt")
    assert.not_nil(n.block)
    assert.equal(n.block.name, "loop")
    assert.count(n.block.body, 1)
end)
