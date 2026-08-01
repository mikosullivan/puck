--[[
{
	"module": "fiona",
	"role": "Fiona's Lua interface for the SQLite backend. Exposes get_db(path, mode) which returns a Db object. This is a minimal first pass — get_db creates the object and applies the schema to fresh databases. Per-method surface (query/set/delete/etc.) lands next.",
	"exports": {
		"get_db": "path, mode -> Db (opens or creates the DB, applies schema if fresh, returns handle)",
		"Db":     "class — the database handle"
	},
	"backend": "SQLite via lsqlite3"
}
]]

local sqlite3 = require("lsqlite3")

------------------------------------------------------------
-- Locate fiona.sql — it lives right next to this file,
-- so we build the path from this module's own source location.
------------------------------------------------------------

local this_file = debug.getinfo(1, "S").source

if this_file:sub(1, 1) == "@" then
	this_file = this_file:sub(2)
end

local this_dir = this_file:match("(.*/)") or "./"
local SCHEMA_PATH = this_dir .. "fiona.sql"

local function read_file(path)
	local f, err = io.open(path, "r")

	if not f then
		error("cannot open schema at " .. path .. " — " .. tostring(err))
	end

	local content = f:read("*a")
	f:close()
	return content
end

------------------------------------------------------------
-- Db class — the handle returned by get_db.
------------------------------------------------------------

local Db = {}
Db.__index = Db

--[[ {"in": {"conn": "lsqlite3 db", "mode": "string", "path": "string"}, "out": "Db instance"} ]]
function Db.new(conn, mode, path)
	return setmetatable({
		_conn = conn,
		_mode = mode,
		_path = path,
	}, Db)
end

-- Run fn() atomically via a SAVEPOINT. Nests correctly if the caller
-- already has a transaction (or savepoint) open. Rolls back on error
-- and re-raises with the original message.
local function atomic(conn, fn)
	conn:exec("savepoint sp")

	local ok, err = pcall(fn)

	if ok then
		conn:exec("release sp")
	else
		conn:exec("rollback to sp")
		conn:exec("release sp")
		error(err, 0)
	end
end

--[[ {"in": {}, "out": "table — every row in the meta table as {[key] = value}"} ]]
function Db:meta()
	local result = {}

	for row in self._conn:nrows("select key, value from meta") do
		result[row.key] = row.value
	end

	return result
end

--[[ {"in": {}, "out": "integer — the new row's hsa_pk"} ]]
function Db:add_hash()
	if self._mode == "r" then
		error("add_hash: database is opened in read-only mode ('r'); writes are not allowed")
	end

	local rc = self._conn:exec("insert into hsa (type, st, value) values ('h', null, null)")

	if rc ~= sqlite3.OK then
		error("add_hash: insert failed — " .. self._conn:errmsg())
	end

	return self._conn:last_insert_rowid()
end

--[[ {"in": {}, "out": "integer — the new row's hsa_pk"} ]]
function Db:add_array()
	if self._mode == "r" then
		error("add_array: database is opened in read-only mode ('r'); writes are not allowed")
	end

	local rc = self._conn:exec("insert into hsa (type, st, value) values ('a', null, null)")

	if rc ~= sqlite3.OK then
		error("add_array: insert failed — " .. self._conn:errmsg())
	end

	return self._conn:last_insert_rowid()
end

--[[ {"in": {"value": "nil | boolean | number | string"}, "out": "integer — the new row's hsa_pk"} ]]
function Db:add_scalar(value)
	if self._mode == "r" then
		error("add_scalar: database is opened in read-only mode ('r'); writes are not allowed")
	end

	local st, stored
	local t = type(value)

	if value == nil then
		st, stored = "u", nil
	elseif t == "boolean" then
		st, stored = "b", value and 1 or 0
	elseif t == "number" then
		st, stored = "n", value
	elseif t == "string" then
		st, stored = "s", value
	else
		error("add_scalar: value must be nil, boolean, number, or string — got " .. t .. " (use add_hash / add_array for collections)")
	end

	local stmt = self._conn:prepare("insert into hsa (type, st, value) values ('s', :st, :val)")
	stmt:bind_names({st = st, val = stored})
	local rc = stmt:step()
	stmt:finalize()

	if rc ~= sqlite3.DONE then
		error("add_scalar: insert failed — " .. self._conn:errmsg())
	end

	return self._conn:last_insert_rowid()
end

