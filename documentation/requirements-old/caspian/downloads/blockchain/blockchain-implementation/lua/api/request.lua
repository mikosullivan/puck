local cjson = require "cjson"
local http  = require "resty.http"
local chain = require "chain"

local function respond(status, body)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(body))
end

ngx.req.read_body()
local raw = ngx.req.get_body_data()
if not raw then
    return respond(400, {error = "empty body"})
end

local ok, req = pcall(cjson.decode, raw)
if not ok or type(req) ~= "table" then
    return respond(400, {error = "invalid JSON"})
end

local uns = req.uns
if type(uns) ~= "string" or uns == "" then
    return respond(400, {error = "uns required"})
end

local httpc = http.new()
local res, err = httpc:request_uri("https://" .. uns, {
    method  = "GET",
    headers = {Accept = "application/json"},
    ssl_verify = false,
})

if not res then
    return respond(502, {error = "fetch failed: " .. tostring(err)})
end
if res.status ~= 200 then
    return respond(502, {error = "upstream returned " .. res.status})
end

local ok, obj = pcall(cjson.decode, res.body)
if not ok or type(obj) ~= "table" then
    return respond(502, {error = "upstream did not return valid JSON"})
end

local version = type(obj.version) == "string" and obj.version or "unknown"

local hash, err = chain.insert_registry_entry(uns, version, nil, obj)
if not hash then
    return respond(500, {error = "chain write failed: " .. tostring(err)})
end

respond(200, {ok = true, uns = uns, version = version, record_hash = hash})
