-- Standalone script: post grammar block to Falstaff chain.
-- Run with: luajit post-grammar.lua

package.path  = '/usr/local/openresty/luajit/share/lua/5.1/?.lua;/app/lua/?.lua;' .. package.path
package.cpath = '/usr/local/openresty/luajit/lib/lua/5.1/?.so;' .. package.cpath

-- ngx shim (encode_base64 used by sign.lua)
local function b64enc(data)
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local pad = (3 - #data % 3) % 3
    data = data .. string.rep('\0', pad)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = string.byte(data, i, i + 2)
        local n = a * 0x10000 + b * 0x100 + c
        out[#out+1] = chars:sub(math.floor(n / 0x40000) % 64 + 1, math.floor(n / 0x40000) % 64 + 1)
        out[#out+1] = chars:sub(math.floor(n / 0x1000)  % 64 + 1, math.floor(n / 0x1000)  % 64 + 1)
        out[#out+1] = chars:sub(math.floor(n / 0x40)    % 64 + 1, math.floor(n / 0x40)    % 64 + 1)
        out[#out+1] = chars:sub(n % 64 + 1,                        n % 64 + 1)
    end
    local s = table.concat(out)
    if pad > 0 then s = s:sub(1, -pad - 1) .. string.rep('=', pad) end
    return s
end

ngx = {encode_base64 = b64enc}

local sqlite3 = require 'lsqlite3'
local cjson   = require 'cjson'
local util    = require 'util'
local sign    = require 'sign'

local DB_PATH = '/data/falstaff.db'

local function read_file(path)
    local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
    local s = f:read('*a'); f:close(); return s
end

local db   = assert(sqlite3.open(DB_PATH))
local priv = read_file('/data/private.pem')
local ts   = os.date('!%Y-%m-%dT%H:%M:%SZ')

local stmt = db:prepare('SELECT record_hash FROM records ORDER BY id DESC LIMIT 1')
stmt:step()
local prev = stmt:get_value(0)
stmt:finalize()

local payload = {
    intent      = 'define-grammar',
    grammar     = {hash = 'self', version = '1.0'},
    vibecode    = {type = 'grammar', version = '1.0', signer = 'falstaff',
                   description = 'Puck blockchain block grammar version 1.0'},
    version     = '1.0',
    description = 'Puck blockchain block grammar version 1.0',
    inherits    = cjson.null,
    envelope    = {
        fields   = {'type', 'prev_hash', 'ts', 'signer', 'payload', 'signature'},
        required = {'type', 'prev_hash', 'ts', 'signer', 'payload', 'signature'},
    },
    payload_common = {
        fields    = {'intent', 'grammar', 'vibecode'},
        required  = {'intent', 'grammar'},
        encouraged = {'vibecode'},
        notes     = 'grammar is {hash, version}; use hash:self for the grammar block itself',
    },
    block_types   = {'root', 'grammar', 'registry_entry', 'endorsement',
                     'deprecation', 'revocation', 'delegation'},
    intent_values = {'establish-authority', 'endorse', 'delegate', 'define-grammar'},
    scope_values  = {'provenance', 'license-verified', 'security:fedramp-moderate',
                     'security:fedramp-high', 'security:fips-140-2', 'audit'},
}

local rec = {type = 'grammar', prev_hash = prev, ts = ts, signer = 'falstaff', payload = payload}

local sig, err = sign.sign(rec, priv)
if not sig then io.stderr:write('signing failed: ' .. tostring(err) .. '\n'); os.exit(1) end
rec.signature = sig

local record_hash = util.sha256_hex(util.sorted_json({
    type      = rec.type,
    prev_hash = rec.prev_hash,
    ts        = rec.ts,
    signer    = rec.signer,
    payload   = rec.payload,
    signature = rec.signature,
}))

local ins = db:prepare([[
    INSERT INTO records (type, prev_hash, ts, signer, payload, signature, record_hash)
    VALUES (?, ?, ?, ?, ?, ?, ?)
]])
ins:bind(1, rec.type)
ins:bind(2, rec.prev_hash)
ins:bind(3, rec.ts)
ins:bind(4, rec.signer)
ins:bind(5, cjson.encode(payload))
ins:bind(6, sig)
ins:bind(7, record_hash)
local code = ins:step()
ins:finalize()
db:close()

if code ~= sqlite3.DONE then
    io.stderr:write('insert failed: ' .. tostring(code) .. '\n'); os.exit(1)
end

print('Grammar block posted.')
print('record_hash: ' .. record_hash)
