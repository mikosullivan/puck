-- Tests for db:set_array_element(parent, idx, child) — insert or replace
-- an (idx -> child) mapping under an array parent. Sparse indexes are
-- allowed. Replacement preserves neighboring positions (shift-down on
-- delete + shift-up on insert cancel).

local h = require("helpers")
local fiona = require("fiona")

local function rels_for(db, parent_pk)
	local out = {}

	for row in db._conn:nrows("select child, idx from relationships where parent = " .. parent_pk .. " order by idx") do
		table.insert(out, row)
	end

	return out
end

h.test("set_array_element with a new idx inserts", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_scalar("a")

	db:set_array_element(arr_pk, 0, child_pk)

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 1)
	h.assert_eq(rels[1].idx, 0)
	h.assert_eq(rels[1].child, child_pk)
end)

h.test("set_array_element allows sparse indexes", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()

	db:set_array_element(arr_pk, 0, db:add_scalar("a"))
	db:set_array_element(arr_pk, 100, db:add_scalar("far"))

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 2, "two entries")
	h.assert_eq(rels[1].idx, 0)
	h.assert_eq(rels[2].idx, 100, "sparse idx preserved")
end)

h.test("set_array_element replaces in place without shifting siblings", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()

	local a = db:add_scalar("a")
	local b = db:add_scalar("b")
	local c = db:add_scalar("c")
	local d = db:add_scalar("d")

	db:set_array_element(arr_pk, 0, a)
	db:set_array_element(arr_pk, 1, b)
	db:set_array_element(arr_pk, 2, c)
	db:set_array_element(arr_pk, 3, d)

	-- Replace idx 1 with a new scalar.
	local x = db:add_scalar("x")
	db:set_array_element(arr_pk, 1, x)

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 4, "still four entries")
	h.assert_eq(rels[1].idx, 0)  h.assert_eq(rels[1].child, a)
	h.assert_eq(rels[2].idx, 1)  h.assert_eq(rels[2].child, x)
	h.assert_eq(rels[3].idx, 2)  h.assert_eq(rels[3].child, c)
	h.assert_eq(rels[4].idx, 3)  h.assert_eq(rels[4].child, d)
end)

h.test("set_array_element preserves sparseness across a replace", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()

	db:set_array_element(arr_pk, 0, db:add_scalar("a"))
	db:set_array_element(arr_pk, 100, db:add_scalar("far"))

	-- Replace the sparse idx.
	local new_far = db:add_scalar("new_far")
	db:set_array_element(arr_pk, 100, new_far)

	local rels = rels_for(db, arr_pk)
	h.assert_eq(#rels, 2)
	h.assert_eq(rels[2].idx, 100, "sparse idx still 100 (no collapse)")
	h.assert_eq(rels[2].child, new_far)
end)

h.test("set_array_element rejects a hash parent via schema trigger", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_array_element(hash_pk, 0, child_pk)
	end, nil, "trigger blocks array entry under hash parent")
end)

h.test("set_array_element rejects negative idx at the Lua boundary", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_array_element(arr_pk, -1, child_pk)
	end, "non-negative integer", "negative idx rejected")
end)

h.test("set_array_element rejects float idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_array_element(arr_pk, 1.5, child_pk)
	end, "non-negative integer", "float idx rejected")
end)

h.test("set_array_element to the SAME child is a no-op", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_element(1, "root_arr", arr_pk)

	local child_pk = db:add_scalar("stable")
	db:set_array_element(arr_pk, 0, child_pk)

	-- Naïve DELETE+INSERT would have BR eat the child during the delete.
	db:set_array_element(arr_pk, 0, child_pk)

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. child_pk) do
		h.assert_eq(row.c, 1, "child still exists — no-op respected")
	end

	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr_pk .. " and idx = 0") do
		h.assert_eq(row.c, 1, "still exactly one (arr, 0) relationship")
	end
end)

h.test("set_array_element: replacing with a descendant of the old child now works (formerly pathological)", function()
	-- With mutable-child, this is a single UPDATE — same logic as the
	-- hash case above.
	local db = fiona.get_db(":memory:", "rw")

	local arr = db:add_array()
	db:set_hash_element(1, "root_arr", arr)

	local old_child = db:add_hash()
	db:set_array_element(arr, 0, old_child)

	local deep_child = db:add_scalar("under old_child")
	db:set_hash_element(old_child, "sub", deep_child)

	db:set_array_element(arr, 0, deep_child)  -- clean; used to raise FK

	local child_after
	for row in db._conn:nrows("select child from relationships where parent = " .. arr .. " and idx = 0") do
		child_after = row.child
	end
	h.assert_eq(child_after, deep_child, "arr[0] now points at deep_child")

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. old_child) do
		h.assert_eq(row.c, 0, "old_child was GCed")
	end

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. deep_child) do
		h.assert_eq(row.c, 1, "deep_child survived")
	end
end)

h.test("set_array_element raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_array_element(1, 0, 1)
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
