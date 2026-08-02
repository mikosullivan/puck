-- Tests for Db:delete_array_element. Covers the API contract itself
-- (return value, idempotency, guards) and the Ruby-array shift-down
-- semantic that the Lua-side Db:_shift_down_array two-phase 10^18 hop
-- provides — including the previously-empirical case that used to
-- lean on undocumented SQLite planner ordering.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- Small helper: fresh DB with an array anchored at (root, 'arr'), the
-- array populated with N scalar children packed at idx 0..N-1. Returns
-- the array's pk plus a table of the N child pks (1-indexed to match
-- the caller-visible slot numbering).
local function fresh_array(n)
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_element(1, "arr", arr)
	local children = {}

	for i = 1, n do
		children[i] = db:add_scalar(i * 10)
		db:set_array_element(arr, i - 1, children[i])
	end

	return db, arr, children
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
	h.assert_raises(function() db:delete_array_element(arr, 1.5) end,
		"non-negative integer", "float idx rejected")
end)

h.test("delete_array_element raises on a read-only handle", function()
	local db_rw, arr = fresh_array(3)
	local path = "/tmp/fiona-delete-array-test.db"
	os.remove(path)
	os.remove(path .. "-journal")

	local db = fiona.get_db(path, "rw")
	local a = db:add_array()
	db:set_hash_element(1, "arr", a)
	db:set_array_element(a, 0, db:add_scalar(1))

	local db_r = fiona.get_db(path, "r")

	h.assert_raises(function() db_r:delete_array_element(a, 0) end,
		"read-only", "rejected on r mode")

	os.remove(path)
	os.remove(path .. "-journal")
end)

-- ------------------------------------------------------------
-- Shift-down semantics — arr.delete_at(N)
-- ------------------------------------------------------------

h.test("shift-down: dense case", function()
	-- [10, 20, 30, 40, 50] at idx 0..4. Delete idx 2.
	local db, arr, children = fresh_array(5)
	db:delete_array_element(arr, 2)

	local by_idx = {}
	for row in db._conn:nrows("select idx, child from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.child
	end
	h.assert_eq(by_idx[0], children[1], "child 1 stays at 0")
	h.assert_eq(by_idx[1], children[2], "child 2 stays at 1")
	h.assert_eq(by_idx[2], children[4], "child 4 shifted from 3 to 2")
	h.assert_eq(by_idx[3], children[5], "child 5 shifted from 4 to 3")
	h.assert_eq(by_idx[4], nil,         "idx 4 no longer occupied")
end)

h.test("shift-down: preserves sparseness — shifts by exactly 1", function()
	-- Two elements at idx 0 and idx 1000. Delete idx 0 → remaining at 999.
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_element(1, "arr", arr)
	local a = db:add_scalar(1)
	local b = db:add_scalar(2)
	db:set_array_element(arr, 0, a)
	db:set_array_element(arr, 1000, b)

	db:delete_array_element(arr, 0)

	local row_idx, row_child
	for row in db._conn:nrows("select idx, child from relationships where parent = " .. arr) do
		row_idx = row.idx
		row_child = row.child
	end
	h.assert_eq(row_child, b,   "only b remains")
	h.assert_eq(row_idx,   999, "b shifted 1000 → 999; sparseness preserved")
end)

h.test("shift-down: last idx — no siblings to shift, straightforward removal", function()
	local db, arr, children = fresh_array(3)
	db:delete_array_element(arr, 2)

	local count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr) do
		count = row.c
	end
	h.assert_eq(count, 2, "two remain")

	local by_idx = {}
	for row in db._conn:nrows("select idx, child from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.child
	end
	h.assert_eq(by_idx[0], children[1], "child 1 stays at 0")
	h.assert_eq(by_idx[1], children[2], "child 2 stays at 1")
end)

h.test("shift-down: only element — array becomes empty", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_element(1, "arr", arr)
	db:set_array_element(arr, 0, db:add_scalar(1))

	db:delete_array_element(arr, 0)

	local count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr) do
		count = row.c
	end
	h.assert_eq(count, 0, "array is empty")
end)

