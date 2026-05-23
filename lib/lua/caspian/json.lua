--[[
{
  "module": "caspian.json",
  "role": "Minimal JSON encoder and parser for CaspianJ",
  "exports": {
    "encode":    "(value, pretty?) → string  encode any Lua value to a JSON string",
    "parse":     "(string) → any              parse a JSON string to a Lua value; null → M.null",
    "null":      "sentinel  JSON null; use instead of Lua nil when building CaspianJ tables",
    "new_hash":  "() → ordered_hash  create an empty ordered hash",
    "hash_set":  "(h, k, v)  set a key on an ordered hash, preserving insertion order",
    "hash_keys": "(h) → array  return keys in insertion order (falls back to sorted for plain tables)"
  },
  "number_rule": "integers emitted without decimal point; floats use %.17g",
  "hash_ordering": "ordered hashes carry a _keys array in their metatable; plain Lua tables fall back to sorted keys",
  "parse_note": "parse returns ordered hashes (with _keys metatable) for JSON objects, so round-trip preserves insertion order"
}
]]
local M = {}

--[[ { "what": "JSON null sentinel", "why": "Lua nil cannot be stored in tables; use this wherever JSON null is needed in CaspianJ output" } ]]
M.null = setmetatable({}, { __tostring = function() return "null" end })

--[[ { "what": "metatable shared by all ordered hashes", "note": "presence of this metatable signals to the encoder to use _keys for ordering" } ]]
local ordered_hash_mt = {}

--[[ { "out": "ordered_hash", "note": "creates an empty hash that tracks insertion order; use hash_set to add keys" } ]]
function M.new_hash()
    return setmetatable({}, {__index = ordered_hash_mt, _keys = {}})
end

