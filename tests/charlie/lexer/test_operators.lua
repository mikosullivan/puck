--[[
{
  "suite": "lexer / operators",
  "covers": "all OP tokens (==, !=, <, >, <=, >=, &&, ||, !, +, -, *, /, |, |&), ASSIGN (=), ROCKET (=>), COLON (:), SYMBOL (:name)"
}
]]
local runner = require("support.runner")
local assert = require("support.assert")
local lexer  = require("charlie.lexer")
local T      = lexer.T

--[[ { "in": "src: string", "out": "string[]  (values of OP/ASSIGN/ROCKET tokens only)", "note": "filters token stream down to operator values for concise assertions" } ]]
local function ops(src)
    local out = {}
    for _, t in ipairs(lexer.tokenize(src)) do
        if t.type == T.OP or t.type == T.ASSIGN or t.type == T.ROCKET then
            out[#out + 1] = t.value
        end
    end
    return out
end

runner.suite("lexer / operators")

local cases = {
    { "==", "==" }, { "!=", "!=" },
    { "<=", "<=" }, { ">=", ">=" },
    { "<",  "<"  }, { ">",  ">"  },
    { "&&", "&&" }, { "||", "||" },
    { "!",  "!"  },
    { "+",  "+"  }, { "-",  "-"  },
    { "*",  "*"  }, { "/",  "/"  },
    { "|",  "|"  }, { "|&", "|&" },
}

for _, c in ipairs(cases) do
    local src, expected = c[1], c[2]
    runner.test(src, function()
        local got = ops(src)
        assert.count(got, 1)
        assert.equal(got[1], expected)
    end)
end

runner.test("= is ASSIGN not OP", function()
    local tokens = lexer.tokenize("$x = 1")
    local assigns = {}
    for _, t in ipairs(tokens) do
        if t.type == T.ASSIGN then assigns[#assigns + 1] = t end
    end
    assert.count(assigns, 1)
end)

runner.test("=> is ROCKET", function()
    local tokens = lexer.tokenize(":foo => 'bar'")
    local rockets = {}
    for _, t in ipairs(tokens) do
        if t.type == T.ROCKET then rockets[#rockets + 1] = t end
    end
    assert.count(rockets, 1)
end)

runner.test(": before letter is SYMBOL not COLON", function()
    local tokens = lexer.tokenize(":foo")
    assert.equal(tokens[1].type, T.SYMBOL)
end)

runner.test(": before space is COLON not SYMBOL", function()
    local tokens = lexer.tokenize("foo: bar")
    -- foo IDENT, : COLON, bar IDENT
    local colon
    for _, t in ipairs(tokens) do
        if t.type == T.COLON then colon = t end
    end
    assert.not_nil(colon)
end)
