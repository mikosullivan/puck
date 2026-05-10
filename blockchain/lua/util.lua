local cjson      = require "cjson"
local resty_sha  = require "resty.sha256"
local resty_str  = require "resty.string"

local _M = {}

local cjson_null = cjson.null

local function json_str(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"',  '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        n = n + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            return false
        end
    end
    return n == #t
end

local function encode(val)
    if val == cjson_null then
        return "null"
    end
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val == math.floor(val) then
            return string.format("%d", val)
        else
            return string.format("%.17g", val)
        end
    elseif t == "string" then
        return json_str(val)
    elseif t == "table" then
        if is_array(val) then
            local parts = {}
            for i = 1, #val do
                parts[i] = encode(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local keys = {}
            for k in pairs(val) do
                if type(k) == "string" then keys[#keys+1] = k end
            end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do
                parts[#parts+1] = json_str(k) .. ":" .. encode(val[k])
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Serialize a table to minified JSON with keys in sorted order.
-- Used for signing — deterministic regardless of Lua table insertion order.
function _M.sorted_json(t)
    return encode(t)
end

function _M.sha256_hex(s)
    local h = resty_sha:new()
    h:update(s)
    return resty_str.to_hex(h:final())
end

return _M
