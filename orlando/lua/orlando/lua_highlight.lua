--[=[
{
  "module": "orlando.lua_highlight",
  "role": "Tokenize Lua source and emit HTML with pygments-compatible span classes so the pygments CSS in style.css colours it. Sibling of orlando.caspian_highlight; same span-class conventions.",
  "exports": {
    "highlight": "lua source -> HTML string of <span class=\"...\">...</span> pieces; whitespace and unrecognized characters pass through escaped"
  },
  "classes": {
    "c1": "-- line comment",
    "cm": "--[[ ... ]] block comment (any level of long-bracket)",
    "kc": "true / false / nil",
    "kd": "function / local",
    "kr": "if / elseif / else / end / do / while / for / repeat / until / break / return / then / in / goto",
    "kp": "and / or / not (logical word operators)",
    "s1": "'single' string",
    "s2": "\"double\" string",
    "s":  "[[long-bracket]] string (any level)",
    "mi": "integer",
    "mf": "float",
    "mh": "hex literal",
    "o":  "operator"
  },
  "limitations_v1": [
    "no highlighting for standard-library names (math.pi, string.format, etc.) — passes through as plain identifier",
    "no per-context disambiguation (function name after `function` keyword renders as plain identifier)"
  ]
}
]=]
local M = {}

local KEYWORDS_CONTROL = {
    ["if"]=1, ["elseif"]=1, ["else"]=1, ["end"]=1, ["do"]=1,
    ["while"]=1, ["for"]=1, ["repeat"]=1, ["until"]=1, ["break"]=1,
    ["return"]=1, ["then"]=1, ["in"]=1, ["goto"]=1,
}
local KEYWORDS_DECL    = { ["function"]=1, ["local"]=1 }
local KEYWORDS_LOGICAL = { ["and"]=1, ["or"]=1, ["not"]=1 }
local CONSTANTS        = { ["true"]=1, ["false"]=1, ["nil"]=1 }

local function escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function span(cls, text)
    return '<span class="' .. cls .. '">' .. escape(text) .. '</span>'
end

