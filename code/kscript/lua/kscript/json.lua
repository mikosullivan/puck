--[[
{
  "module": "kscript.json",
  "role": "Minimal JSON encoder for KScriptJSON output",
  "exports": {
    "encode":    "(value, pretty?) → string  encode any Lua value to a JSON string",
    "null":      "sentinel  JSON null; use instead of Lua nil when building KScriptJSON tables",
    "new_hash":  "() → ordered_hash  create an empty ordered hash",
    "hash_set":  "(h, k, v)  set a key on an ordered hash, preserving insertion order",
    "hash_keys": "(h) → array  return keys in insertion order (falls back to sorted for plain tables)"
  },
  "number_rule": "integers emitted without decimal point; floats use %.17g",
  "hash_ordering": "ordered hashes carry a _keys array in their metatable; plain Lua tables fall back to sorted keys"
}
]]
local M = {}

--[[ { "what": "JSON null sentinel", "why": "Lua nil cannot be stored in tables; use this wherever JSON null is needed in KScriptJSON output" } ]]
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

return M
