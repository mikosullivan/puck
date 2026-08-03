-- Tests for db:set_hash_scalar(parent, key, value) — carry an inline
-- scalar under a hash parent. Covers each Lua-type mapping (nil → 'u',
-- boolean → 'b', number → 'n', string → 's'), fresh insert, same-value
-- no-op, value update on an existing scalar row, and shape swing from
-- ref to scalar (fires the mark trigger on the old ref).

local h = require("helpers")
local fiona = require("fiona")

local function shape_at(db, parent_pk, key)
	for row in db._conn:nrows(string.format(
		"select child, st, scalar, idx from relationships where parent = %d and key = '%s'",
		parent_pk, key
	)) do
		return row
	end

	return nil
end

local function row_count(db, sql)
	for row in db._conn:nrows(sql) do
		return row.c
	end

	return 0
end

h.test("set_hash_scalar: fresh string insert (st = 's')", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", "hello")

	local row = shape_at(db, hash_pk, "k")
	h.assert_true(row.child == nil, "child null on scalar row")
	h.assert_eq(row.st, "s", "st is 's'")
	h.assert_eq(row.scalar, "hello", "scalar stored verbatim")
	h.assert_eq(row.idx, 0, "first entry at idx 0")
end)

h.test("set_hash_scalar: fresh number insert (st = 'n')", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", 42)

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "n", "st is 'n'")
	h.assert_eq(row.scalar, 42, "number stored")
end)

h.test("set_hash_scalar: fresh boolean true → stored as 1 (st = 'b')", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", true)

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "b", "st is 'b'")
	h.assert_eq(row.scalar, 1, "true stored as 1")
end)

h.test("set_hash_scalar: fresh boolean false → stored as 0 (st = 'b')", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", false)

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "b", "st is 'b'")
	h.assert_eq(row.scalar, 0, "false stored as 0")
end)

h.test("set_hash_scalar: fresh nil → st = 'u' with null scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", nil)

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "u", "st is 'u' (null flavor)")
	h.assert_true(row.scalar == nil, "scalar column is null")
end)

h.test("set_hash_scalar: same value → no-op (row not touched)", function()
	-- Second set with identical (st, scalar) short-circuits before any
	-- write. Nothing observable changes; the row keeps its rel_pk.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", "stable")

	local rel_pk_before
	for row in db._conn:nrows("select rel_pk from relationships where parent = " .. hash_pk .. " and key = 'k'") do
		rel_pk_before = row.rel_pk
	end

	db:set_hash_scalar(hash_pk, "k", "stable")

	local rel_pk_after
	for row in db._conn:nrows("select rel_pk from relationships where parent = " .. hash_pk .. " and key = 'k'") do
		rel_pk_after = row.rel_pk
	end

	h.assert_eq(rel_pk_after, rel_pk_before, "rel_pk unchanged — same-value no-op")
end)

h.test("set_hash_scalar: update value on an existing scalar row (same st)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", "one")
	db:set_hash_scalar(hash_pk, "k", "two")

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "s", "still string")
	h.assert_eq(row.scalar, "two", "value updated")
end)

h.test("set_hash_scalar: change st (number → string) on an existing scalar row", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "k", 42)
	db:set_hash_scalar(hash_pk, "k", "forty-two")

	local row = shape_at(db, hash_pk, "k")
	h.assert_eq(row.st, "s", "st swapped to string")
	h.assert_eq(row.scalar, "forty-two", "new value stored")
end)

h.test("set_hash_scalar: swing shape from ref to scalar collects the old ref", function()
	-- Setup: hash_pk → old_ref (only anchor). Swinging (hash_pk, 'k') from
	-- ref to scalar fires the mark trigger on old_ref; drain finds it
	-- unreachable and deletes it.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	local old_ref = db:add_hash()
	db:set_hash_ref(hash_pk, "k", old_ref)

	db:set_hash_scalar(hash_pk, "k", "now a scalar")

	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. old_ref), 0,
		"old ref was GCed after the ref→scalar swing")

	local row = shape_at(db, hash_pk, "k")
	h.assert_true(row.child == nil, "child cleared")
	h.assert_eq(row.st, "s", "st set to 's'")
	h.assert_eq(row.scalar, "now a scalar", "scalar set")
end)

h.test("set_hash_scalar: preserves idx across value change (position stays put)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	db:set_hash_scalar(hash_pk, "alpha", 1)
	db:set_hash_scalar(hash_pk, "beta",  2)
	db:set_hash_scalar(hash_pk, "gamma", 3)

	local before = {}

	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk) do
		before[row.key] = row.idx
	end

	db:set_hash_scalar(hash_pk, "beta", 99)

	local after = {}

	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk) do
		after[row.key] = row.idx
	end

	h.assert_eq(after.alpha, before.alpha, "alpha idx unchanged")
	h.assert_eq(after.beta,  before.beta,  "beta idx unchanged")
	h.assert_eq(after.gamma, before.gamma, "gamma idx unchanged")
end)

h.test("set_hash_scalar: rejects table values (not a scalar)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	h.assert_raises(function()
		db:set_hash_scalar(hash_pk, "k", {})
	end, "scalar value must be", "table rejected as scalar")
end)

h.test("set_hash_scalar: rejects non-hash parent (schema trigger)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	h.assert_raises(function()
		db:set_hash_scalar(arr_pk, "k", "x")
	end, nil, "trigger blocks hash-style entry under array parent")
end)

h.test("set_hash_scalar: rejects non-string key at the Lua boundary", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	h.assert_raises(function()
		db:set_hash_scalar(hash_pk, 42, "x")
	end, "key must be a string", "non-string key")
end)

h.test("set_hash_scalar: raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_hash_scalar(1, "k", "x")
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
