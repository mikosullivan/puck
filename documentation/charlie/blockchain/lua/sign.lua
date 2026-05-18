local pkey = require "resty.openssl.pkey"
local util = require "util"

local _M = {}

local function record_msg(record)
    local copy = {}
    for k, v in pairs(record) do
        if k ~= "signature" then copy[k] = v end
    end
    return util.sorted_json(copy)
end

-- Sign a record table. Returns base64 signature or nil, err.
function _M.sign(record, private_key_pem)
    local pk, err = pkey.new(private_key_pem, {format = "PEM"})
    if not pk then return nil, err end

    local sig, err = pk:sign(record_msg(record))
    if not sig then return nil, err end

    return ngx.encode_base64(sig)
end

-- Verify a signed record. Returns true/false or nil, err.
function _M.verify(record, public_key_pem)
    local pk, err = pkey.new(public_key_pem, {format = "PEM"})
    if not pk then return nil, err end

    local sig = ngx.decode_base64(record.signature)
    if not sig then return nil, "bad base64 signature" end

    return pk:verify(sig, record_msg(record))
end

-- Generate a new Ed25519 key pair. Returns priv_pem, pub_pem or nil, nil, err.
function _M.generate_keypair()
    local pk, err = pkey.new({type = "Ed25519"})
    if not pk then return nil, nil, err end

    local priv, err = pk:to_PEM("private")
    if not priv then return nil, nil, err end

    local pub, err = pk:to_PEM("public")
    if not pub then return nil, nil, err end

    return priv, pub
end

return _M
