--[[
{
  "suite": "lexer / literals",
  "covers": "strings (single/double-quoted, heredoc), numbers (integer/float), booleans, null, symbols, comments"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local lexer  = require("kscript.lexer")
local T      = lexer.T

--[[ { "in": "src: string", "out": "token[]  (NEWLINE and EOF stripped)", "note": "lex helper; returns only meaningful tokens" } ]]
local function tok(src)
    local tokens = lexer.tokenize(src)
    -- strip trailing NEWLINE and EOF
    local out = {}
    for _, t in ipairs(tokens) do
        if t.type ~= T.NEWLINE and t.type ~= T.EOF then
            out[#out + 1] = t
        end
    end
    return out
end

runner.suite("lexer / literals")

runner.test("single-quoted string", function()
    local t = tok("'hello world'")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.STRING)
    assert.equal(t[1].value, "hello world")
end)

runner.test("single-quoted escape sequences", function()
    local t = tok([['line\nnewline']])
    assert.equal(t[1].value, "line\nnewline")
end)

runner.test("double-quoted string", function()
    local t = tok('"hello"')
    assert.count(t, 1)
    assert.equal(t[1].type,  T.STRING)
    assert.equal(t[1].value, "hello")
end)

runner.test("symbol is STRING token", function()
    local t = tok(":foo")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.SYMBOL)
    assert.equal(t[1].value, "foo")
end)

runner.test("integer", function()
    local t = tok("42")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.NUMBER)
    assert.equal(t[1].value, 42)
end)

runner.test("float", function()
    local t = tok("3.14")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.NUMBER)
    assert.equal(t[1].value, 3.14)
end)

runner.test("true", function()
    local t = tok("true")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.BOOL)
    assert.is_true(t[1].value)
end)

runner.test("false", function()
    local t = tok("false")
    assert.count(t, 1)
    assert.equal(t[1].type,  T.BOOL)
    assert.is_false(t[1].value)
end)

runner.test("null", function()
    local t = tok("null")
    assert.count(t, 1)
    assert.equal(t[1].type, T.NULL)
end)

runner.test("heredoc single-quoted", function()
    local src = "<<'EOF'\n    hello\nEOF"
    local t = tok(src)
    assert.count(t, 1)
    assert.equal(t[1].type,  T.STRING)
    assert.equal(t[1].value, "hello")
end)

runner.test("heredoc strips common indent", function()
    local src = "<<'EOF'\n    line one\n    line two\nEOF"
    local t = tok(src)
    assert.equal(t[1].value, "line one\nline two")
end)

runner.test("comment produces no tokens", function()
    local t = tok("# this is a comment")
    assert.count(t, 0)
end)

runner.test("comment does not consume next line", function()
    local tokens = lexer.tokenize("# comment\n$foo")
    local non_meta = {}
    for _, t in ipairs(tokens) do
        if t.type ~= T.EOF then non_meta[#non_meta + 1] = t end
    end
    -- NEWLINE then VAR
    assert.equal(non_meta[1].type, T.NEWLINE)
    assert.equal(non_meta[2].type, T.VAR)
    assert.equal(non_meta[2].value, "foo")
end)
