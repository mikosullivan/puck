--[[
{
  "module": "orlando.caspian_highlight",
  "role": "Tokenize Caspian source and emit HTML with pygments-compatible span classes so the pygments CSS in style.css colours it. Mirrors the token categories defined by vscode/syntax/syntaxes/caspian.tmLanguage.json; the V1 lexer is intentionally regex-grade rather than reusing caspian.lexer (which is line/col-aware and overkill for HTML markup).",
  "exports": {
    "highlight": "caspian source -> HTML string of <span class=\"...\">...</span> pieces; whitespace and unrecognized characters pass through escaped"
  },
  "classes": {
    "c1": "# line comment",
    "kc": "true / false / null",
    "kd": "function / class / inherits / abstract / record_class / field / accessor / helper / remote / join",
    "kr": "if / elsif / elseif / else / end / while / do / return / catch / heed / as / yield / untrusted / self / exit / before / between / after / noloop",
    "kp": "and / or / not (logical word operators)",
    "s1": "'single' string",
    "s2": "\"double\" string and heredoc body",
    "nv": "$name variable",
    "vi": "@name instance variable",
    "nb": "%name system method",
    "nf": "&name function reference (and &.) ",
    "nl": ":name symbol",
    "mi": "integer",
    "mf": "float",
    "o":  "operator"
  },
  "limitations_v1": [
    "no interpolation parsing inside double-quoted strings (#{...} renders as part of the string)",
    "no special highlighting for string variable embed ($var inside \"...\")",
    "no per-context disambiguation (e.g., : as colon-symbol vs hash-rocket; we lex by leading char)"
  ]
}
]]
local M = {}

local KEYWORDS_CONTROL = {
    ["if"]=1, ["elsif"]=1, ["elseif"]=1, ["else"]=1, ["end"]=1,
    ["while"]=1, ["do"]=1, ["return"]=1, ["catch"]=1, ["heed"]=1,
}
local KEYWORDS_DECL = {
    ["function"]=1, ["remote"]=1, ["class"]=1, ["inherits"]=1,
    ["abstract"]=1, ["record_class"]=1, ["field"]=1, ["accessor"]=1,
    ["helper"]=1, ["join"]=1,
}
local KEYWORDS_OTHER = {
    ["as"]=1, ["yield"]=1, ["untrusted"]=1, ["self"]=1, ["exit"]=1,
    ["before"]=1, ["between"]=1, ["after"]=1, ["noloop"]=1,
}
local KEYWORDS_LOGICAL = { ["and"]=1, ["or"]=1, ["not"]=1 }
local CONSTANTS        = { ["true"]=1, ["false"]=1, ["null"]=1 }

local function escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function span(cls, text)
    return '<span class="' .. cls .. '">' .. escape(text) .. '</span>'
end

------------------------------------------------------------
-- Scanners — each returns the matched chunk and the new position,
-- or nil if no match at `i`.
------------------------------------------------------------

