--[[
{
  "module": "kscript.lexer",
  "role": "Tokenizer for KScript source — converts a source string to a flat token array",
  "exports": {
    "tokenize": "string → token[]",
    "T":        "token-type constants (VAR, VAROBJ, IVAR, FUNC, SAFENAV, SYS, SYMBOL, STRING, NUMBER, BOOL, NULL, IDENT, OP, ASSIGN, ROCKET, LPAREN, RPAREN, LBRACK, RBRACK, LBRACE, RBRACE, COMMA, DOT, COLON, NEWLINE, EOF)"
  },
  "token_shape": "{type: string, value: any, line: number, col: number}",
  "sigil_map": {"$": "VAR", "$$": "VAROBJ", "@": "IVAR", "&name": "FUNC", "&.": "SAFENAV", "%": "SYS", ":name": "SYMBOL", ":": "COLON"},
  "name_suffixes": "trailing ? always consumed into the name; trailing ! consumed unless followed by ="
}
]]
local M = {}

-- Token types
M.T = {
    VAR      = "VAR",      -- $name
    VAROBJ   = "VAROBJ",   -- $$name
    IVAR     = "IVAR",     -- @name
    FUNC     = "FUNC",     -- &name
    SAFENAV  = "SAFENAV",  -- &.
    SYS      = "SYS",      -- %name
    SYMBOL   = "SYMBOL",   -- :name (shorthand for string 'name')
    STRING   = "STRING",
    NUMBER   = "NUMBER",
    BOOL     = "BOOL",
    NULL     = "NULL",
    IDENT    = "IDENT",    -- bare word; keywords share this type, distinguished by value
    OP       = "OP",       -- ==  !=  <  >  <=  >=  &&  ||  !  +  -  *  /  |  |&
    ASSIGN   = "ASSIGN",   -- =
    ROCKET   = "ROCKET",   -- =>
    LPAREN   = "LPAREN",
    RPAREN   = "RPAREN",
    LBRACK   = "LBRACK",
    RBRACK   = "RBRACK",
    LBRACE   = "LBRACE",
    RBRACE   = "RBRACE",
    COMMA    = "COMMA",
    DOT      = "DOT",
    COLON    = "COLON",    -- standalone : (hash rocket and keyword-arg separator)
    NEWLINE  = "NEWLINE",
    EOF      = "EOF",
}

local T = M.T

