-- Tests for Db:delete_array_element. Covers the API contract (return
-- value, idempotency, guards) and the Ruby-array shift-down semantic
-- that the Lua-side Db:_shift_down_array two-phase 10^18 hop provides.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- Small helper: fresh DB with an array anchored at (root, 'arr'), the
-- array populated with N scalar entries packed at idx 0..N-1. Returns
-- the db handle and the array's pk.
local function fresh_array(n)
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)

	for i = 0, n - 1 do
		db:set_array_scalar(arr, i, (i + 1) * 10)
	end

	return db, arr
end

-- ------------------------------------------------------------
-- API contract
-- ------------------------------------------------------------

h.test("delete_array_element returns true when a row was removed", function()
	local db, arr = fresh_array(3)
	h.assert_eq(db:delete_array_element(arr, 1), true, "row removed")
end)

h.test("delete_array_element returns false when the slot was empty", function()
	local db, arr = fresh_array(3)
	h.assert_eq(db:delete_array_element(arr, 99), false, "no row at idx 99")
end)

h.test("delete_array_element raises on non-integer idx", function()
	local db, arr = fresh_array(3)

	h.assert_raises(function()
		db:delete_array_element(arr, 1.5)
	end, "non-negative integer", "float idx rejected")
end)

h.test("delete_array_element raises on a read-only handle", function()
	local path = "/tmp/fiona-delete-array-test.db"
	os.remove(path)
	os.remove(path .. "-journal")

	local db = fiona.get_db(path, "rw")
	local a = db:add_array()
	db:set_hash_ref(1, "arr", a)
	db:set_array_scalar(a, 0, 1)
	db._conn:close()

	local db_r = fiona.get_db(path, "r")

	h.assert_raises(function()
		db_r:delete_array_element(a, 0)
	end, "read-only", "rejected on r mode")

	db_r._conn:close()
	os.remove(path)
	os.remove(path .. "-journal")
end)

-- ------------------------------------------------------------
-- Shift-down semantics — arr.delete_at(N)
-- ------------------------------------------------------------

h.test("shift-down: dense case", function()
	-- [10, 20, 30, 40, 50] at idx 0..4. Delete idx 2.
	local db, arr = fresh_array(5)
	db:delete_array_element(arr, 2)

	local by_idx = {}

	for row in db._conn:nrows("select idx, scalar from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.scalar
	end

	h.assert_eq(by_idx[0], 10, "10 stays at 0")
	h.assert_eq(by_idx[1], 20, "20 stays at 1")
	h.assert_eq(by_idx[2], 40, "40 shifted from 3 to 2")
	h.assert_eq(by_idx[3], 50, "50 shifted from 4 to 3")
	h.assert_eq(by_idx[4], nil,"idx 4 no longer occupied")
end)

h.test("shift-down: preserves sparseness — shifts by exactly 1", function()
	-- Two entries at idx 0 and idx 1000. Delete idx 0 → remaining at 999.
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 1000, "b")

	db:delete_array_element(arr, 0)

	local row_idx, row_scalar
	for row in db._conn:nrows("select idx, scalar from relationships where parent = " .. arr) do
		row_idx = row.idx
		row_scalar = row.scalar
	end

	h.assert_eq(row_scalar, "b", "only b remains")
	h.assert_eq(row_idx,    999, "b shifted 1000 → 999; sparseness preserved")
end)

h.test("shift-down: last idx — no siblings to shift, straightforward removal", function()
	local db, arr = fresh_array(3)
	db:delete_array_element(arr, 2)

	local count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr) do
		count = row.c
	end

	h.assert_eq(count, 2, "two remain")

	local by_idx = {}

	for row in db._conn:nrows("select idx, scalar from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.scalar
	end

	h.assert_eq(by_idx[0], 10, "10 stays at 0")
	h.assert_eq(by_idx[1], 20, "20 stays at 1")
end)

h.test("shift-down: only element — array becomes empty", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, 1)

	db:delete_array_element(arr, 0)

	local count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr) do
		count = row.c
	end

	h.assert_eq(count, 0, "array is empty")
end)

h.test("shift-down: three-cluster sparse pattern", function()
	-- Sparse clusters at 0..2 and 100..102. Delete idx 1 in the first
	-- cluster; second cluster should shift too (all rows with idx > 1
	-- move down by 1). The two-phase 10^18 hop handles the whole set in
	-- one pass.
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)

	local values = {10, 20, 30, 40, 50, 60}
	local slots  = {0,  1,  2,  100, 101, 102}

	for i = 1, 6 do
		db:set_array_scalar(arr, slots[i], values[i])
	end

	db:delete_array_element(arr, 1)

	local by_idx = {}

	for row in db._conn:nrows("select idx, scalar from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.scalar
	end

	h.assert_eq(by_idx[0],   10, "10 stays at 0")
	h.assert_eq(by_idx[1],   30, "30 shifted from 2 to 1")
	h.assert_eq(by_idx[2],   nil, "idx 2 vacated by the shift")
	h.assert_eq(by_idx[99],  40, "40 shifted 100 → 99")
	h.assert_eq(by_idx[100], 50, "50 shifted 101 → 100")
	h.assert_eq(by_idx[101], 60, "60 shifted 102 → 101")
end)

-- ------------------------------------------------------------
-- GC integration — cascade deletes leave gaps, explicit shifts
-- ------------------------------------------------------------

h.test("cascade delete from drain leaves a gap in a surviving array parent", function()
	-- arr = [x, shared, z] where shared is a collection with a second
	-- anchor from root. Delete the second anchor — shared stays. Then
	-- delete arr[1] via delete_array_element (which shifts) — shared has
	-- no anchor and gets GC'd. arr should now be [x, z].
	local db = fiona.get_db(":memory:", "rw")

	local arr, shared = db:atomic(function()
		local a = db:add_array()
		db:set_hash_ref(1, "arr", a)
		local s = db:add_hash()
		db:set_array_scalar(a, 0, "x")
		db:set_array_ref(a, 1, s)
		db:set_array_scalar(a, 2, "z")
		db:set_hash_ref(1, "backup", s)  -- second anchor for `shared`
		return a, s
	end)

	db:delete_hash_element(1, "backup")  -- shared still anchored via arr[1]

	local exists
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. shared) do
		exists = row.c
	end

	h.assert_eq(exists, 1, "shared still alive after backup anchor removed")

	-- Now remove the arr entry — shared becomes an orphan and gets GC'd.
	db:delete_array_element(arr, 1)

	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. shared) do
		exists = row.c
	end

	h.assert_eq(exists, 0, "shared collected")

	-- After the explicit delete + shift, arr is [x, z] at idx 0, 1.
	local by_idx = {}

	for row in db._conn:nrows("select idx from relationships where parent = " .. arr) do
		by_idx[row.idx] = true
	end

	h.assert_true(by_idx[0], "idx 0 occupied")
	h.assert_true(by_idx[1], "idx 1 occupied (shifted from 2)")
	h.assert_true(by_idx[2] == nil, "idx 2 empty after shift")
end)
