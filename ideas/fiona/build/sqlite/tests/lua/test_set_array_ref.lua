-- Tests for db:set_array_ref(parent, idx, ref_pk) — anchor a collection
-- reference at a specific idx under an array parent. Sparse indexes are
-- allowed. Same shape-transition trio as the hash variant: fresh insert,
-- in-place update (same target = no-op, swing target), swing from
-- scalar-shape to ref-shape.

local h = require("helpers")
local fiona = require("fiona")

local function rels_for(db, parent_pk)
	local out = {}

	for row in db._conn:nrows("select child, idx, st, scalar from relationships where parent = " .. parent_pk .. " order by idx") do
		table.insert(out, row)
	end

	return out
end

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

h.test("set_array_ref: fresh insert at a new idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local child_pk = db:add_hash()
	db:set_array_ref(arr_pk, 0, child_pk)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.child, child_pk, "child stored")
	h.assert_true(row.st == nil, "st null on ref row")
	h.assert_true(row.scalar == nil, "scalar null on ref row")
end)

h.test("set_array_ref: sparse indexes preserved on insert", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_ref(arr_pk, 0,   db:add_hash())
	db:set_array_ref(arr_pk, 100, db:add_hash())

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 2, "two entries")
	h.assert_eq(rels[1].idx, 0)
	h.assert_eq(rels[2].idx, 100, "sparse idx preserved")
end)

h.test("set_array_ref: same target is a no-op", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local child_pk = db:add_hash()
	db:set_array_ref(arr_pk, 0, child_pk)
	db:set_array_ref(arr_pk, 0, child_pk)

	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. child_pk), 1,
		"child survived the no-op")
end)

h.test("set_array_ref: swing target GCs the old child if unreachable", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local old_child = db:add_hash()
	db:set_array_ref(arr_pk, 0, old_child)

	local new_child = db:add_hash()
	db:set_array_ref(arr_pk, 0, new_child)

	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. old_child), 0,
		"old child collected")
	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. new_child), 1,
		"new child survives")
end)

h.test("set_array_ref: swing target preserves neighboring positions", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local a = db:add_hash()
	local b = db:add_hash()
	local c = db:add_hash()
	local d = db:add_hash()

	db:set_array_ref(arr_pk, 0, a)
	db:set_array_ref(arr_pk, 1, b)
	db:set_array_ref(arr_pk, 2, c)
	db:set_array_ref(arr_pk, 3, d)

	local x = db:add_hash()
	db:set_array_ref(arr_pk, 1, x)

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 4, "still four entries")
	h.assert_eq(rels[1].idx, 0)  h.assert_eq(rels[1].child, a)
	h.assert_eq(rels[2].idx, 1)  h.assert_eq(rels[2].child, x)
	h.assert_eq(rels[3].idx, 2)  h.assert_eq(rels[3].child, c)
	h.assert_eq(rels[4].idx, 3)  h.assert_eq(rels[4].child, d)
end)

h.test("set_array_ref: swing from scalar shape to ref shape — no old collection to mark", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	db:set_array_scalar(arr_pk, 0, "old scalar")

	local ref_pk = db:add_hash()
	db:set_array_ref(arr_pk, 0, ref_pk)

	local row = shape_at(db, arr_pk, 0)
	h.assert_eq(row.child, ref_pk, "child set")
	h.assert_true(row.st == nil, "st cleared")
	h.assert_true(row.scalar == nil, "scalar cleared")
	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. ref_pk), 1,
		"ref survives")
end)

h.test("set_array_ref: rejects a hash parent (schema trigger)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_array_ref(hash_pk, 0, child_pk)
	end, nil, "trigger blocks array-style entry under hash parent")
end)

h.test("set_array_ref: rejects negative idx at the Lua boundary", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)
	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_array_ref(arr_pk, -1, child_pk)
	end, "non-negative integer", "negative idx rejected")
end)

h.test("set_array_ref: rejects float idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)
	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_array_ref(arr_pk, 1.5, child_pk)
	end, "non-negative integer", "float idx rejected")
end)

h.test("set_array_ref: raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_array_ref(1, 0, 1)
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
