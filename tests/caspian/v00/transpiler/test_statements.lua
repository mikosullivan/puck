--[[
{
  "suite": "transpiler / statements",
  "covers": "assignments (setvar/setivar/[]=/ setter), func_def (setvar/setfunc/setremote/params/kwparams/body), return/yield, if/elsif/else, while, catch/heed, class decls, do-blocks, JSON sanity check"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local ks     = require("caspian")

--[[ { "in": "src: string", "out": "CaspianJ table  (all statements)", "note": "transpile helper; returns ks.transpile(src)" } ]]
local function tx(src)
    return ks.transpile(src)
end

--[[ { "in": "src: string", "out": "CaspianJ node  (first statement)", "note": "transpile helper; returns tx(src)[1]" } ]]
local function s1(src)
    return tx(src)[1]
end

runner.suite("transpiler / statements")

-- Assignments ------------------------------------------------------------

runner.test("setvar $name = expr", function()
    local s = s1("$x = 42")
    assert.equal(s[1], "scope")
    assert.equal(s[2], "setvar")
    assert.equal(s[3], "x")
    assert.equal(s[4].value, 42)
end)

runner.test("setivar @name = expr", function()
    local s = s1("@rank = 'Captain'")
    assert.equal(s[1], "scope")
    assert.equal(s[2], "setivar")
    assert.equal(s[3], "rank")
    assert.equal(s[4].value, "Captain")
end)

runner.test("index assignment []=", function()
    local s = s1("$foo['key'] = 42")
    assert.equal(s[1].var, "foo")
    assert.equal(s[2], "[]=")
    assert.equal(s[3].args[1].value, "key")
    assert.equal(s[3].args[2].value, 42)
end)

runner.test("setter method assignment", function()
    local s = s1("$foo.rank = 'Admiral'")
    assert.equal(s[1].var, "foo")
    assert.equal(s[2], "rank=")
    assert.equal(s[3].args[1].value, "Admiral")
end)

-- Function definitions ---------------------------------------------------

runner.test("function $name setvar", function()
    local s = s1("function $greet\nend")
    assert.equal(s[1], "scope")
    assert.equal(s[2], "setvar")
    assert.equal(s[3], "greet")
    assert.not_nil(s[4]["function"])
end)

runner.test("function &name setfunc", function()
    local s = s1("function &greet\nend")
    assert.equal(s[1], "scope")
    assert.equal(s[2], "setfunc")
    assert.equal(s[3], "greet")
end)

runner.test("remote function setremote", function()
    local s = s1("remote function &save\nend")
    assert.equal(s[2], "setremote")
end)

runner.test("function params in function table", function()
    local s = s1("function &greet($name, $rank)\nend")
    local fn = s[4]["function"]
    assert.count(fn.params, 2)
    assert.equal(fn.params[1], "name")
    assert.equal(fn.params[2], "rank")
end)

runner.test("function kwparams in function table", function()
    local s = s1("function &promote(new_rank:)\nend")
    local fn = s[4]["function"]
    assert.count(fn.kwparams, 1)
    assert.equal(fn.kwparams[1], "new_rank")
end)

runner.test("function body transpiled", function()
    local s = s1("function &double($x)\nreturn $x * 2\nend")
    local fn = s[4]["function"]
    assert.count(fn.body, 1)
    assert.equal(fn.body[1][1], "command")
    assert.equal(fn.body[1][2], "return")
end)

-- Return / yield ---------------------------------------------------------

runner.test("return with value", function()
    local s = s1("function $f\nreturn 42\nend")
    local ret = s[4]["function"].body[1]
    assert.equal(ret[1], "command")
    assert.equal(ret[2], "return")
    assert.equal(ret[3].value, 42)
end)

runner.test("yield with value", function()
    local s = s1("function &apply($v)\nyield $v\nend")
    local y = s[4]["function"].body[1]
    assert.equal(y[1], "command")
    assert.equal(y[2], "yield")
    assert.equal(y[3].var, "v")
end)

-- If statement -----------------------------------------------------------

runner.test("simple if", function()
    local s = s1("if ($x == 1)\nend")
    assert.equal(s[1], "command")
    assert.equal(s[2], "if")
    local cmd = s[3]
    assert.count(cmd.expressions, 1)
    assert.equal(cmd.expressions[1].when[2], "==")
    assert.count(cmd.expressions[1]["then"], 0)
end)

runner.test("if-else branches", function()
    local s = s1("if ($x == 1)\n$y = 2\nelse\n$y = 3\nend")
    local cmd = s[3]
    assert.count(cmd.expressions, 1)
    assert.count(cmd["else"], 1)
end)

runner.test("if-elsif-else branches", function()
    local s = s1("if ($x == 1)\nelsif ($x == 2)\nelse\nend")
    local cmd = s[3]
    assert.count(cmd.expressions, 2)
    assert.not_nil(cmd["else"])
end)

-- While ------------------------------------------------------------------

runner.test("while loop", function()
    local s = s1("while($i < 10)\n$i = $i + 1\nend")
    assert.equal(s[1], "command")
    assert.equal(s[2], "while")
    local cmd = s[3]
    assert.not_nil(cmd.cond)
    assert.equal(cmd.cond[2], "<")
    assert.count(cmd.body, 1)
end)

-- Catch / heed -----------------------------------------------------------

runner.test("catch assignment", function()
    local s = s1("$e = catch('some.error')\nend")
    assert.equal(s[1], "command")
    assert.equal(s[2], "catch")
    local cmd = s[3]
    assert.equal(cmd.target, "e")
    assert.count(cmd.classes, 1)
    assert.equal(cmd.classes[1].value, "some.error")
end)

runner.test("catch with empty parens", function()
    local s = s1("$e = catch()\nend")
    assert.equal(s[2], "catch")
    assert.count(s[3].classes, 0)
end)

runner.test("heed assignment", function()
    local s = s1("$w = heed('foo.com/warning')\nend")
    assert.equal(s[1], "command")
    assert.equal(s[2], "heed")
    local cmd = s[3]
    assert.equal(cmd.target, "w")
    assert.count(cmd.classes, 1)
end)

-- Class definitions ------------------------------------------------------

runner.test("empty class", function()
    local s = s1("class 'fleet.officer'\nend")
    assert.equal(s[1], "command")
    assert.equal(s[2], "class")
    assert.equal(s[3].uns, "fleet.officer")
    assert.count(s[3].body, 0)
end)

runner.test("class with inherits decl", function()
    local s = s1("class 'fleet.captain'\ninherits 'fleet.officer'\nend")
    local decl = s[3].body[1]
    assert.equal(decl.decl, "inherits")
    assert.equal(decl.uns, "fleet.officer")
end)

runner.test("class with field decl", function()
    local s = s1("class 'fleet.officer'\nfield :rank, class: :string\nend")
    local decl = s[3].body[1]
    assert.equal(decl.decl, "field")
    assert.equal(decl.name, "rank")
    assert.equal(decl.opts.class.value, "string")
end)

runner.test("class with abstract decl", function()
    local s = s1("class 'fleet.base'\nabstract true\nend")
    local decl = s[3].body[1]
    assert.equal(decl.decl, "abstract")
    assert.equal(decl.value, true)
end)

runner.test("class with join decl", function()
    local s = s1("class 'foo'\njoin :a, :b\nend")
    local decl = s[3].body[1]
    assert.equal(decl.decl, "join")
    assert.count(decl.fields, 2)
end)

runner.test("class with function decl", function()
    local s = s1("class 'foo'\nfunction &greet\nend\nend")
    local decl = s[3].body[1]
    assert.equal(decl.decl, "function")
    assert.equal(decl.name, "greet")
end)

-- Blocks -----------------------------------------------------------------

runner.test("do block attached to method call", function()
    local stmts = tx("$list.each do($x)\n$x.save\nend")
    local s = stmts[1]
    -- Block is on the method_call inside expr_stmt
    assert.equal(s[2], "each")
    local blk = s[3].block
    assert.not_nil(blk)
    assert.count(blk.params, 1)
    assert.equal(blk.params[1], "x")
    assert.count(blk.body, 1)
end)

runner.test("do block before/after clauses", function()
    local stmts = tx("$list.each do($x)\nbefore\n$n = 0\nafter\n$n.save\nend")
    local blk = stmts[1][3].block
    assert.not_nil(blk.before)
    assert.count(blk.before, 1)
    assert.not_nil(blk.after)
end)

runner.test("as implicit block name stored", function()
    local stmts = tx("$list.each($x) as $loop\n$x.save\nend")
    local s = stmts[1]
    local blk = s[3].block
    assert.not_nil(blk)
    assert.equal(blk.name, "loop")
end)

-- JSON serialisation sanity check ----------------------------------------

runner.test("to_json produces valid JSON string", function()
    local out = ks.to_json("$x = 42")
    assert.not_nil(out)
    -- Spot-check: contains the string
    assert.equal(out:find('"setvar"') ~= nil, true)
    assert.equal(out:find('"42"') == nil, true)   -- 42 should be a number, not string
    assert.equal(out:find('42') ~= nil, true)
end)
