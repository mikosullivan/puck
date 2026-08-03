--[[
{
	"module": "fiona",
	"role": "Fiona's Lua interface for the SQLite backend. Exposes get_db(path, mode) which returns a Db object. Collections (hashes and arrays) live in the collections table; scalars live inline in the relationships table via st + scalar columns. There is no add_scalar — scalars are set directly via set_hash_scalar / set_array_scalar.",
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
local TEMP_SCHEMA_PATH = this_dir .. "fiona-temp.sql"

local function read_file(path)
	local f, err = io.open(path, "r")

	if not f then
		error("cannot open schema at " .. path .. " — " .. tostring(err))
	end

	local content = f:read("*a")
	f:close()
	return content
end

-- Classify a Lua value into (st, stored) for a scalar-carrying row.
-- Rejects table / function / userdata: those aren't scalars, and Fiona
-- has no path to store them.
--[[ {"in": {"value": "nil | boolean | number | string"}, "out": "st (string), stored (any) — CHECK-compatible pair for the relationships (st, scalar) columns"} ]]
local function classify_scalar(value)
	local t = type(value)

	if value == nil then
		return "u", nil
	elseif t == "boolean" then
		return "b", value and 1 or 0
	elseif t == "number" then
		return "n", value
	elseif t == "string" then
		return "s", value
	end

	error("scalar value must be nil, boolean, number, or string — got " .. t)
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

--[[ {"in": {}, "out": "integer — the new row's collection_pk"} ]]
function Db:add_hash()
	if self._mode == "r" then
		error("add_hash: database is opened in read-only mode ('r'); writes are not allowed")
	end

	self:_exec("insert into collections (type) values ('h')", nil, "add_hash: insert")
	return self._conn:last_insert_rowid()
end

--[[ {"in": {}, "out": "integer — the new row's collection_pk"} ]]
function Db:add_array()
	if self._mode == "r" then
		error("add_array: database is opened in read-only mode ('r'); writes are not allowed")
	end

	self:_exec("insert into collections (type) values ('a')", nil, "add_array: insert")
	return self._conn:last_insert_rowid()
end

------------------------------------------------------------
-- Set operations. Two flavors for each parent shape:
--   set_*_ref     — anchor an existing collection (child column set)
--   set_*_scalar  — carry an inline scalar (st + scalar columns set)
-- Each method handles the three shape-transition cases at (parent, slot):
-- fresh insert, in-place update of same-shape row, and swing between
-- ref-shape and scalar-shape. Mark trigger on the schema catches the
-- "was a collection edge, now isn't" cases so the drain can GC.
------------------------------------------------------------

--[[ {"in": {"parent_pk": "integer", "key": "string", "ref_pk": "integer — an existing collection_pk"}, "out": "nil"} ]]
function Db:set_hash_ref(parent_pk, key, ref_pk)
	if self._mode == "r" then
		error("set_hash_ref: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_hash_ref: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(key) ~= "string" then
		error("set_hash_ref: key must be a string; got " .. type(key))
	end

	if type(ref_pk) ~= "number" then
		error("set_hash_ref: ref_pk must be a number; got " .. type(ref_pk))
	end

	return self:atomic(function()
		local existing_child, existing_st = self:_row_shape_hash(parent_pk, key)

		if existing_child == nil and existing_st == nil then
			-- Fresh slot — insert.
			local next_idx = self:_query_one(
				"select coalesce(max(idx) + 1, 0) from relationships where parent = :p",
				{p = parent_pk})

			self:_exec(
				"insert into relationships (parent, child, key, idx) values (:p, :c, :k, :i)",
				{p = parent_pk, c = ref_pk, k = key, i = next_idx},
				"set_hash_ref: insert")
		elseif existing_child ~= nil then
			-- Same-shape row (already a ref). No-op if same target.
			if existing_child == ref_pk then
				return
			end

			-- Swing the child — mark trigger fires to needs_trace the old child.
			self:_exec(
				"update relationships set child = :c where parent = :p and key = :k",
				{c = ref_pk, p = parent_pk, k = key},
				"set_hash_ref: update")
		else
			-- Existing row is scalar — swing shape to ref. child transitions
			-- from null to ref_pk (mark trigger doesn't fire, correctly:
			-- old.child was null so nothing to mark).
			self:_exec(
				"update relationships set child = :c, st = null, scalar = null where parent = :p and key = :k",
				{c = ref_pk, p = parent_pk, k = key},
				"set_hash_ref: swing from scalar to ref")
		end
	end)
end

--[[ {"in": {"parent_pk": "integer", "key": "string", "value": "nil | boolean | number | string"}, "out": "nil"} ]]
function Db:set_hash_scalar(parent_pk, key, value)
	if self._mode == "r" then
		error("set_hash_scalar: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_hash_scalar: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(key) ~= "string" then
		error("set_hash_scalar: key must be a string; got " .. type(key))
	end

	local new_st, new_scalar = classify_scalar(value)

	return self:atomic(function()
		local existing_child, existing_st, existing_scalar =
			self:_row_shape_hash_full(parent_pk, key)

		if existing_child == nil and existing_st == nil then
			-- Fresh slot — insert.
			local next_idx = self:_query_one(
				"select coalesce(max(idx) + 1, 0) from relationships where parent = :p",
				{p = parent_pk})

			self:_exec(
				"insert into relationships (parent, key, idx, st, scalar) values (:p, :k, :i, :st, :sc)",
				{p = parent_pk, k = key, i = next_idx, st = new_st, sc = new_scalar},
				"set_hash_scalar: insert")
		elseif existing_child ~= nil then
			-- Existing row is a ref — swing shape to scalar. child transitions
			-- from non-null to null; mark trigger fires and marks the old
			-- collection as needs_trace.
			self:_exec(
				"update relationships set child = null, st = :st, scalar = :sc where parent = :p and key = :k",
				{st = new_st, sc = new_scalar, p = parent_pk, k = key},
				"set_hash_scalar: swing from ref to scalar")
		else
			-- Same-shape row (already a scalar). No-op if same value.
			if existing_st == new_st and existing_scalar == new_scalar then
				return
			end

			self:_exec(
				"update relationships set st = :st, scalar = :sc where parent = :p and key = :k",
				{st = new_st, sc = new_scalar, p = parent_pk, k = key},
				"set_hash_scalar: update")
		end
	end)
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer >= 0", "ref_pk": "integer — an existing collection_pk"}, "out": "nil"} ]]
function Db:set_array_ref(parent_pk, idx, ref_pk)
	if self._mode == "r" then
		error("set_array_ref: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_array_ref: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(idx) ~= "number" or idx < 0 or math.floor(idx) ~= idx then
		error("set_array_ref: idx must be a non-negative integer; got " .. tostring(idx))
	end

	if type(ref_pk) ~= "number" then
		error("set_array_ref: ref_pk must be a number; got " .. type(ref_pk))
	end

	return self:atomic(function()
		local existing_child, existing_st = self:_row_shape_array(parent_pk, idx)

		if existing_child == nil and existing_st == nil then
			self:_exec(
				"insert into relationships (parent, child, idx) values (:p, :c, :i)",
				{p = parent_pk, c = ref_pk, i = idx},
				"set_array_ref: insert")
		elseif existing_child ~= nil then
			if existing_child == ref_pk then
				return
			end

			self:_exec(
				"update relationships set child = :c where parent = :p and idx = :i",
				{c = ref_pk, p = parent_pk, i = idx},
				"set_array_ref: update")
		else
			self:_exec(
				"update relationships set child = :c, st = null, scalar = null where parent = :p and idx = :i",
				{c = ref_pk, p = parent_pk, i = idx},
				"set_array_ref: swing from scalar to ref")
		end
	end)
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer >= 0", "value": "nil | boolean | number | string"}, "out": "nil"} ]]
function Db:set_array_scalar(parent_pk, idx, value)
	if self._mode == "r" then
		error("set_array_scalar: database is opened in read-only mode ('r'); writes are not allowed")
	end

	if type(parent_pk) ~= "number" then
		error("set_array_scalar: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(idx) ~= "number" or idx < 0 or math.floor(idx) ~= idx then
		error("set_array_scalar: idx must be a non-negative integer; got " .. tostring(idx))
	end

	local new_st, new_scalar = classify_scalar(value)

	return self:atomic(function()
		local existing_child, existing_st, existing_scalar =
			self:_row_shape_array_full(parent_pk, idx)

		if existing_child == nil and existing_st == nil then
			self:_exec(
				"insert into relationships (parent, idx, st, scalar) values (:p, :i, :st, :sc)",
				{p = parent_pk, i = idx, st = new_st, sc = new_scalar},
				"set_array_scalar: insert")
		elseif existing_child ~= nil then
			self:_exec(
				"update relationships set child = null, st = :st, scalar = :sc where parent = :p and idx = :i",
				{st = new_st, sc = new_scalar, p = parent_pk, i = idx},
				"set_array_scalar: swing from ref to scalar")
		else
			if existing_st == new_st and existing_scalar == new_scalar then
				return
			end

			self:_exec(
				"update relationships set st = :st, scalar = :sc where parent = :p and idx = :i",
				{st = new_st, sc = new_scalar, p = parent_pk, i = idx},
				"set_array_scalar: update")
		end
	end)
end

-- Row-shape lookups used by the set_* methods. Return (child, st) —
-- both nil means "no row at that slot"; child non-nil means "ref shape";
-- st non-nil means "scalar shape". The _full variants also return the
-- scalar value for the same-value no-op check.
--[[ {"in": {"parent_pk": "integer", "key": "string"}, "out": "child, st"} ]]
function Db:_row_shape_hash(parent_pk, key)
	local stmt = self:_stmt(
		"select child, st from relationships where parent = :p and key = :k")
	stmt:bind_names({p = parent_pk, k = key})

	local child, st

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
	end

	stmt:reset()
	return child, st
end

--[[ {"in": {"parent_pk": "integer", "key": "string"}, "out": "child, st, scalar"} ]]
function Db:_row_shape_hash_full(parent_pk, key)
	local stmt = self:_stmt(
		"select child, st, scalar from relationships where parent = :p and key = :k")
	stmt:bind_names({p = parent_pk, k = key})

	local child, st, scalar

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
		scalar = stmt:get_value(2)
	end

	stmt:reset()
	return child, st, scalar
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer"}, "out": "child, st"} ]]
function Db:_row_shape_array(parent_pk, idx)
	local stmt = self:_stmt(
		"select child, st from relationships where parent = :p and idx = :i")
	stmt:bind_names({p = parent_pk, i = idx})

	local child, st

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
	end

	stmt:reset()
	return child, st
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer"}, "out": "child, st, scalar"} ]]
function Db:_row_shape_array_full(parent_pk, idx)
	local stmt = self:_stmt(
		"select child, st, scalar from relationships where parent = :p and idx = :i")
	stmt:bind_names({p = parent_pk, i = idx})

	local child, st, scalar

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
		scalar = stmt:get_value(2)
	end

	stmt:reset()
	return child, st, scalar
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
			"select type from collections where collection_pk = :p",
			{p = parent_pk})

		if parent_type == "a" then
			self:_shift_down_array(parent_pk, idx)
		end

		return true
	end)
end

-- Two-phase 10^18 hop that shifts every sibling with idx > deleted_idx
------------------------------------------------------------
-- Reading elements. Point-lookup navigation, not queries. Returns the
-- value at a slot (collection_pk if the row holds a reference, scalar
-- if it holds an inline value, nil if the slot is empty). No parent-
-- existence check on get_element — nonexistent parent implies no
-- matching row implies nil, same as an empty slot on a real parent.
-- The get_length methods do check parent type since the count vs
-- max(idx)+1 semantic is method-specific.
------------------------------------------------------------

-- Interpret a scalar row's (st, scalar) columns as a Lua value. Boolean
-- storage is 0/1 in the scalar column; everything else is what it looks
-- like. Null-scalar (st = 'u') returns Lua nil, indistinguishable from
-- "no row" — per spec, V1 collapses those cases.
--[[ {"in": {"st": "string — 's'/'n'/'b'/'u'", "scalar": "any"}, "out": "any — Lua-typed value"} ]]
local function decode_scalar(st, scalar)
	if st == "b" then
		return scalar == 1
	end

	return scalar
end

--[[ {"in": {"parent_pk": "integer", "key": "string"}, "out": "collection_pk (integer) | scalar (Lua value) | nil"} ]]
function Db:get_hash_element(parent_pk, key)
	if type(parent_pk) ~= "number" then
		error("get_hash_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(key) ~= "string" then
		error("get_hash_element: key must be a string; got " .. type(key))
	end

	local stmt = self:_stmt(
		"select child, st, scalar from relationships where parent = :p and key = :k")
	stmt:bind_names({p = parent_pk, k = key})

	local child, st, scalar

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
		scalar = stmt:get_value(2)
	end

	stmt:reset()

	if child ~= nil then
		return child
	end

	return decode_scalar(st, scalar)
end

--[[ {"in": {"parent_pk": "integer", "idx": "integer >= 0"}, "out": "collection_pk (integer) | scalar (Lua value) | nil"} ]]
function Db:get_array_element(parent_pk, idx)
	if type(parent_pk) ~= "number" then
		error("get_array_element: parent_pk must be a number; got " .. type(parent_pk))
	end

	if type(idx) ~= "number" or idx < 0 or math.floor(idx) ~= idx then
		error("get_array_element: idx must be a non-negative integer; got " .. tostring(idx))
	end

	local stmt = self:_stmt(
		"select child, st, scalar from relationships where parent = :p and idx = :i")
	stmt:bind_names({p = parent_pk, i = idx})

	local child, st, scalar

	if stmt:step() == sqlite3.ROW then
		child = stmt:get_value(0)
		st = stmt:get_value(1)
		scalar = stmt:get_value(2)
	end

	stmt:reset()

	if child ~= nil then
		return child
	end

	return decode_scalar(st, scalar)
end

--[[ {"in": {"parent_pk": "integer"}, "out": "integer — count of entries"} ]]
function Db:get_hash_length(parent_pk)
	if type(parent_pk) ~= "number" then
		error("get_hash_length: parent_pk must be a number; got " .. type(parent_pk))
	end

	local parent_type = self:_query_one(
		"select type from collections where collection_pk = :p",
		{p = parent_pk})

	if parent_type == nil then
		error("get_hash_length: no collection with collection_pk = " .. parent_pk)
	end

	if parent_type ~= "h" then
		error("get_hash_length: parent " .. parent_pk .. " must be a hash; got type '" .. parent_type .. "'")
	end

	return self:_query_one(
		"select count(*) from relationships where parent = :p",
		{p = parent_pk}) or 0
end

--[[ {"in": {"parent_pk": "integer"}, "out": "integer — max(idx) + 1 (Ruby-array semantic)"} ]]
function Db:get_array_length(parent_pk)
	if type(parent_pk) ~= "number" then
		error("get_array_length: parent_pk must be a number; got " .. type(parent_pk))
	end

	local parent_type = self:_query_one(
		"select type from collections where collection_pk = :p",
		{p = parent_pk})

	if parent_type == nil then
		error("get_array_length: no collection with collection_pk = " .. parent_pk)
	end

	if parent_type ~= "a" then
		error("get_array_length: parent " .. parent_pk .. " must be an array; got type '" .. parent_type .. "'")
	end

	return self:_query_one(
		"select coalesce(max(idx) + 1, 0) from relationships where parent = :p",
		{p = parent_pk}) or 0
end

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
-- with the GC state fully drained: no committed collections row ever
-- has needs_trace or in_trace set. This is what turns "the delete of a
-- relationship orphans something" into a durable "the orphan and any
-- downstream unreachable subgraph are gone by the time the caller
-- gets control back."
--
-- Idiomatic use is grouping "create + associate" so no orphan
-- collection is observable between them:
--
--     db:atomic(function()
--         local pk = db:add_hash()
--         db:set_hash_ref(parent, "k", pk)
--     end)
--
-- Returns whatever fn returns (all values preserved via table.pack /
-- table.unpack). On error, rolls back the savepoint (drain NOT run —
-- the whole transaction is aborted, so any transient needs_trace /
-- in_trace marks disappear along with it) and re-raises the original
-- message unchanged.
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
-- While any collections row has needs_trace = 1:
--   1. Pick one such row (the seed). Partial index collections_needs_trace
--      makes this a near-zero lookup.
--   2. Mark the seed in_trace = 1.
--   3. Propagate in_trace upward via a single recursive-CTE UPDATE:
--      every collection with a relationship pointing to something already
--      in_trace becomes in_trace itself. Fix-point in one statement.
--      Root can be marked here — the alive check reads root's in_trace
--      directly, and the collections_root_no_needs_trace trigger
--      guards the flag that must never touch root (needs_trace),
--      leaving in_trace free.
--   4. Alive check: read root's in_trace. If set, one of root's
--      descendants sits in the closure — seed is anchored. Clear the
--      closure (including root's in_trace), clear seed's needs_trace,
--      loop.
--   5. Dead: bulk DELETE FROM collections WHERE in_trace = 1. Cascade
--      FKs remove their relationships; the mark trigger on
--      relationships fires per cascade-delete and adds cascade-orphaned
--      collections to needs_trace. Loop picks up the next seed.
--
-- Final assertion: no row has needs_trace = 1 or in_trace = 1 at exit.
-- This is what "no saved state has the flags set" comes down to — if
-- the assertion trips, we have a drain bug and the transaction should
-- fail loudly rather than commit with lingering marks.
------------------------------------------------------------

--[[ {"in": {}, "out": "nil — mutates collections"} ]]
function Db:_drain_needs_trace()
	while true do
		local seed = self:_query_one(
			"select collection_pk from collections where needs_trace = 1 limit 1")

		if not seed then
			break
		end

		-- Mark seed and propagate upward to fix-point in a single
		-- recursive-CTE UPDATE. The CTE seeds from :seed directly (rather
		-- than reading `where in_trace = 1`) so we don't need a separate
		-- pre-mark UPDATE. Root is included in the closure — the
		-- collections_root_no_needs_trace trigger only blocks needs_trace,
		-- not in_trace, precisely so this UPDATE can land the mark on
		-- root and the alive check can be a single primary-key read.
		-- Statement is cached via _exec across drain iterations.
		self:_exec([[
			update collections set in_trace = 1
			where in_trace is null
				and collection_pk in (
					with recursive upward(pk) as (
						select :seed
						union
						select r.parent from relationships r
						join upward on r.child = upward.pk
					)
					select pk from upward
				)
		]], {seed = seed}, "drain: seed + propagate in_trace")

		-- Alive iff root ended up in_trace after propagation.
		local alive = self:_query_one(
			"select in_trace from collections where collection_pk = 1")

		if alive then
			-- Seed and its trace are anchored via root. Clear the flags
			-- and move on to the next needs_trace row (if any).
			self:_exec(
				"update collections set in_trace = null where in_trace = 1",
				nil,
				"drain: clear in_trace on alive branch")
			self:_exec(
				"update collections set needs_trace = null where collection_pk = :pk",
				{pk = seed},
				"drain: clear needs_trace on alive seed")
		else
			-- The whole in_trace closure is unreachable. Delete. Root is
			-- not in this set (if it were, we'd be in the alive branch).
			-- FK cascade drops their relationships; the mark trigger fires
			-- on each cascade-delete and populates needs_trace for the
			-- next iteration.
			self:_exec(
				"delete from collections where in_trace = 1",
				nil,
				"drain: dead-set delete")
		end
	end

	-- Assertion — no flag should be set at drain exit.
	local leftover = self:_query_one(
		"select count(*) from collections where needs_trace = 1 or in_trace = 1")

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

-- 'w' is deliberately excluded — every Fiona write reads the root
-- collection first, so a strict write-only handle can't perform any
-- operation Fiona exposes. Documented as a conscious V1 choice in the
-- spec (see fiona/specs/index.md, "No write-only mode in V1").
-- If a real append-only use case surfaces, 'w' can be reinstated with
-- the root-read exception carved out.
local VALID_MODES = {r = true, rw = true, wr = true}

--[[ {"in": {"path": "string (file path or ':memory:')", "mode": "string ('r' | 'rw' | 'wr')"}, "out": "Db instance"} ]]
local function get_db(path, mode)
	if type(path) ~= "string" then
		error("get_db: path must be a string; got " .. type(path))
	end

	if not VALID_MODES[mode] then
		error("get_db: mode must be one of 'r', 'rw', 'wr' (write-only 'w' is deliberately unavailable in V1 — every write reads the root collection first); got " .. tostring(mode))
	end

	if path == ":memory:" and mode == "r" then
		error("get_db: ':memory:' requires write permission; mode 'r' has nothing to read")
	end

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

	-- Presence of the collections table is the marker for "schema is
	-- applied" — a full three-table check (collections + relationships
	-- + meta) is a later refinement.
	local has_collections = false

	for _ in conn:nrows("select name from sqlite_master where type = 'table' and name = 'collections'") do
		has_collections = true
	end

	if not has_collections then
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

	-- Per-connection iterator scratch tables — applied every open, since
	-- temp tables live in the connection's temp schema and don't survive
	-- close. Schema definition lives at fiona-temp.sql alongside fiona.sql.
	local temp_schema = read_file(TEMP_SCHEMA_PATH)
	local temp_ok = conn:exec(temp_schema)

	if temp_ok ~= sqlite3.OK then
		error("get_db: temp schema apply failed — " .. conn:errmsg())
	end

	return Db.new(conn, mode, path)
end

------------------------------------------------------------
-- Module exports
------------------------------------------------------------

return {
	get_db = get_db,
	Db     = Db,
}
