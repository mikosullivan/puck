--[[
{
  "file":     "tests/caspian/bree/test_end_marker.lua",
  "test_id":  "TB.7",
  "verifies": "Lexer stops tokenizing at a bare __END__ line per caspian.md spec. Content after the marker is not tokenized; non-bare uses (mid-line, indented-only-as-trailing-whitespace, etc.) follow the spec's two rules.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local caspian = require("caspian")

runner.suite("bree / TB.7 end_marker")

local function last_non_eof(tokens)
    for i = #tokens, 1, -1 do
        if tokens[i].type ~= "EOF" then return tokens[i] end
    end
    return nil
end

local function has_token_value(tokens, value)
    for _, tok in ipairs(tokens) do
        if tok.value == value then return true end
    end
    return false
end

runner.test("bare __END__ on its own line stops tokenization", function()
    local src = "$foo = 'hello'\n__END__\nignored garbage that would otherwise lex-error @@@\n"
    local tokens = caspian.tokenize(src)
    -- After the assignment line + NEWLINE, the lexer should stop.
    -- 'ignored garbage' must NOT appear in any token value.
    assert_.is_false(has_token_value(tokens, "ignored"), "ignored content leaked into tokens")
    assert_.is_false(has_token_value(tokens, "garbage"), "garbage content leaked into tokens")
end)

runner.test("__END__ with trailing whitespace before newline still stops tokenization", function()
    local src = "$foo = 1\n__END__   \t\nignored\n"
    local tokens = caspian.tokenize(src)
    assert_.is_false(has_token_value(tokens, "ignored"), "content after __END__ should not be tokenized")
end)

runner.test("__END__ at end of file (no trailing newline) stops tokenization", function()
    local src = "$foo = 1\n__END__"
    local tokens = caspian.tokenize(src)
    -- No error; tokenization succeeds.
    assert_.not_nil(tokens, "tokens is nil")
end)

runner.test("__END__ not at start of line is treated as a normal identifier", function()
    local src = "$foo = bar __END__\n"
    -- Mid-line "__END__" should be an IDENT, not a terminator. With it as IDENT,
    -- the expression "bar __END__" is still parser-rejected, but the LEXER
    -- should produce tokens including __END__ as an identifier value.
    local tokens = caspian.tokenize(src)
    assert_.is_true(has_token_value(tokens, "__END__"), "mid-line __END__ should be tokenized as IDENT")
end)

runner.test("__END__ inside a string literal is just text", function()
    local src = "$foo = '__END__'\nbar"
    local tokens = caspian.tokenize(src)
    -- 'bar' should still appear — the __END__ inside the string didn't terminate.
    assert_.is_true(has_token_value(tokens, "bar"), "tokenization should continue past __END__-inside-string")
    assert_.is_true(has_token_value(tokens, "__END__"), "the string literal value should be '__END__'")
end)

runner.test("__END__ at start of input (no prior tokens) stops tokenization", function()
    local src = "__END__\nignored\n"
    local tokens = caspian.tokenize(src)
    assert_.is_false(has_token_value(tokens, "ignored"), "content after __END__ should not be tokenized")
end)