-- # comment — except #{ (string interpolation, only inside strings).
local function scan_comment(s, i)
    if s:sub(i, i) ~= "#" then return nil end
    if s:sub(i + 1, i + 1) == "{" then return nil end
    local j = s:find("\n", i, true) or (#s + 1)
    return s:sub(i, j - 1), j
end

-- '...' — single-quoted string with \. escapes.
local function scan_squote(s, i)
    if s:sub(i, i) ~= "'" then return nil end
    local j = i + 1
    local n = #s
    while j <= n do
        local c = s:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == "'" then return s:sub(i, j), j + 1
        else j = j + 1
        end
    end
    return s:sub(i, n), n + 1  -- unterminated — consume to EOF
end

-- "..." — double-quoted string with \. escapes (interpolation not split out).
local function scan_dquote(s, i)
    if s:sub(i, i) ~= '"' then return nil end
    local j = i + 1
    local n = #s
    while j <= n do
        local c = s:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == '"' then return s:sub(i, j), j + 1
        else j = j + 1
        end
    end
    return s:sub(i, n), n + 1
end

-- <<NAME, <<'NAME', <<"NAME" — heredoc body through end-of-line NAME.
local function scan_heredoc(s, i)
    if s:sub(i, i + 1) ~= "<<" then return nil end
    local label_start = i + 2
    local first = s:sub(label_start, label_start)
    local name, body_start
    if first == "'" or first == '"' then
        local close_q = s:find(first, label_start + 1, true)
        if not close_q then return nil end
        name = s:sub(label_start + 1, close_q - 1)
        body_start = close_q + 1
    else
        local m = s:match("^([%w_]+)", label_start)
        if not m then return nil end
        name = m
        body_start = label_start + #name
    end
    if name == "" then return nil end
    -- Find end-marker: a line whose entire contents == name.
    -- Search line by line from body_start.
    local pos = body_start
    while pos <= #s do
        local nl = s:find("\n", pos, true)
        local line_end = nl or (#s + 1)
        local line = s:sub(pos, line_end - 1)
        if line == name then
            return s:sub(i, line_end - 1), line_end
        end
        if not nl then break end
        pos = nl + 1
    end
    return s:sub(i), #s + 1  -- unterminated — consume to EOF
end

-- Identifier: [A-Za-z_][A-Za-z0-9_]*  (optional trailing ? always; ! unless followed by =)
local function scan_ident(s, i)
    local c = s:sub(i, i)
    if not c:match("[%a_]") then return nil end
    local j = i
    while j <= #s and s:sub(j, j):match("[%w_]") do j = j + 1 end
    -- trailing ? always consumed
    if s:sub(j, j) == "?" then j = j + 1
    elseif s:sub(j, j) == "!" and s:sub(j + 1, j + 1) ~= "=" then
        j = j + 1
    end
    return s:sub(i, j - 1), j
end

-- $name, $$name — variable.
local function scan_var(s, i)
    if s:sub(i, i) ~= "$" then return nil end
    local prefix_len = (s:sub(i + 1, i + 1) == "$") and 2 or 1
    local name_start = i + prefix_len
    local m = s:match("^[%a_][%w_]*", name_start)
    if not m then return nil end
    return s:sub(i, name_start + #m - 1), name_start + #m
end

-- @name — instance variable.
local function scan_ivar(s, i)
    if s:sub(i, i) ~= "@" then return nil end
    local m = s:match("^[%a_][%w_]*", i + 1)
    if not m then return nil end
    return s:sub(i, i + #m), i + #m + 1
end

-- %name(.subname)* — system method.
local function scan_sys(s, i)
    if s:sub(i, i) ~= "%" then return nil end
    local m = s:match("^[%a_][%w_.]*", i + 1)
    if not m then return nil end
    return s:sub(i, i + #m), i + #m + 1
end

-- &name or &. — function ref or safe-nav.
local function scan_func(s, i)
    if s:sub(i, i) ~= "&" then return nil end
    if s:sub(i + 1, i + 1) == "." then return "&.", i + 2 end
    local m = s:match("^[%a_][%w_]*", i + 1)
    if not m then return nil end
    return s:sub(i, i + #m), i + #m + 1
end

-- :name — symbol. Don't match :: or := or ': ' (standalone colon).
local function scan_symbol(s, i)
    if s:sub(i, i) ~= ":" then return nil end
    local m = s:match("^[%a_][%w_]*", i + 1)
    if not m then return nil end
    return s:sub(i, i + #m), i + #m + 1
end

-- Numbers: integer or float.
local function scan_number(s, i)
    local c = s:sub(i, i)
    if not c:match("%d") then return nil end
    local j = i
    while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
    if s:sub(j, j) == "." and s:sub(j + 1, j + 1):match("%d") then
        j = j + 1
        while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
        return s:sub(i, j - 1), j, true  -- float
    end
    return s:sub(i, j - 1), j, false  -- int
end

-- Multi-char operators tried longest-first.
local OPS = { "==", "!=", "<=", ">=", "=>", "|&", "&&", "||" }
local function scan_op(s, i)
    for _, op in ipairs(OPS) do
        if s:sub(i, i + #op - 1) == op then return op, i + #op end
    end
    local c = s:sub(i, i)
    if c == "<" or c == ">" or c == "+" or c == "-"
       or c == "*" or c == "/" or c == "=" or c == "|"
       or c == "!" then
        return c, i + 1
    end
    return nil
end

------------------------------------------------------------
-- Main tokenizer / renderer
------------------------------------------------------------

local function classify_ident(name)
    if CONSTANTS[name]        then return "kc" end
    if KEYWORDS_CONTROL[name] then return "kr" end
    if KEYWORDS_DECL[name]    then return "kd" end
    if KEYWORDS_OTHER[name]   then return "kr" end
    if KEYWORDS_LOGICAL[name] then return "kp" end
    return nil  -- plain identifier — pass through unclassified
end

-- Try the scanners in order; the first hit decides the token's class.
-- Returns html_fragment, new_i. Always advances by at least one char.
local function next_token(source, i)
    local c = source:sub(i, i)

    -- Pass through pure whitespace runs.
    if c == "\n" or c == " " or c == "\t" then
        local n, j = #source, i
        while j <= n and (source:sub(j, j) == "\n"
                       or source:sub(j, j) == " "
                       or source:sub(j, j) == "\t") do
            j = j + 1
        end
        return escape(source:sub(i, j - 1)), j
    end

    local tok, ni

    tok, ni = scan_comment(source, i)
    if tok then return span("c1", tok), ni end

    tok, ni = scan_heredoc(source, i)
    if tok then return span("s2", tok), ni end

    tok, ni = scan_squote(source, i)
    if tok then return span("s1", tok), ni end

    tok, ni = scan_dquote(source, i)
    if tok then return span("s2", tok), ni end

    tok, ni = scan_var(source, i)
    if tok then return span("nv", tok), ni end

    tok, ni = scan_ivar(source, i)
    if tok then return span("vi", tok), ni end

    tok, ni = scan_sys(source, i)
    if tok then return span("nb", tok), ni end

    tok, ni = scan_func(source, i)
    if tok then return span("nf", tok), ni end

    tok, ni = scan_symbol(source, i)
    if tok then return span("nl", tok), ni end

    local is_float
    tok, ni, is_float = scan_number(source, i)
    if tok then return span(is_float and "mf" or "mi", tok), ni end

    tok, ni = scan_ident(source, i)
    if tok then
        local cls = classify_ident(tok)
        if cls then return span(cls, tok), ni end
        return escape(tok), ni
    end

    tok, ni = scan_op(source, i)
    if tok then return span("o", tok), ni end

    -- Fallback: pass through one char escaped.
    return escape(c), i + 1
end

--[[ { "in": {"source": "string (caspian source)"}, "out": "string (HTML with span markup)" } ]]
function M.highlight(source)
    local out, i, n = {}, 1, #source
    while i <= n do
        local frag, ni = next_token(source, i)
        out[#out + 1] = frag
        i = ni
    end
    return table.concat(out)
end

return M
