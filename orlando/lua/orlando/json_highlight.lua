--[[
{
  "module": "orlando.json_highlight",
  "role": "Tokenize a JSON document and emit HTML with pygments-compatible span classes (nt, s2, kc, mi, mf, p) so the existing pygments CSS in style.css colours it. Used for the vibecode dark blocks; could be used for any JSON code block.",
  "exports": {
    "highlight": "json text -> HTML string of <span class=\"...\">...</span> ... pieces. Whitespace and unrecognized characters pass through as escaped plain text."
  },
  "classes": {
    "nt": "object key (Name.Tag)",
    "s2": "string value (Literal.String.Double)",
    "kc": "true / false / null (Keyword.Constant)",
    "mi": "integer (Literal.Number.Integer)",
    "mf": "float (Literal.Number.Float)",
    "p":  "punctuation { } [ ] , :"
  }
}
]]
local M = {}

local function escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function span(cls, text)
    return '<span class="' .. cls .. '">' .. escape(text) .. '</span>'
end

-- Read one quoted JSON string starting at i (i points at the opening ").
-- Returns the substring including both quotes, and the index after the closing quote.
local function scan_string(s, i)
    local j = i + 1
    local n = #s
    while j <= n do
        local c = s:sub(j, j)
        if c == "\\" then
            j = j + 2
        elseif c == '"' then
            return s:sub(i, j), j + 1
        else
            j = j + 1
        end
    end
    -- Malformed (no closing quote): return what we have so we don't loop.
    return s:sub(i, n), n + 1
end

-- Read a JSON number starting at i. Returns (text, next_i, is_float).
local function scan_number(s, i)
    local j = i
    local n = #s
    if s:sub(j, j) == "-" then j = j + 1 end
    while j <= n and s:sub(j, j):match("%d") do j = j + 1 end
    local is_float = false
    if s:sub(j, j) == "." then
        is_float = true
        j = j + 1
        while j <= n and s:sub(j, j):match("%d") do j = j + 1 end
    end
    local exp = s:sub(j, j)
    if exp == "e" or exp == "E" then
        is_float = true
        j = j + 1
        if s:sub(j, j):match("[+-]") then j = j + 1 end
        while j <= n and s:sub(j, j):match("%d") do j = j + 1 end
    end
    return s:sub(i, j - 1), j, is_float
end

--[[ {
    "in":  {"json": "string"},
    "out": "string (HTML)"
} ]]
function M.highlight(json)
    local parts = {}
    local i, n = 1, #json
    while i <= n do
        local c = json:sub(i, i)
        if c == '"' then
            local str, ni = scan_string(json, i)
            -- Key vs value: a string followed by `:` (after whitespace) is a key.
            local k = ni
            while k <= n and json:sub(k, k):match("%s") do k = k + 1 end
            local cls = json:sub(k, k) == ":" and "nt" or "s2"
            parts[#parts + 1] = span(cls, str)
            i = ni
        elseif c:match("[%-%d]") then
            local num, ni, is_float = scan_number(json, i)
            parts[#parts + 1] = span(is_float and "mf" or "mi", num)
            i = ni
        elseif json:sub(i, i + 3) == "true" then
            parts[#parts + 1] = span("kc", "true"); i = i + 4
        elseif json:sub(i, i + 4) == "false" then
            parts[#parts + 1] = span("kc", "false"); i = i + 5
        elseif json:sub(i, i + 3) == "null" then
            parts[#parts + 1] = span("kc", "null"); i = i + 4
        elseif c == "{" or c == "}" or c == "[" or c == "]" or c == "," or c == ":" then
            parts[#parts + 1] = span("p", c)
            i = i + 1
        else
            -- whitespace and anything else: emit as escaped text
            parts[#parts + 1] = escape(c)
            i = i + 1
        end
    end
    return table.concat(parts)
end

return M
