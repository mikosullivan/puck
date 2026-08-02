-- Tests for db:set_array_scalar(parent, idx, value) — carry an inline
-- scalar at a specific idx under an array parent. Same Lua-type mapping
-- as set_hash_scalar; same shape-transition trio (fresh insert, in-place
-- update, swing from ref to scalar).

local h = require("helpers")
local fiona = require("fiona")

local function shape_at(db, parent_pk, idx)
	for row in db._conn:nrows(string.format(
		"select child, st, scalar from relationships where parent = %d and idx = %d",
		parent_pk, idx
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

h.test("set_array_scalar: fresh string insert (st = 's')", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, "hello")

	local row = shape_at(db, arr_pk, 0)
	h.assert_true(row.child == nil, "child null on scalar row")
	h.assert_eq(row.st, "s", "st is 's'")
	h.assert_eq(row.scalar, "hello", "scalar stored")
end)

h.test("set_array_scalar: fresh number insert (st = 'n')", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, 42)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.st, "n", "st is 'n'")
	h.assert_eq(row.scalar, 42, "number stored")
end)

h.test("set_array_scalar: fresh boolean true stored as 1", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, true)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.st, "b", "st is 'b'")
	h.assert_eq(row.scalar, 1, "true stored as 1")
end)

h.test("set_array_scalar: fresh boolean false stored as 0", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, false)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.st, "b", "st is 'b'")
	h.assert_eq(row.scalar, 0, "false stored as 0")
end)

h.test("set_array_scalar: fresh nil → st = 'u'", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, nil)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.st, "u", "st is 'u' (null flavor)")
	h.assert_true(row.scalar == nil, "scalar column is null")
end)

h.test("set_array_scalar: same value → no-op (row not touched)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, "stable")

	local rel_pk_before
	for row in db._conn:nrows("select rel_pk from relationships where parent = " .. arr_pk .. " and idx = 0") do
		rel_pk_before = row.rel_pk
	end

	db:set_array_scalar(arr_pk, 0, "stable")

	local rel_pk_after
	for row in db._conn:nrows("select rel_pk from relationships where parent = " .. arr_pk .. " and idx = 0") do
		rel_pk_after = row.rel_pk
	end

	h.assert_eq(rel_pk_after, rel_pk_before, "rel_pk unchanged — same-value no-op")
end)

h.test("set_array_scalar: update value on an existing scalar row", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, 1)
	db:set_array_scalar(arr_pk, 0, 2)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.st, "n", "still number")
	h.assert_eq(row.scalar, 2, "value updated")
end)

h.test("set_array_scalar: swing shape from ref to scalar collects the old ref", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local old_ref = db:add_hash()
	db:set_array_ref(arr_pk, 0, old_ref)

	db:set_array_scalar(arr_pk, 0, "now a scalar")

	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. old_ref), 0,
		"old ref was GCed after the ref→scalar swing")

	local row = shape_at(db, arr_pk, 0)
	h.assert_true(row.child == nil, "child cleared")
	h.assert_eq(row.st, "s", "st set to 's'")
	h.assert_eq(row.scalar, "now a scalar", "scalar set")
end)

h.test("set_array_scalar: sparse indexes preserved", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, "a")
	db:set_array_scalar(arr_pk, 100, "far")

	-- Replace the sparse idx.
	db:set_array_scalar(arr_pk, 100, "new far")

	local row = shape_at(db, arr_pk, 100)
	h.assert_eq(row.scalar, "new far", "sparse slot updated")
end)

h.test("set_array_scalar: rejects table values (not a scalar)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	h.assert_raises(function()
		db:set_array_scalar(arr_pk, 0, {})
	end, "scalar value must be", "table rejected as scalar")
end)

h.test("set_array_scalar: rejects a hash parent (schema trigger)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	h.assert_raises(function()
		db:set_array_scalar(hash_pk, 0, "x")
	end, nil, "trigger blocks array-style entry under hash parent")
end)

h.test("set_array_scalar: rejects negative idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	h.assert_raises(function()
		db:set_array_scalar(arr_pk, -1, "x")
	end, "non-negative integer", "negative idx rejected")
end)

h.test("set_array_scalar: rejects float idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	h.assert_raises(function()
		db:set_array_scalar(arr_pk, 1.5, "x")
	end, "non-negative integer", "float idx rejected")
end)

h.test("set_array_scalar: raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_array_scalar(1, 0, "x")
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
