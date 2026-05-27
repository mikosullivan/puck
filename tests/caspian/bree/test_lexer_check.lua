--[[
{
  "file":     "tests/caspian/bree/test_lexer_check.lua",
  "test_id":  "TB.0.1",
  "verifies": "Lexer tokenizes the bree fixture string 'hello'.to_string into string_literal, dot, identifier (in that order). Establishes the Phase-0 baseline.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local caspian = require("caspian")

runner.suite("bree / TB.0.1 lexer_check")

runner.test("lexer tokenizes 'hello'.to_string into 3 tokens: string, dot, identifier", function()
    local tokens = caspian.tokenize("'hello'.to_string")
    assert_.not_nil(tokens, "tokens is nil")

    -- Filter EOF tokens for clean comparison (most lexers append one).
    local kinds = {}
    for _, tok in ipairs(tokens) do
        if tok.type ~= "EOF" then
            kinds[#kinds + 1] = tok.type
        end
    end

    assert_.equal(#kinds, 3, "expected 3 non-EOF tokens, got " .. #kinds)
    assert_.equal(kinds[1], "STRING", "token 1 type")
    assert_.equal(kinds[2], "DOT",    "token 2 type")
    assert_.equal(kinds[3], "IDENT",  "token 3 type")

    -- Spot-check values.
    assert_.equal(tokens[1].value, "hello",     "token 1 value")
    assert_.equal(tokens[3].value, "to_string", "token 3 value")
end)
