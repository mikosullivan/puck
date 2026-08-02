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
		-- Prepared-statement cache, keyed by SQL text. Populated lazily by
		-- Db:_stmt(). Statements live as long as the Db instance and are
		-- finalized implicitly when the connection is closed.
		_stmts = {},
		-- SAVEPOINT depth tracked by Db:atomic(). Increments on entry,
		-- decrements on release/rollback. Db:_drain_needs_trace runs
		-- inside the outer atomic just before it releases, so no
		-- committed state ever has needs_trace or in_trace set.
		_atomic_depth = 0,
	}, Db)
end

-- Return a cached prepared statement, preparing on first use. The
-- statement is reset() before return so it's ready to bind and step
-- regardless of what any previous caller left it in (mid-scan, errored,
-- or fully done). Callers still need to reset() a SELECT after
-- consuming its ROW value so the read cursor doesn't hold state
-- through the following write.
--[[ {"in": {"sql": "string"}, "out": "prepared statement handle"} ]]
function Db:_stmt(sql)
	local stmt = self._stmts[sql]

	if not stmt then
		stmt = self._conn:prepare(sql)

		if not stmt then
			error("_stmt: prepare failed for '" .. sql .. "' — " .. self._conn:errmsg())
		end

		self._stmts[sql] = stmt
	end

	stmt:reset()
	return stmt
end

-- One-value SELECT helper. Runs sql with the given name→value bindings
-- (or nothing if binds is nil), returns column 0 of the first row, or
-- nil if no row. Resets the statement after use so the read cursor
-- doesn't hold state through any subsequent write on the same table.
--
-- Callers never touch prepare / bind / step / reset directly, so
-- "forgot to reset" is not a possible bug.
--[[ {"in": {"sql": "string", "binds": "table? — name→value map"}, "out": "any — column 0 of first row, or nil"} ]]
function Db:_query_one(sql, binds)
	local stmt = self:_stmt(sql)

	if binds then
		stmt:bind_names(binds)
	end

	local value

	if stmt:step() == sqlite3.ROW then
		value = stmt:get_value(0)
	end

	stmt:reset()
	return value
end

-- Write helper. Runs sql with the given name→value bindings (or nothing
-- if binds is nil), asserts step returns DONE, resets. `label` is the
-- error prefix used if step didn't return DONE — pick one that identifies
-- which caller failed (e.g., "add_hash: insert").
--[[ {"in": {"sql": "string", "binds": "table? — name→value map", "label": "string — error prefix"}, "out": "nil"} ]]
function Db:_exec(sql, binds, label)
	local stmt = self:_stmt(sql)

	if binds then
		stmt:bind_names(binds)
	end

	local rc = stmt:step()
	stmt:reset()

	if rc ~= sqlite3.DONE then
		error(label .. " failed — " .. self._conn:errmsg())
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

	self:_exec("insert into hsa (type, st, value) values ('h', null, null)", nil, "add_hash: insert")
	return self._conn:last_insert_rowid()
end