--[[ { "in": {"h": "ordered_hash", "k": "string", "v": "any"}, "note": "sets key on ordered hash; appends k to _keys on first insertion only" } ]]
function M.hash_set(h, k, v)
    local mt = getmetatable(h)
    if mt and mt._keys and h[k] == nil then
        mt._keys[#mt._keys + 1] = k
    end
    h[k] = v
end

--[[ { "in": "h: table", "out": "array of string keys", "note": "returns keys in insertion order for ordered hashes; falls back to sorted order for plain Lua tables" } ]]
function M.hash_keys(h)
    local mt = getmetatable(h)
    if mt and mt._keys then return mt._keys end
    local keys = {}
    for k in pairs(h) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

--[[ { "in": "v: any", "out": "bool", "note": "identity check against M.null sentinel — does not treat Lua nil as null" } ]]
local function is_null(v)  return v == M.null end

--[[ { "in": "t: any", "out": "bool", "note": "true iff t is a table whose only keys are sequential integers 1..#t; empty table → true" } ]]
local function is_array(t)
    if type(t) ~= "table" then return false end
    local mt = getmetatable(t)
    if mt and mt._keys then return false end  -- ordered hashes are never arrays
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

--[[
{
  "in": {"v": "any Lua value", "indent": "string? (indent unit e.g. '  ')", "level": "number (current nesting depth)"},
  "out": "string (JSON fragment)",
  "note": "recursive inner encoder; called by M.encode with indent=nil for compact or indent='  ' for pretty-print"
}
]]
local function encode(v, indent, level)
    local t = type(v)
    if is_null(v) then
        return "null"
    elseif t == "nil" then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        if v == math.floor(v) and v >= -2^53 and v <= 2^53 then
            return string.format("%.0f", v)
        else
            return string.format("%.17g", v)
        end
    elseif t == "string" then
        local s = v
            :gsub('\\', '\\\\')
            :gsub('"',  '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        local pad      = indent and string.rep(indent, level)     or ""
        local ipad     = indent and string.rep(indent, level + 1) or ""
        local sep      = indent and ",\n" .. ipad or ","
        local open_nl  = indent and "\n" .. ipad or ""
        local close_nl = indent and "\n" .. pad  or ""

        if is_array(v) then
            if #v == 0 then return "[]" end
            local parts = {}
            for i = 1, #v do
                parts[i] = encode(v[i], indent, level + 1)
            end
            return "[" .. open_nl .. table.concat(parts, sep) .. close_nl .. "]"
        else
            local keys = M.hash_keys(v)
            if #keys == 0 then return "{}" end
            local parts = {}
            for _, k in ipairs(keys) do
                local ks = '"' .. k:gsub('\\','\\\\'):gsub('"','\\"') .. '"'
                parts[#parts + 1] = ks .. (indent and ": " or ":") .. encode(v[k], indent, level + 1)
            end
            return "{" .. open_nl .. table.concat(parts, sep) .. close_nl .. "}"
        end
    else
        error("json.encode: cannot encode value of type " .. t)
    end
end

--[[ { "in": {"v": "any Lua value", "pretty": "bool?"}, "out": "string (JSON)", "note": "pretty=true → 2-space indented; nil/false → compact single-line" } ]]
function M.encode(v, pretty)
    return encode(v, pretty and "  " or nil, 0)
end

--[[
{
  "what": "JSON parser",
  "role": "Recursive-descent parser producing Lua values from a JSON string",
  "shape": {
    "object": "ordered hash (new_hash + hash_set) — preserves insertion order on round-trip",
    "array":  "plain Lua table indexed from 1",
    "string": "Lua string (escapes \\\" \\\\ \\/ \\b \\f \\n \\r \\t and \\uXXXX decoded)",
    "number": "Lua number (math.floor preserved when integer)",
    "true/false": "Lua true/false",
    "null":   "M.null sentinel (not Lua nil — survives table storage)"
  },
  "errors": "raises a Lua error with line:col on malformed input"
}
]]
local parse_value

--[[ helper: walk to the position of byte offset i and return (line, col), 1-indexed ]]
local function pos_at(s, i)
    local line, col = 1, 1
    for j = 1, i - 1 do
        if s:byte(j) == 10 then line = line + 1; col = 1
        else col = col + 1 end
    end
    return line, col
end

local function parse_error(s, i, msg)
    local line, col = pos_at(s, i)
    error(string.format("json.parse: %s at line %d col %d", msg, line, col), 2)
end

--[[ skip whitespace; returns the next non-whitespace index ]]
local function skip_ws(s, i)
    while i <= #s do
        local c = s:byte(i)
        if c == 32 or c == 9 or c == 10 or c == 13 then
            i = i + 1
        else
            return i
        end
    end
    return i
end

--[[ decode \uXXXX → UTF-8 bytes; cp is a 16-bit codepoint integer ]]
local function utf8_encode(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + (cp >> 6), 0x80 + (cp & 0x3F))
    else
        return string.char(0xE0 + (cp >> 12), 0x80 + ((cp >> 6) & 0x3F), 0x80 + (cp & 0x3F))
    end
end

local function parse_string(s, i)
    if s:byte(i) ~= 34 then parse_error(s, i, "expected '\"'") end
    i = i + 1
    local out = {}
    while i <= #s do
        local c = s:byte(i)
        if c == 34 then
            return table.concat(out), i + 1
        elseif c == 92 then  -- backslash
            local esc = s:byte(i + 1)
            if     esc == 34  then out[#out + 1] = '"';  i = i + 2
            elseif esc == 92  then out[#out + 1] = '\\'; i = i + 2
            elseif esc == 47  then out[#out + 1] = '/';  i = i + 2
            elseif esc == 98  then out[#out + 1] = '\b'; i = i + 2
            elseif esc == 102 then out[#out + 1] = '\f'; i = i + 2
            elseif esc == 110 then out[#out + 1] = '\n'; i = i + 2
            elseif esc == 114 then out[#out + 1] = '\r'; i = i + 2
            elseif esc == 116 then out[#out + 1] = '\t'; i = i + 2
            elseif esc == 117 then  -- \uXXXX
                local hex = s:sub(i + 2, i + 5)
                if #hex ~= 4 or not hex:match("^[0-9A-Fa-f]+$") then
                    parse_error(s, i, "bad \\u escape")
                end
                out[#out + 1] = utf8_encode(tonumber(hex, 16))
                i = i + 6
            else
                parse_error(s, i, "unknown escape")
            end
        else
            out[#out + 1] = string.char(c)
            i = i + 1
        end
    end
    parse_error(s, i, "unterminated string")
end

local function parse_number(s, i)
    local start = i
    if s:byte(i) == 45 then i = i + 1 end  -- minus
    while i <= #s do
        local c = s:byte(i)
        if (c >= 48 and c <= 57) or c == 46 or c == 43 or c == 45
                or c == 69 or c == 101 then
            i = i + 1
        else
            break
        end
    end
    local n = tonumber(s:sub(start, i - 1))
    if n == nil then parse_error(s, start, "bad number") end
    return n, i
end

local function parse_array(s, i)
    i = i + 1  -- consume '['
    local arr = {}
    i = skip_ws(s, i)
    if s:byte(i) == 93 then return arr, i + 1 end  -- empty array
    while true do
        local v
        v, i = parse_value(s, i)
        arr[#arr + 1] = v
        i = skip_ws(s, i)
        local c = s:byte(i)
        if c == 93 then return arr, i + 1
        elseif c == 44 then i = skip_ws(s, i + 1)
        else parse_error(s, i, "expected ',' or ']' in array") end
    end
end

local function parse_object(s, i)
    i = i + 1  -- consume '{'
    local obj = M.new_hash()
    i = skip_ws(s, i)
    if s:byte(i) == 125 then return obj, i + 1 end  -- empty object
    while true do
        i = skip_ws(s, i)
        local k
        k, i = parse_string(s, i)
        i = skip_ws(s, i)
        if s:byte(i) ~= 58 then parse_error(s, i, "expected ':' after object key") end
        i = skip_ws(s, i + 1)
        local v
        v, i = parse_value(s, i)
        M.hash_set(obj, k, v)
        i = skip_ws(s, i)
        local c = s:byte(i)
        if c == 125 then return obj, i + 1
        elseif c == 44 then i = i + 1
        else parse_error(s, i, "expected ',' or '}' in object") end
    end
end

parse_value = function(s, i)
    i = skip_ws(s, i)
    if i > #s then parse_error(s, i, "unexpected end of input") end
    local c = s:byte(i)
    if c == 123 then return parse_object(s, i) end
    if c == 91  then return parse_array(s, i)  end
    if c == 34  then return parse_string(s, i) end
    if c == 45 or (c >= 48 and c <= 57) then return parse_number(s, i) end
    if s:sub(i, i + 3) == "true"  then return true,   i + 4 end
    if s:sub(i, i + 4) == "false" then return false,  i + 5 end
    if s:sub(i, i + 3) == "null"  then return M.null, i + 4 end
    parse_error(s, i, "unexpected character")
end

--[[ { "in": "s: JSON string", "out": "Lua value", "note": "objects become ordered hashes; null becomes M.null sentinel; trailing whitespace is allowed" } ]]
function M.parse(s)
    if type(s) ~= "string" then
        error("json.parse: expected string, got " .. type(s), 2)
    end
    local v, i = parse_value(s, 1)
    i = skip_ws(s, i)
    if i <= #s then parse_error(s, i, "trailing data after JSON value") end
    return v
end

return M