--[[ { "in": "source: string", "out": "lexer object  (call :run() to tokenize)", "note": "factory; creates the lexer state and all inner closures" } ]]
local function new_lexer(source)
    local lx = { source = source, pos = 1, line = 1, col = 1, tokens = {} }

    --[[ { "out": "string  (current character, or '' at EOF)" } ]]
    local function cur()      return lx.source:sub(lx.pos, lx.pos) end
    --[[ { "in": "n: number  (offset from current position)", "out": "string  (character at pos+n)" } ]]
    local function look(n)    return lx.source:sub(lx.pos + n, lx.pos + n) end

    --[[ { "out": "string  (the character consumed)", "note": "advances pos; updates line/col counters" } ]]
    local function advance()
        local c = lx.source:sub(lx.pos, lx.pos)
        lx.pos = lx.pos + 1
        if c == "\n" then lx.line = lx.line + 1; lx.col = 1
        else               lx.col = lx.col + 1 end
        return c
    end

    --[[ { "in": {"typ": "string (token type)", "val": "any"}, "note": "appends a token at current line/col to lx.tokens" } ]]
    local function push(typ, val)
        lx.tokens[#lx.tokens + 1] = { type = typ, value = val, line = lx.line, col = lx.col }
    end

    --[[ { "out": "string  (identifier including optional trailing ?/!)", "note": "consumes [%w_]+ then ? or ! (if ! not followed by =)" } ]]
    local function read_name()
        local s = {}
        while cur():match("[%w_]") do s[#s + 1] = advance() end
        -- Allow trailing ? (predicate methods: match?, active?)
        -- Allow trailing ! only when not followed by = (bang methods: save!, but != is an op)
        if cur() == "?" then
            s[#s + 1] = advance()
        elseif cur() == "!" and look(1) ~= "=" then
            s[#s + 1] = advance()
        end
        return table.concat(s)
    end

    --[[ { "out": "string  (unescaped contents of '...')", "note": "handles \\n \\t \\\\ \\'; other backslash sequences kept verbatim" } ]]
    local function read_single_quoted()
        advance()  -- opening '
        local s = {}
        while lx.pos <= #lx.source do
            local c = cur()
            if c == "'" then advance(); break
            elseif c == "\\" then
                advance()
                local e = advance()
                if     e == "n"  then s[#s+1] = "\n"
                elseif e == "t"  then s[#s+1] = "\t"
                elseif e == "\\" then s[#s+1] = "\\"
                elseif e == "'"  then s[#s+1] = "'"
                else                   s[#s+1] = "\\" .. e end
            else s[#s+1] = advance() end
        end
        return table.concat(s)
    end

    --[[ { "out": "string  (raw contents of \"...\")", "note": "handles \\n \\t \\\" \\\\; interpolation ($var/#{expr}) stored raw for the evaluator" } ]]
    local function read_double_quoted()
        advance()  -- opening "
        local s = {}
        while lx.pos <= #lx.source do
            local c = cur()
            if c == '"' then advance(); break
            elseif c == "\\" then
                advance()
                local e = advance()
                if     e == "n"  then s[#s+1] = "\n"
                elseif e == "t"  then s[#s+1] = "\t"
                elseif e == '"'  then s[#s+1] = '"'
                elseif e == "\\" then s[#s+1] = "\\"
                else                   s[#s+1] = "\\" .. e end
            else s[#s+1] = advance() end
        end
        return table.concat(s)
    end

    --[[
    {
      "out": "string  (heredoc body with common indent stripped)",
      "forms": {"<<'LABEL'": "no interpolation", "<<\"LABEL\"": "interpolated (stored raw)", "<<LABEL": "no interpolation"},
      "note": "called after the first < is consumed; strips common leading whitespace; trims trailing blank lines"
    }
    ]]
    local function read_heredoc()
        advance()  -- second <
        local c = cur()
        local label, interpolated

        if c == "'" then
            advance()
            local parts = {}
            while cur() ~= "'" do parts[#parts+1] = advance() end
            advance()
            label, interpolated = table.concat(parts), false
        elseif c == '"' then
            advance()
            local parts = {}
            while cur() ~= '"' do parts[#parts+1] = advance() end
            advance()
            label, interpolated = table.concat(parts), true
        elseif c:match("[%a_]") then
            label, interpolated = read_name(), false
        else
            error(string.format("Invalid heredoc syntax at line %d", lx.line))
        end

        -- Skip to end of opening line
        while lx.pos <= #lx.source and cur() ~= "\n" do advance() end
        if cur() == "\n" then advance() end

        -- Collect lines until label appears alone on its own line
        local lines = {}
        while lx.pos <= #lx.source do
            if lx.source:sub(lx.pos, lx.pos + #label - 1) == label then
                local after = lx.source:sub(lx.pos + #label, lx.pos + #label)
                if after == "\n" or after == "" then
                    lx.pos = lx.pos + #label
                    if cur() == "\n" then advance() end
                    break
                end
            end
            local line = {}
            while lx.pos <= #lx.source and cur() ~= "\n" do line[#line+1] = advance() end
            if cur() == "\n" then advance() end
            lines[#lines+1] = table.concat(line)
        end

        -- Strip common leading whitespace
        local min_indent = math.huge
        for _, ln in ipairs(lines) do
            if ln:match("%S") then  -- ignore blank lines for indent calculation
                local indent = #(ln:match("^(%s*)"))
                if indent < min_indent then min_indent = indent end
            end
        end
        if min_indent == math.huge then min_indent = 0 end

        local stripped = {}
        for _, ln in ipairs(lines) do
            stripped[#stripped+1] = ln:sub(min_indent + 1)
        end
        -- Trim trailing blank lines
        while #stripped > 0 and stripped[#stripped]:match("^%s*$") do
            stripped[#stripped] = nil
        end

        return table.concat(stripped, "\n")
    end

    --[[ { "out": "number  (Lua number)", "note": "consumes digits; if followed by '.' then digit, consumes float part; parsed with tonumber()" } ]]
    local function read_number()
        local s = {}
        while cur():match("[%d]") do s[#s+1] = advance() end
        if cur() == "." and look(1):match("[%d]") then
            s[#s+1] = advance()
            while cur():match("[%d]") do s[#s+1] = advance() end
        end
        return tonumber(table.concat(s))
    end

    --[[ { "out": "token[]", "note": "main tokenizer loop; consumes entire source, pushes tokens, appends EOF; returns lx.tokens" } ]]
    function lx:run()
        while lx.pos <= #lx.source do
            local c = cur()

            if     c == " " or c == "\t" or c == "\r" then advance()
            elseif c == "\n" then advance(); push(T.NEWLINE, "\n")

            -- Comments (not #{) — skip to end of line
            elseif c == "#" then
                while lx.pos <= #lx.source and cur() ~= "\n" do advance() end

            -- Heredoc must be checked before lone <
            elseif c == "<" and look(1) == "<" then
                advance()  -- first <
                push(T.STRING, read_heredoc())

            elseif c == "'" then push(T.STRING, read_single_quoted())
            elseif c == '"' then push(T.STRING, read_double_quoted())

            -- $var  $$varobj
            elseif c == "$" then
                advance()
                if cur() == "$" then advance(); push(T.VAROBJ, read_name())
                else                             push(T.VAR,    read_name()) end

            -- @ivar
            elseif c == "@" then advance(); push(T.IVAR, read_name())

            -- &name  &.  &&
            elseif c == "&" then
                advance()
                if     cur() == "&" then advance(); push(T.OP,      "&&")
                elseif cur() == "." then advance(); push(T.SAFENAV, "&.")
                else                               push(T.FUNC,    read_name()) end

            -- %sys
            elseif c == "%" then advance(); push(T.SYS, read_name())

            -- :symbol  or standalone :
            elseif c == ":" then
                advance()
                if cur():match("[%a_]") then push(T.SYMBOL, read_name())
                else                         push(T.COLON,  ":") end

            -- Numbers
            elseif c:match("[%d]") then push(T.NUMBER, read_number())

            -- Identifiers and keywords
            elseif c:match("[%a_]") then
                local name = read_name()
                if     name == "true"  then push(T.BOOL, true)
                elseif name == "false" then push(T.BOOL, false)
                elseif name == "null"  then push(T.NULL, nil)
                else                        push(T.IDENT, name) end

            -- Operators
            elseif c == "=" then
                advance()
                if     cur() == "=" then advance(); push(T.OP,     "==")
                elseif cur() == ">" then advance(); push(T.ROCKET, "=>")
                else                               push(T.ASSIGN, "=") end

            elseif c == "!" then
                advance()
                if cur() == "=" then advance(); push(T.OP, "!=")
                else                            push(T.OP, "!") end

            elseif c == "<" then
                advance()
                if cur() == "=" then advance(); push(T.OP, "<=")
                else                            push(T.OP, "<") end

            elseif c == ">" then
                advance()
                if cur() == "=" then advance(); push(T.OP, ">=")
                else                            push(T.OP, ">") end

            elseif c == "|" then
                advance()
                if     cur() == "&" then advance(); push(T.OP, "|&")
                elseif cur() == "|" then advance(); push(T.OP, "||")
                else                               push(T.OP, "|") end

            elseif c == "+" then advance(); push(T.OP,     "+")
            elseif c == "-" then advance(); push(T.OP,     "-")
            elseif c == "*" then advance(); push(T.OP,     "*")
            elseif c == "/" then advance(); push(T.OP,     "/")
            elseif c == "(" then advance(); push(T.LPAREN, "(")
            elseif c == ")" then advance(); push(T.RPAREN, ")")
            elseif c == "[" then advance(); push(T.LBRACK, "[")
            elseif c == "]" then advance(); push(T.RBRACK, "]")
            elseif c == "{" then advance(); push(T.LBRACE, "{")
            elseif c == "}" then advance(); push(T.RBRACE, "}")
            elseif c == "," then advance(); push(T.COMMA,  ",")
            elseif c == "." then advance(); push(T.DOT,    ".")

            else
                error(string.format("Unexpected character %q at line %d col %d",
                    c, lx.line, lx.col))
            end
        end

        push(T.EOF, nil)
        return lx.tokens
    end

    return lx
end

--[[ { "in": "source: string", "out": "token[]", "note": "public entry point; creates a lexer and runs it" } ]]
function M.tokenize(source)
    return new_lexer(source):run()
end

return M