--[[ {"in": {"parent_pk": "integer", "key": "string", "child_pk": "integer"}, "out": "nil"} ]]
function Db:set_hash_element(parent_pk, key, child_pk)
	if self._mode == "r" then
		error("set_hash_element: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_hash_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(key) ~= "string" then
		error("set_hash_element: key must be a string; got " .. type(key))
	end

	if type(child_pk) ~= "number" then
		error("set_hash_element: child_pk must be a number; got " .. type(child_pk))
	end

	-- Look up existing (parent, key) — if present, we UPDATE the child
	-- in place (identity-immutable, content-mutable). If absent, we
	-- INSERT a fresh entry at max_idx + 1.
	local existing_child
	local sel = self._conn:prepare("select child from relationships where parent = :p and key = :k")
	sel:bind_names({p = parent_pk, k = key})

	if sel:step() == sqlite3.ROW then
		existing_child = sel:get_value(0)
	end

	sel:finalize()

	-- Same child already there — nothing to do.
	if existing_child == child_pk then
		return
	end

	if existing_child then
		-- UPDATE in place. The purge_after_update_of_child trigger fires
		-- and GCs the old child if it's now unreachable.
		local upd = self._conn:prepare("update relationships set child = :c where parent = :p and key = :k")
		upd:bind_names({c = child_pk, p = parent_pk, k = key})
		local rc = upd:step()
		upd:finalize()

		if rc ~= sqlite3.DONE then
			error("set_hash_element: update failed — " .. self._conn:errmsg())
		end
	else
		-- New key — append at max+1 (or 0 if empty).
		local max_sel = self._conn:prepare("select coalesce(max(idx) + 1, 0) from relationships where parent = :p")
		max_sel:bind_names({p = parent_pk})
		max_sel:step()
		local next_idx = max_sel:get_value(0)
		max_sel:finalize()

		local ins = self._conn:prepare("insert into relationships (parent, child, key, idx) values (:p, :c, :k, :i)")
		ins:bind_names({p = parent_pk, c = child_pk, k = key, i = next_idx})
		local rc = ins:step()
		ins:finalize()

		if rc ~= sqlite3.DONE then
			error("set_hash_element: insert failed — " .. self._conn:errmsg())
		end
	end
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer >= 0", "child_pk": "integer"}, "out": "nil"} ]]
function Db:set_array_element(parent_pk, idx, child_pk)
	if self._mode == "r" then
		error("set_array_element: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_array_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(idx) ~= "number" or idx < 0 or math.floor(idx) ~= idx then
		error("set_array_element: idx must be a non-negative integer; got " .. tostring(idx))
	end

	if type(child_pk) ~= "number" then
		error("set_array_element: child_pk must be a number; got " .. type(child_pk))
	end

	-- Same shape as set_hash_element: UPDATE in place if (parent, idx) is
	-- occupied; INSERT at that idx if not.
	local existing_child
	local sel = self._conn:prepare("select child from relationships where parent = :p and idx = :i")
	sel:bind_names({p = parent_pk, i = idx})

	if sel:step() == sqlite3.ROW then
		existing_child = sel:get_value(0)
	end

	sel:finalize()

	if existing_child == child_pk then
		return
	end

	if existing_child then
		local upd = self._conn:prepare("update relationships set child = :c where parent = :p and idx = :i")
		upd:bind_names({c = child_pk, p = parent_pk, i = idx})
		local rc = upd:step()
		upd:finalize()

		if rc ~= sqlite3.DONE then
			error("set_array_element: update failed — " .. self._conn:errmsg())
		end
	else
		local ins = self._conn:prepare("insert into relationships (parent, child, idx) values (:p, :c, :i)")
		ins:bind_names({p = parent_pk, c = child_pk, i = idx})
		local rc = ins:step()
		ins:finalize()

		if rc ~= sqlite3.DONE then
			error("set_array_element: insert failed — " .. self._conn:errmsg())
		end
	end
end

------------------------------------------------------------
-- get_db(path, mode) — opens or creates a Fiona SQLite DB
-- and returns the Db handle. Applies the schema to fresh DBs.
------------------------------------------------------------

-- 'w' is deliberately excluded — every Fiona write reads the root hash
-- first, so a strict write-only handle can't perform any operation Fiona
-- exposes. Documented as a conscious V1 choice in the spec (see
-- fiona/spec/sqlite/index.md, "No write-only mode in V1"). If a real
-- append-only use case surfaces, 'w' can be reinstated with the
-- root-read exception carved out.
local VALID_MODES = {r = true, rw = true, wr = true}

--[[ {"in": {"path": "string (file path or ':memory:')", "mode": "string ('r' | 'rw' | 'wr')"}, "out": "Db instance"} ]]
local function get_db(path, mode)
	if type(path) ~= "string" then
		error("get_db: path must be a string; got " .. type(path))
	end

	if not VALID_MODES[mode] then
		error("get_db: mode must be one of 'r', 'rw', 'wr' (write-only 'w' is deliberately unavailable in V1 — every write reads the root hash first); got " .. tostring(mode))
	end

	if path == ":memory:" and mode == "r" then
		error("get_db: ':memory:' requires write permission; mode 'r' has nothing to read")
	end

	-- Open with mode-appropriate flags. 'w' is enforced at the Fiona API
	-- surface, not by SQLite — the connection is read/write under the hood.
	local flags

	if mode == "r" then
		flags = sqlite3.OPEN_READONLY
	else
		flags = sqlite3.OPEN_READWRITE + sqlite3.OPEN_CREATE
	end

	local conn = sqlite3.open(path, flags)

	if not conn then
		error("get_db: failed to open database at '" .. path .. "'")
	end

	-- Check whether the Fiona schema is already applied. Presence of the
	-- hsa table is the marker; a full three-table check (hsa + relationships
	-- + meta) is a later refinement.
	local has_hsa = false

	for _ in conn:nrows("select name from sqlite_master where type = 'table' and name = 'hsa'") do
		has_hsa = true
	end

	if not has_hsa then
		if mode == "r" then
			error("get_db: opened in mode 'r' but the database has no Fiona schema; can't populate a read-only database")
		end

		local schema = read_file(SCHEMA_PATH)
		local ok = conn:exec(schema)

		if ok ~= sqlite3.OK then
			error("get_db: schema apply failed — " .. conn:errmsg())
		end
	end

	-- Set per-connection pragmas. Required by the schema's triggers.
	conn:exec("pragma foreign_keys = on")
	conn:exec("pragma recursive_triggers = on")

	return Db.new(conn, mode, path)
end

------------------------------------------------------------
-- Module exports
------------------------------------------------------------

return {
	get_db = get_db,
	Db     = Db,
}
