local sqlite3 = require "lsqlite3"
local cjson   = require "cjson"
local util    = require "util"
local sign    = require "sign"

local _M = {}

local DB_PATH       = "/data/falstaff.db"
local KEY_PRIV_PATH = "/data/private.pem"
local KEY_PUB_PATH  = "/data/public.pem"

local SCHEMA = [[
    CREATE TABLE IF NOT EXISTS records (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        type        TEXT    NOT NULL,
        prev_hash   TEXT,
        ts          TEXT    NOT NULL,
        signer      TEXT    NOT NULL,
        payload     TEXT    NOT NULL,
        signature   TEXT    NOT NULL,
        record_hash TEXT    NOT NULL UNIQUE
    );
    CREATE TABLE IF NOT EXISTS uns_index (
        uns          TEXT    NOT NULL,
        version      TEXT    NOT NULL,
        effective_dt TEXT    NOT NULL,
        record_id    INTEGER NOT NULL,
        PRIMARY KEY (uns, version)
    );
    CREATE INDEX IF NOT EXISTS idx_uns_dt ON uns_index (uns, effective_dt);
]]

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function open_db()
    local db, code = sqlite3.open(DB_PATH)
    if not db then return nil, "sqlite3 open failed: " .. tostring(code) end
    db:exec("PRAGMA journal_mode=WAL;")
    return db
end

local function last_hash(db)
    local stmt = db:prepare("SELECT record_hash FROM records ORDER BY id DESC LIMIT 1")
    local hash
    if stmt:step() == sqlite3.ROW then hash = stmt:get_value(0) end
    stmt:finalize()
    return hash
end

local function insert_record(db, rec)
    local json_blob = cjson.encode(rec.payload)
    local record_hash = util.sha256_hex(
        util.sorted_json({
            type      = rec.type,
            prev_hash = rec.prev_hash,
            ts        = rec.ts,
            signer    = rec.signer,
            payload   = rec.payload,
            signature = rec.signature,
        })
    )

    local stmt = db:prepare([[
        INSERT INTO records (type, prev_hash, ts, signer, payload, signature, record_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]])
    stmt:bind(1, rec.type)
    if rec.prev_hash then stmt:bind(2, rec.prev_hash) else stmt:bind(2) end
    stmt:bind(3, rec.ts)
    stmt:bind(4, rec.signer)
    stmt:bind(5, json_blob)
    stmt:bind(6, rec.signature)
    stmt:bind(7, record_hash)
    local code = stmt:step()
    stmt:finalize()

    if code ~= sqlite3.DONE then
        return nil, "insert failed: " .. tostring(code)
    end
    return record_hash
end

-- Called once at nginx startup.
function _M.init()
    local db, err = open_db()
    if not db then return false, err end

    db:exec(SCHEMA)

    -- Ensure key pair exists.
    if not read_file(KEY_PRIV_PATH) then
        local priv, pub, err = sign.generate_keypair()
        if not priv then db:close(); return false, "keygen: " .. tostring(err) end
        write_file(KEY_PRIV_PATH, priv)
        write_file(KEY_PUB_PATH, pub)
    end

    -- Ensure root block exists.
    local stmt = db:prepare("SELECT COUNT(*) FROM records WHERE type = 'root'")
    stmt:step()
    local count = stmt:get_value(0)
    stmt:finalize()

    if count == 0 then
        local priv = read_file(KEY_PRIV_PATH)
        local pub  = read_file(KEY_PUB_PATH)
        local ts   = os.date("!%Y-%m-%dT%H:%M:%SZ")

        local rec = {
            type      = "root",
            prev_hash = nil,
            ts        = ts,
            signer    = "falstaff",
            payload   = {note = "Falstaff test chain root block", public_key = pub},
        }
        local sig, err = sign.sign(rec, priv)
        if not sig then db:close(); return false, "root sign: " .. tostring(err) end
        rec.signature = sig

        local hash, err = insert_record(db, rec)
        if not hash then db:close(); return false, err end
    end

    db:close()
    return true
end

function _M.insert_registry_entry(uns, version, effective_dt, bucket)
    local db, err = open_db()
    if not db then return nil, err end

    local priv = read_file(KEY_PRIV_PATH)
    if not priv then db:close(); return nil, "no private key" end

    local ts   = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local prev = last_hash(db)

    local payload = {
        uns          = uns,
        version      = version or "unknown",
        effective_dt = effective_dt or ts,
        bucket       = bucket,
    }

    local rec = {
        type      = "registry_entry",
        prev_hash = prev,
        ts        = ts,
        signer    = "falstaff",
        payload   = payload,
    }

    local sig, err = sign.sign(rec, priv)
    if not sig then db:close(); return nil, err end
    rec.signature = sig

    local hash, err = insert_record(db, rec)
    if not hash then db:close(); return nil, err end

    -- Index by UNS for retrieval.
    local stmt = db:prepare([[
        INSERT OR REPLACE INTO uns_index (uns, version, effective_dt, record_id)
        VALUES (?, ?, ?, ?)
    ]])
    stmt:bind(1, uns)
    stmt:bind(2, payload.version)
    stmt:bind(3, payload.effective_dt)
    stmt:bind(4, db:last_insert_rowid())
    stmt:step()
    stmt:finalize()

    db:close()
    return hash
end

local function row_to_record(stmt)
    return {
        type        = stmt:get_value(0),
        prev_hash   = stmt:get_value(1) or cjson.null,
        ts          = stmt:get_value(2),
        signer      = stmt:get_value(3),
        payload     = cjson.decode(stmt:get_value(4)),
        signature   = stmt:get_value(5),
        record_hash = stmt:get_value(6),
    }
end

local SELECT = [[
    SELECT r.type, r.prev_hash, r.ts, r.signer, r.payload, r.signature, r.record_hash
    FROM records r JOIN uns_index u ON u.record_id = r.id
    WHERE u.uns = ?
]]

function _M.get_latest(uns)
    local db, err = open_db()
    if not db then return nil, err end

    local stmt = db:prepare(SELECT .. " ORDER BY u.effective_dt DESC, r.id DESC LIMIT 1")
    stmt:bind(1, uns)
    local rec
    if stmt:step() == sqlite3.ROW then rec = row_to_record(stmt) end
    stmt:finalize()
    db:close()
    return rec
end

function _M.get_version(uns, version)
    local db, err = open_db()
    if not db then return nil, err end

    local stmt = db:prepare(SELECT .. " AND u.version = ? LIMIT 1")
    stmt:bind(1, uns)
    stmt:bind(2, version)
    local rec
    if stmt:step() == sqlite3.ROW then rec = row_to_record(stmt) end
    stmt:finalize()
    db:close()
    return rec
end

function _M.get_at_date(uns, date)
    local db, err = open_db()
    if not db then return nil, err end

    local stmt = db:prepare(SELECT .. " AND u.effective_dt <= ? ORDER BY u.effective_dt DESC, r.id DESC LIMIT 1")
    stmt:bind(1, uns)
    stmt:bind(2, date)
    local rec
    if stmt:step() == sqlite3.ROW then rec = row_to_record(stmt) end
    stmt:finalize()
    db:close()
    return rec
end

return _M