--[[ {"in": {}, "out": "integer — the new row's hsa_pk"} ]]
function Db:add_array()
	if self._mode == "r" then
		error("add_array: database is opened in read-only mode ('r'); writes are not allowed")
	end

	self:_exec("insert into hsa (type, st, value) values ('a', null, null)", nil, "add_array: insert")
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

	self:_exec(
		"insert into hsa (type, st, value) values ('s', :st, :val)",
		{st = st, val = stored},
		"add_scalar: insert")

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

	-- Implicit atomic: if the update path fires and swings a child, the
	-- mark trigger marks the old child needs_trace; drain runs at the
	-- outer atomic() boundary before commit.
	return self:atomic(function()
		-- Look up existing (parent, key) — if present, we update the child
		-- in place (identity-immutable, content-mutable). If absent, we
		-- insert a fresh entry at max_idx + 1.
		local existing_child = self:_query_one(
			"select child from relationships where parent = :p and key = :k",
			{p = parent_pk, k = key})

		-- Same child already there — nothing to do.
		if existing_child == child_pk then
			return
		end

		if existing_child then
			-- Update in place. The mark trigger fires on the swing and
			-- adds the old child to the needs_trace worklist.
			self:_exec(
				"update relationships set child = :c where parent = :p and key = :k",
				{c = child_pk, p = parent_pk, k = key},
				"set_hash_element: update")
		else
			-- New key — append at max+1 (or 0 if empty).
			local next_idx = self:_query_one(
				"select coalesce(max(idx) + 1, 0) from relationships where parent = :p",
				{p = parent_pk})

			self:_exec(
				"insert into relationships (parent, child, key, idx) values (:p, :c, :k, :i)",
				{p = parent_pk, c = child_pk, k = key, i = next_idx},
				"set_hash_element: insert")
		end
	end)
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

	return self:atomic(function()
		-- Same shape as set_hash_element: update in place if (parent, idx)
		-- is occupied; insert at that idx if not.
		local existing_child = self:_query_one(
			"select child from relationships where parent = :p and idx = :i",
			{p = parent_pk, i = idx})

		if existing_child == child_pk then
			return
		end

		if existing_child then
			self:_exec(
				"update relationships set child = :c where parent = :p and idx = :i",
				{c = child_pk, p = parent_pk, i = idx},
				"set_array_element: update")
		else
			self:_exec(
				"insert into relationships (parent, child, idx) values (:p, :c, :i)",
				{p = parent_pk, c = child_pk, i = idx},
				"set_array_element: insert")
		end
	end)
end