-- Long-bracket opener at position i: returns (level, body_start) or nil.
-- Level = number of '=' between the brackets (0 for [[, 1 for [=[, ...).
local function match_long_open(s, i)
    if s:sub(i, i) ~= "[" then return nil end
    local j = i + 1
    local level = 0
    while s:sub(j, j) == "=" do level = level + 1; j = j + 1 end
    if s:sub(j, j) ~= "[" then return nil end
    return level, j + 1
end

-- Find matching close ]=*] starting from body_start with the given level.
-- Returns the position AFTER the closing bracket, or nil if unterminated.
local function find_long_close(s, body_start, level)
    local pat = "]" .. string.rep("=", level) .. "]"
    local plen = #pat
    local pos = body_start
    while pos <= #s do
        local found = s:find(pat, pos, true)
        if not found then return nil end
        return found + plen
    end
    return nil
end

-- -- line comment, --[[ block comment, --[=[ block comment level 1, etc.
local function scan_comment(s, i)
    if s:sub(i, i + 1) ~= "--" then return nil end
    local level, body_start = match_long_open(s, i + 2)
    if level then
        local finish = find_long_close(s, body_start, level)
        if finish then
            return s:sub(i, finish - 1), finish, true
        end
        return s:sub(i), #s + 1, true
    end
    local j = s:find("\n", i, true) or (#s + 1)
    return s:sub(i, j - 1), j, false
end

-- [[ or [=[ ... ]=] long-bracket string.
local function scan_long_string(s, i)
    local level, body_start = match_long_open(s, i)
    if not level then return nil end
    local finish = find_long_close(s, body_start, level)
    if finish then return s:sub(i, finish - 1), finish end
    return s:sub(i), #s + 1
end

local function scan_squote(s, i)
    if s:sub(i, i) ~= "'" then return nil end
    local j, n = i + 1, #s
    while j <= n do
        local c = s:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == "'" then return s:sub(i, j), j + 1
        elseif c == "\n" then return s:sub(i, j - 1), j
        else j = j + 1
        end
    end
    return s:sub(i, n), n + 1
end

local function scan_dquote(s, i)
    if s:sub(i, i) ~= '"' then return nil end
    local j, n = i + 1, #s
    while j <= n do
        local c = s:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == '"' then return s:sub(i, j), j + 1
        elseif c == "\n" then return s:sub(i, j - 1), j
        else j = j + 1
        end
    end
    return s:sub(i, n), n + 1
end

local function scan_ident(s, i)
    local c = s:sub(i, i)
    if not c:match("[%a_]") then return nil end
    local j = i
    while j <= #s and s:sub(j, j):match("[%w_]") do j = j + 1 end
    return s:sub(i, j - 1), j
end

-- Hex, integer, float — no leading sign (that's an operator).
local function scan_number(s, i)
    local c = s:sub(i, i)
    if not c:match("%d") then
        if c == "." and s:sub(i + 1, i + 1):match("%d") then
            -- .5 float
        else return nil end
    end
    -- hex?
    if c == "0" and (s:sub(i + 1, i + 1) == "x" or s:sub(i + 1, i + 1) == "X") then
        local j = i + 2
        while j <= #s and s:sub(j, j):match("[%da-fA-F]") do j = j + 1 end
        return s:sub(i, j - 1), j, "mh"
    end
    local j = i
    while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
    local is_float = false
    if s:sub(j, j) == "." then
        is_float = true
        j = j + 1
        while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
    end
    if s:sub(j, j) == "e" or s:sub(j, j) == "E" then
        is_float = true
        j = j + 1
        if s:sub(j, j) == "+" or s:sub(j, j) == "-" then j = j + 1 end
        while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
    end
    return s:sub(i, j - 1), j, is_float and "mf" or "mi"
end

-- Multi-char operators tried longest-first.
local OPS_LONG = { "...", "..", "==", "~=", "<=", ">=", "<<", ">>", "::", "//" }
local OPS_SINGLE = {
    ["+"]=1, ["-"]=1, ["*"]=1, ["/"]=1, ["%"]=1, ["^"]=1, ["#"]=1,
    ["&"]=1, ["|"]=1, ["~"]=1, ["<"]=1, [">"]=1, ["="]=1,
}
local function scan_op(s, i)
    for _, op in ipairs(OPS_LONG) do
        if s:sub(i, i + #op - 1) == op then return op, i + #op end
    end
    local c = s:sub(i, i)
    if OPS_SINGLE[c] then return c, i + 1 end
    return nil
end

local function classify_ident(name)
    if CONSTANTS[name]        then return "kc" end
    if KEYWORDS_CONTROL[name] then return "kr" end
    if KEYWORDS_DECL[name]    then return "kd" end
    if KEYWORDS_LOGICAL[name] then return "kp" end
    return nil
end

local function next_token(source, i)
    local c = source:sub(i, i)

    if c == "\n" or c == " " or c == "\t" then
        local n, j = #source, i
        while j <= n and (source:sub(j, j) == "\n"
                       or source:sub(j, j) == " "
                       or source:sub(j, j) == "\t") do
            j = j + 1
        end
        return escape(source:sub(i, j - 1)), j
    end

    local tok, ni, extra

    tok, ni, extra = scan_comment(source, i)
    if tok then return span(extra and "cm" or "c1", tok), ni end

    tok, ni = scan_long_string(source, i)
    if tok then return span("s", tok), ni end

    tok, ni = scan_squote(source, i)
    if tok then return span("s1", tok), ni end

    tok, ni = scan_dquote(source, i)
    if tok then return span("s2", tok), ni end

    local ncls
    tok, ni, ncls = scan_number(source, i)
    if tok then return span(ncls, tok), ni end

    tok, ni = scan_ident(source, i)
    if tok then
        local cls = classify_ident(tok)
        if cls then return span(cls, tok), ni end
        return escape(tok), ni
    end

    tok, ni = scan_op(source, i)
    if tok then return span("o", tok), ni end

    return escape(c), i + 1
end

--[[ { "in": {"source": "string (lua source)"}, "out": "string (HTML with span markup)" } ]]
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
