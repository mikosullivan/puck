--[[
{
  "suite": "lexer / sigils",
  "covers": "VAR ($), VAROBJ ($$), IVAR (@), FUNC (&), SAFENAV (&.), SYS (%), && vs &, |& pipe-safe"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local lexer  = require("kscript.lexer")
local T      = lexer.T

--[[ { "in": "src: string", "out": "token  (first token in the stream)", "note": "lex helper; returns tokens[1] — sufficient for single-sigil assertions" } ]]
local function first(src)
    local tokens = lexer.tokenize(src)
    return tokens[1]
end

runner.suite("lexer / sigils")

runner.test("$var", function()
    local t = first("$foo")
    assert.equal(t.type,  T.VAR)
    assert.equal(t.value, "foo")
end)

runner.test("$$varobj", function()
    local t = first("$$foo")
    assert.equal(t.type,  T.VAROBJ)
    assert.equal(t.value, "foo")
end)

runner.test("@ivar", function()
    local t = first("@rank")
    assert.equal(t.type,  T.IVAR)
    assert.equal(t.value, "rank")
end)

runner.test("&func", function()
    local t = first("&greet")
    assert.equal(t.type,  T.FUNC)
    assert.equal(t.value, "greet")
end)

runner.test("&. safe navigation", function()
    local t = first("&.")
    assert.equal(t.type,  T.SAFENAV)
    assert.equal(t.value, "&.")
end)

runner.test("%sys", function()
    local t = first("%chain")
    assert.equal(t.type,  T.SYS)
    assert.equal(t.value, "chain")
end)

runner.test("&& is AND operator not two funcs", function()
    local tokens = lexer.tokenize("$a && $b")
    local ops = {}
    for _, t in ipairs(tokens) do
        if t.type == T.OP then ops[#ops + 1] = t end
    end
    assert.count(ops, 1)
    assert.equal(ops[1].value, "&&")
end)

runner.test("|& is PIPESAFE", function()
    local tokens = lexer.tokenize("&foo |& &bar")
    local ops = {}
    for _, t in ipairs(tokens) do
        if t.type == T.OP then ops[#ops + 1] = t end
    end
    assert.count(ops, 1)
    assert.equal(ops[1].value, "|&")
end)

runner.test("$var with subscript tokenises correctly", function()
    local tokens = lexer.tokenize("$foo['key']")
    local types = {}
    for _, t in ipairs(tokens) do
        if t.type ~= T.NEWLINE and t.type ~= T.EOF then
            types[#types + 1] = t.type
        end
    end
    assert.equal(types[1], T.VAR)
    assert.equal(types[2], T.LBRACK)
    assert.equal(types[3], T.STRING)
    assert.equal(types[4], T.RBRACK)
end)
