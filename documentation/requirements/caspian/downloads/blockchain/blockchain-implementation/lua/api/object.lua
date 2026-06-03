local cjson = require "cjson"
local chain = require "chain"

local function respond(status, body)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(body))
end

local uns = ngx.var.uri:match("^/v1/object/(.+)$")
if not uns then
    return respond(400, {error = "invalid path"})
end

local args    = ngx.req.get_uri_args()
local version = args.version
local at      = args.at

local rec, err
if version then
    rec, err = chain.get_version(uns, version)
elseif at then
    rec, err = chain.get_at_date(uns, at)
else
    rec, err = chain.get_latest(uns)
end

if err then
    return respond(500, {error = err})
end
if not rec then
    return respond(404, {error = "not found"})
end

respond(200, rec)