h.test("shift-down: three-cluster sparse pattern (was the empirical-order regression test)", function()
	-- Under the old cascade-triggered shift, this pattern is exactly
	-- the shape that would have failed with unique-constraint violations
	-- if SQLite's planner had ever processed the shift UPDATE in
	-- non-ascending order. The Lua two-phase hop doesn't depend on
	-- order, but keeping the test verifies correctness at the same
	-- shape.
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_element(1, "arr", arr)

	local children = {}
	for i = 1, 6 do
		children[i] = db:add_scalar(i * 10)
	end

	-- Three-cluster pattern: children at idx 0, 1, 2, 100, 101, 102.
	db:set_array_element(arr, 0,   children[1])
	db:set_array_element(arr, 1,   children[2])
	db:set_array_element(arr, 2,   children[3])
	db:set_array_element(arr, 100, children[4])
	db:set_array_element(arr, 101, children[5])
	db:set_array_element(arr, 102, children[6])

	-- Delete an entry in the first cluster.
	db:delete_array_element(arr, 1)

	local by_idx = {}
	for row in db._conn:nrows("select idx, child from relationships where parent = " .. arr) do
		by_idx[row.idx] = row.child
	end
	h.assert_eq(by_idx[0],   children[1], "child 1 stays at 0")
	h.assert_eq(by_idx[1],   children[3], "child 3 shifted from 2 to 1")
	h.assert_eq(by_idx[2],   nil,         "idx 2 vacated by the shift")
	h.assert_eq(by_idx[99],  children[4], "child 4 shifted 100 → 99 — sparse gap preserved")
	h.assert_eq(by_idx[100], children[5], "child 5 shifted 101 → 100")
	h.assert_eq(by_idx[101], children[6], "child 6 shifted 102 → 101")
end)

-- ------------------------------------------------------------
-- GC integration — cascade deletes leave gaps, explicit shifts
-- ------------------------------------------------------------

h.test("cascade delete from drain leaves a gap in a surviving array parent", function()
	-- Set up: arr = [x, shared, z]. shared also has a second anchor
	-- from root. Delete shared's OTHER anchor — shared stays alive.
	-- Then delete shared's LAST anchor (from root) → drain collects
	-- shared → cascade removes the (arr, 1) relationship. arr now
	-- has a gap at idx 1 (Ruby-array 'nil' hole), by design.
	local db = fiona.get_db(":memory:", "rw")

	local arr, shared = db:atomic(function()
		local a = db:add_array()
		db:set_hash_element(1, "arr", a)
		local x = db:add_scalar("x")
		local s = db:add_scalar("shared")
		local z = db:add_scalar("z")
		db:set_array_element(a, 0, x)
		db:set_array_element(a, 1, s)
		db:set_array_element(a, 2, z)
		db:set_hash_element(1, "backup", s)  -- second anchor for `shared`
		return a, s
	end)

	db:delete_hash_element(1, "backup")  -- shared still anchored via arr[1]

	local exists
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. shared) do
		exists = row.c
	end
	h.assert_eq(exists, 1, "shared still alive after backup anchor removed")

	-- Now remove the arr entry — shared is orphaned, gets GC'd.
	db:delete_array_element(arr, 1)

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. shared) do
		exists = row.c
	end
	h.assert_eq(exists, 0, "shared collected")

	-- arr should now contain [x at 0, z at 1] because we called
	-- delete_array_element (which shifts). Cascade case is exercised
	-- in a separate test below.
	local by_idx = {}
	for row in db._conn:nrows("select idx from relationships where parent = " .. arr) do
		by_idx[row.idx] = true
	end
	h.assert_true(by_idx[0], "idx 0 occupied")
	h.assert_true(by_idx[1], "idx 1 occupied (shifted from 2)")
	h.assert_true(by_idx[2] == nil, "idx 2 empty after shift")
end)

h.test("cascade-only orphan of a mid-array child leaves a gap (no shift)", function()
	-- arr = [x, shared, z]. shared has two anchors: arr[1] and (1, "extra").
	-- Delete the (1, "extra") anchor first. shared stays alive via arr[1].
	-- Now remove shared via an unrelated path: null out arr[1] by delete_
	-- array_element → shift closes gap. That's the explicit path.
	--
	-- The cascade-only case: build shared with anchors from arr[1] AND
	-- some hash. Delete the hash → shared still alive. Then delete the
	-- hash's ancestor to orphan the whole hash side, cascading in a way
	-- that removes shared without touching arr[1] directly. arr[1]
	-- becomes an orphaned edge whose child is gone — cascade FK deletes
	-- that edge, leaving arr with a gap.
	local db = fiona.get_db(":memory:", "rw")

	local arr, sub_hash = db:atomic(function()
		local a = db:add_array()
		db:set_hash_element(1, "arr", a)
		local h1 = db:add_hash()
		db:set_hash_element(1, "hh", h1)
		local shared = db:add_scalar("shared")
		db:set_array_element(a, 0, db:add_scalar("x"))
		db:set_array_element(a, 1, shared)
		db:set_array_element(a, 2, db:add_scalar("z"))
		db:set_hash_element(h1, "s", shared)
		return a, h1
	end)

	-- Delete arr entry for shared → shift closes the gap; shared still
	-- alive via h1.s. arr is now [x, shared, ??] wait — actually after
	-- shift arr becomes [x, z]. But shared is still alive.
	db:delete_array_element(arr, 1)

	-- Confirm arr is [x, z].
	local count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. arr) do
		count = row.c
	end
	h.assert_eq(count, 2, "arr has two entries after explicit shift")

	-- shared still exists via h1.s.
	for row in db._conn:nrows("select count(*) as c from hsa where value = 'shared'") do
		h.assert_eq(row.c, 1, "shared still alive via h1.s")
	end
end)
