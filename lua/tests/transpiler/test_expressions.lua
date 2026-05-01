--[[
{
  "suite": "transpiler / expressions",
  "covers": "all literal types, variable refs ($/@/$$/%/self), array/hash, binop/unop, method_call, func_call, subscript, pipe, safe_call, untrusted, anonymous function"
}
]]
local runner = require("tests.support.runner")
local assert = require("tests.support.assert")
local ks     = require("kscript")

--[[ { "in": "src: string", "out": "KScriptJSON node  (first statement)", "note": "transpile helper; returns ks.transpile(src)[1]" } ]]
local function tx(src)
    local stmts = ks.transpile(src)
    return stmts[1]
end

runner.suite("transpiler / expressions")

-- Literals ---------------------------------------------------------------

runner.test("integer literal", function()
    local n = tx("42")
    assert.equal(n.value, 42)
end)

runner.test("float literal", function()
    local n = tx("3.14")
    assert.equal(n.value, 3.14)
end)

runner.test("string literal", function()
    local n = tx("'hello'")
    assert.equal(n.value, "hello")
end)

runner.test("boolean true", function()
    local n = tx("true")
    assert.equal(n.value, true)
end)

runner.test("boolean false", function()
    local n = tx("false")
    assert.equal(n.value, false)
end)

runner.test("null literal", function()
    local n = tx("null")
    assert.equal(n.value, ks.null)
end)

runner.test("symbol is string", function()
    local n = tx(":foo")
    assert.equal(n.value, "foo")
end)

-- Variable references ----------------------------------------------------

runner.test("$var reference", function()
    local n = tx("$foo")
    assert.equal(n.var, "foo")
end)

runner.test("@ivar reference", function()
    local n = tx("@rank")
    assert.equal(n.ivar, "rank")
end)

runner.test("$$varobj reference", function()
    local n = tx("$$foo")
    assert.equal(n.varobj, "foo")
end)

runner.test("%sys reference", function()
    local n = tx("%chain")
    assert.equal(n.sys, "chain")
end)

-- Collections ------------------------------------------------------------

runner.test("array literal", function()
    local n = tx("[1, 2, 3]")
    assert.not_nil(n.array)
    assert.count(n.array, 3)
    assert.equal(n.array[1].value, 1)
    assert.equal(n.array[3].value, 3)
end)

runner.test("hash literal bare keys", function()
    local n = tx("{name: 'Picard', rank: 'Captain'}")
    assert.not_nil(n.hash)
    assert.equal(n.hash.name.value, "Picard")
    assert.equal(n.hash.rank.value, "Captain")
end)

-- Operators (method calls) -----------------------------------------------

runner.test("addition binop", function()
    local n = tx("$a + $b")
    assert.equal(n[1].var, "a")
    assert.equal(n[2], "+")
    assert.equal(n[3].args[1].var, "b")
end)

runner.test("comparison binop", function()
    local n = tx("$x == 1")
    assert.equal(n[2], "==")
    assert.equal(n[3].args[1].value, 1)
end)

runner.test("unary not", function()
    local n = tx("!$foo")
    assert.equal(n[1].var, "foo")
    assert.equal(n[2], "!")
end)

-- Method calls -----------------------------------------------------------

runner.test("method call no args", function()
    local n = tx("$foo.save")
    assert.equal(n[1].var, "foo")
    assert.equal(n[2], "save")
    assert.is_nil(n[3])
end)

runner.test("method call with kwargs", function()
    local n = tx("$foo.greet(name: 'Jean-Luc')")
    assert.equal(n[2], "greet")
    assert.equal(n[3].kwargs.name.value, "Jean-Luc")
end)

runner.test("method call with positional arg", function()
    local n = tx("$foo.bar('hello')")
    assert.equal(n[2], "bar")
    assert.equal(n[3].args[1].value, "hello")
end)

runner.test("chained method calls", function()
    local n = tx("$foo.bar.baz")
    assert.equal(n[2], "baz")
    assert.equal(n[1][2], "bar")  -- inner call
    assert.equal(n[1][1].var, "foo")
end)

-- Function calls ---------------------------------------------------------

runner.test("bare function call &greet", function()
    local n = tx("&greet")
    assert.equal(n[1].var, "greet")
    assert.equal(n[2], "&")
    assert.is_nil(n[3])
end)

runner.test("function call with positional args", function()
    local n = tx("&greet('hello', 42)")
    assert.equal(n[2], "&")
    assert.equal(n[3].args[1].value, "hello")
    assert.equal(n[3].args[2].value, 42)
end)

runner.test("function call with kwargs", function()
    local n = tx("&promote(new_rank: 'Captain')")
    assert.equal(n[3].kwargs.new_rank.value, "Captain")
end)

-- Subscript --------------------------------------------------------------

runner.test("subscript index", function()
    local n = tx("$foo['key']")
    assert.equal(n[1].var, "foo")
    assert.equal(n[2], "[]")
    assert.equal(n[3].args[1].value, "key")
end)

-- Pipe -------------------------------------------------------------------

runner.test("pipe chain", function()
    local n = tx("&foo | &bar | &baz")
    assert.not_nil(n.pipe)
    assert.count(n.pipe.stages, 3)
    assert.equal(n.pipe.null_safe, false)
    assert.equal(n.pipe.stages[1][1].var, "foo")
    assert.equal(n.pipe.stages[2][1].var, "bar")
    assert.equal(n.pipe.stages[3][1].var, "baz")
end)

runner.test("null-safe pipe", function()
    local n = tx("&foo |& &bar")
    assert.not_nil(n.pipe)
    assert.equal(n.pipe.null_safe, true)
end)

-- Safe navigation --------------------------------------------------------

runner.test("safe navigation &.", function()
    local n = tx("$foo&.bar")
    assert.not_nil(n.safe)
    assert.equal(n.safe.recv.var, "foo")
    assert.equal(n.safe.method, "bar")
end)

-- Untrusted --------------------------------------------------------------

runner.test("untrusted()", function()
    local n = tx("untrusted($foo)")
    assert.not_nil(n.untrusted)
    assert.equal(n.untrusted.var, "foo")
end)

-- Anonymous function -----------------------------------------------------

runner.test("anonymous function expression", function()
    local n = tx("$f = function($x)\nend")
    -- The outer statement is setvar
    local stmts = ks.transpile("$f = function($x)\nend")
    local s = stmts[1]
    assert.equal(s[1], "scope")
    assert.equal(s[2], "setvar")
    assert.equal(s[3], "f")
    assert.not_nil(s[4]["function"])
    assert.count(s[4]["function"].params, 1)
end)