--[[ {"in": {"parent_pk": "integer", "key": "string"}, "out": "boolean — true if a row was removed, false if no such (parent, key)"} ]]
function Db:delete_hash_element(parent_pk, key)
	if self._mode == "r" then
		error("delete_hash_element: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("delete_hash_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(key) ~= "string" then
		error("delete_hash_element: key must be a string; got " .. type(key))
	end

	return self:atomic(function()
		-- Look up first so we can report whether anything actually went;
		-- the delete itself is idempotent, but callers may want to know.
		local existing = self:_query_one(
			"select 1 from relationships where parent = :p and key = :k",
			{p = parent_pk, k = key})

		if not existing then
			return false
		end

		self:_exec(
			"delete from relationships where parent = :p and key = :k",
			{p = parent_pk, k = key},
			"delete_hash_element")

		return true
	end)
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer >= 0"}, "out": "boolean — true if a row was removed, false if no such (parent, idx)"} ]]
function Db:delete_array_element(parent_pk, idx)
	if self._mode == "r" then
		error("delete_array_element: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("delete_array_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(idx) ~= "number" or idx < 0 or math.floor(idx) ~= idx then
		error("delete_array_element: idx must be a non-negative integer; got " .. tostring(idx))
	end

	return self:atomic(function()
		local existing = self:_query_one(
			"select 1 from relationships where parent = :p and idx = :i",
			{p = parent_pk, i = idx})

		if not existing then
			return false
		end

		self:_exec(
			"delete from relationships where parent = :p and idx = :i",
			{p = parent_pk, i = idx},
			"delete_array_element")

		-- Ruby's arr.delete_at semantic: every sibling with a higher idx
		-- moves down by 1. Only fires for array parents — hashes leave
		-- gaps because hash users address by key, not idx.
		local parent_type = self:_query_one(
			"select type from hsa where hsa_pk = :p",
			{p = parent_pk})

		if parent_type == "a" then
			self:_shift_down_array(parent_pk, idx)
		end

		return true
	end)
end

-- Two-phase 10^18 hop that shifts every sibling with idx > deleted_idx
-- down by 1. Same safe-range pattern the shift-on-update trigger uses:
-- phase 1 moves each row into the 10^18 range at (old_idx - 1 + 10^18),
-- phase 2 subtracts 10^18 to land at (old_idx - 1). All target slots are
-- empty at the moment they're written to, so no unique-constraint
-- collision happens regardless of the order SQLite processes rows —
-- no dependency on planner behavior.
--[[ {"in": {"parent_pk": "integer", "deleted_idx": "integer"}, "out": "nil"} ]]
function Db:_shift_down_array(parent_pk, deleted_idx)
	-- Phase 1: hop siblings into the safe range.
	self:_exec(
		"update relationships set idx = idx + 999999999999999999 where parent = :p and idx > :i",
		{p = parent_pk, i = deleted_idx},
		"shift_down_array: phase 1")

	-- Phase 2: hop them back down, net effect: each shifted by -1.
	self:_exec(
		"update relationships set idx = idx - 1000000000000000000 where parent = :p and idx >= 1000000000000000000",
		{p = parent_pk},
		"shift_down_array: phase 2")
end

------------------------------------------------------------
-- Db:atomic(fn) — run fn() atomically via a SAVEPOINT. Any Fiona API
-- calls inside fn commit together on success, roll back together on
-- error. Nests correctly (SQLite savepoints stack).
--
-- The outermost atomic() also runs _drain_needs_trace() just before
-- releasing its savepoint, so every user-observable transition ends
-- with the GC state fully drained: no committed hsa row ever has
-- needs_trace or in_trace set. This is what turns "the delete of a
-- relationship orphans something" into a durable "the orphan and any
-- downstream unreachable subgraph are gone by the time the caller
-- gets control back."
--
-- Idiomatic use is grouping "create + associate" so no orphan hsa row
-- is observable between them:
--
--     db:atomic(function()
--         local pk = db:add_scalar(42)
--         db:set_hash_element(parent, "k", pk)
--     end)
--
-- Returns whatever fn returns (single value). On error, rolls back the
-- savepoint (drain NOT run — the whole transaction is aborted, so any
-- transient needs_trace / in_trace marks disappear along with it) and
-- re-raises the original message unchanged.
------------------------------------------------------------

--[[ {"in": {"fn": "function — Fiona API calls to bundle atomically"}, "out": "any... — whatever fn returns, all values preserved"} ]]
function Db:atomic(fn)
	self._atomic_depth = self._atomic_depth + 1
	self._conn:exec("savepoint sp")

	-- table.pack captures every return value from fn (pcall returns
	-- ok + fn's rets), so `return db:atomic(function() return a, b end)`
	-- forwards both a and b, not just a.
	local packed = table.pack(pcall(fn))
	local ok = packed[1]

	if ok then
		-- Drain runs INSIDE the savepoint, BEFORE release, and ONLY at
		-- the outermost boundary. Nested atomic() calls stack their
		-- own savepoints and defer to the outer for drain.
		if self._atomic_depth == 1 then
			self:_drain_needs_trace()
		end

		self._atomic_depth = self._atomic_depth - 1
		self._conn:exec("release sp")
		return table.unpack(packed, 2, packed.n)
	end

	self._atomic_depth = self._atomic_depth - 1
	self._conn:exec("rollback to sp")
	self._conn:exec("release sp")
	error(packed[2], 0)
end

------------------------------------------------------------
-- Db:_drain_needs_trace() — Drinian-style backward-trace GC.
--
-- While any hsa row has needs_trace = 1:
--   1. Pick one such row (the seed). Partial index hsa_needs_trace
--      makes this a near-zero lookup.
--   2. Mark the seed in_trace = 1 (root is never marked — the
--      hsa_no_update_root trigger would reject it, and the check on
--      hsa_pk <> 1 in the update below skips it defensively).
--   3. Propagate in_trace upward via a single recursive-CTE UPDATE:
--      every hsa row that has a relationship pointing to something
--      already in_trace becomes in_trace itself. Fix-point in one
--      statement.
--   4. Alive check: does root have a direct edge to any in_trace
--      row? If yes, one of root's descendants sits in the closure —
--      the seed is anchored, clear the closure, clear the seed's
--      needs_trace, loop.
--   5. Dead: bulk DELETE FROM hsa WHERE in_trace = 1. Cascade FKs
--      remove those rows' relationships; the mark trigger on
--      relationships fires per cascade-delete and adds the cascade-
--      orphaned children to needs_trace. Loop picks up the next seed.
--
-- Final assertion: no row has needs_trace = 1 or in_trace = 1 at exit.
-- This is what "no saved state has the flags set" comes down to — if
-- the assertion trips, we have a drain bug and the transaction should
-- fail loudly rather than commit with lingering marks.
------------------------------------------------------------

--[[ {"in": {}, "out": "nil — mutates hsa"} ]]
function Db:_drain_needs_trace()
	while true do
		local seed = self:_query_one(
			"select hsa_pk from hsa where needs_trace = 1 limit 1")

		if not seed then
			break
		end

		-- Seed enters in_trace. Root can never be a seed (mark triggers
		-- gate on old.child <> 1) so we don't need to guard here.
		self:_exec(
			"update hsa set in_trace = 1 where hsa_pk = :pk",
			{pk = seed},
			"drain: mark seed in_trace")

		-- Propagate upward to fix-point. Root is excluded from the mark
		-- so the no-update-root trigger never fires — the alive check
		-- below reads root's incidence into the closure without needing
		-- root itself to carry a flag.
		self._conn:exec([[
			update hsa set in_trace = 1
			where hsa_pk <> 1
				and in_trace is null
				and hsa_pk in (
					with recursive upward(pk) as (
						select hsa_pk from hsa where in_trace = 1
						union
						select r.parent from relationships r
						join upward on r.child = upward.pk
					)
					select pk from upward
				)
		]])

		-- Alive iff root has a direct outgoing edge to any in_trace row.
		-- Any longer path root → X → … → seed forces X into in_trace
		-- during propagation, so the direct-edge check catches it.
		local alive = self:_query_one([[
			select 1 from relationships
			where parent = 1
				and child in (select hsa_pk from hsa where in_trace = 1)
			limit 1
		]])

		if alive then
			-- Seed and its trace are anchored via root. Clear the flags
			-- and move on to the next needs_trace row (if any).
			self._conn:exec("update hsa set in_trace = null where in_trace = 1")
			self:_exec(
				"update hsa set needs_trace = null where hsa_pk = :pk",
				{pk = seed},
				"drain: clear needs_trace on alive seed")
		else
			-- The whole in_trace closure is unreachable. Delete. FK
			-- cascade drops their relationships; the mark trigger fires
			-- on each cascade-delete and populates needs_trace for the
			-- next iteration.
			self._conn:exec("delete from hsa where in_trace = 1")
		end
	end

	-- Assertion — no flag should be set at drain exit.
	local leftover = self:_query_one(
		"select count(*) from hsa where needs_trace = 1 or in_trace = 1")

	if leftover ~= 0 then
		error(string.format(
			"_drain_needs_trace: %d rows still marked at drain exit — this is a bug",
			leftover))
	end
end

------------------------------------------------------------
-- Explicit teardown — finalizes cached statements and closes the
-- underlying connection. Idempotent. Also wired as __gc below so the
-- safety net fires even for callers who never call close() themselves.
--
-- Set on the metatable BEFORE any Db instance is created via
-- Db.new() — Lua 5.4 activates __gc based on whether it's present on
-- the metatable at setmetatable() time, so this line has to run at
-- module load before get_db() is ever called.
------------------------------------------------------------

--[[ {"in": {}, "out": "nil"} ]]
function Db:close()
	if not self._conn then
		return
	end

	for _, stmt in pairs(self._stmts) do
		stmt:finalize()
	end

	self._stmts = {}
	self._conn:close()
	self._conn = nil
end

Db.__gc = Db.close

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
