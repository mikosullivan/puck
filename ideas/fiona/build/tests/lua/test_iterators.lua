-- Tests for db:keys / db:values / db:pairs — snapshot iterators over a
-- collection's entries. Verifies each variant yields the right shape
-- (keys, values, or key+value pairs), snapshot semantics (adding /
-- removing entries mid-walk doesn't affect the walk), and cleanup
-- (temp iterator rows drop when the walk exhausts).

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- keys
-- ------------------------------------------------------------

h.test("keys over an empty hash yields nothing", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	local count = 0
	for _ in db:keys(pk) do count = count + 1 end
	h.assert_eq(count, 0, "no keys in empty hash")
end)

h.test("keys over a hash yields insertion-order keys", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "alpha", 1)
	db:set_hash_scalar(pk, "beta", 2)
	db:set_hash_scalar(pk, "gamma", 3)

	local got = {}
	for k in db:keys(pk) do table.insert(got, k) end
	h.assert_eq(#got, 3, "three keys")
	h.assert_eq(got[1], "alpha", "first")
	h.assert_eq(got[2], "beta", "second")
	h.assert_eq(got[3], "gamma", "third")
end)

h.test("keys over an array yields idxs", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 1, "b")
	db:set_array_scalar(arr, 5, "far")

	local got = {}
	for k in db:keys(arr) do table.insert(got, k) end
	h.assert_eq(#got, 3, "three idxs")
	h.assert_eq(got[1], 0, "first idx")
	h.assert_eq(got[2], 1, "second idx")
	h.assert_eq(got[3], 5, "sparse idx preserved")
end)

h.test("keys raises for a nonexistent parent", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function()
		for _ in db:keys(9999) do end
	end, "no collection", "nonexistent parent rejected")
end)

-- ------------------------------------------------------------
-- values
-- ------------------------------------------------------------

h.test("values over a hash yields values (scalars and refs)", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "name", "alice")
	db:set_hash_scalar(pk, "age", 30)
	local child = db:add_hash()
	db:set_hash_ref(pk, "child", child)

	local got = {}
	for v in db:values(pk) do table.insert(got, v) end
	h.assert_eq(#got, 3, "three values")
	h.assert_eq(got[1], "alice", "string scalar")
	h.assert_eq(got[2], 30, "number scalar")
	h.assert_eq(got[3], child, "ref value is collection_pk")
end)

h.test("values over an array yields values", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 1, "b")

	local got = {}
	for v in db:values(arr) do table.insert(got, v) end
	h.assert_eq(#got, 2, "two values")
	h.assert_eq(got[1], "a", "idx 0")
	h.assert_eq(got[2], "b", "idx 1")
end)

-- ------------------------------------------------------------
-- pairs
-- ------------------------------------------------------------

h.test("pairs over a hash yields (key, value) tuples", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "a", 1)
	db:set_hash_scalar(pk, "b", 2)

	local got = {}
	for k, v in db:pairs(pk) do table.insert(got, {k, v}) end
	h.assert_eq(#got, 2, "two entries")
	h.assert_eq(got[1][1], "a", "first key")
	h.assert_eq(got[1][2], 1, "first value")
	h.assert_eq(got[2][1], "b", "second key")
	h.assert_eq(got[2][2], 2, "second value")
end)

h.test("pairs over an array yields (idx, value) tuples", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 5, "b")

	local got = {}
	for k, v in db:pairs(arr) do table.insert(got, {k, v}) end
	h.assert_eq(#got, 2, "two entries")
	h.assert_eq(got[1][1], 0, "first idx")
	h.assert_eq(got[1][2], "a", "first value")
	h.assert_eq(got[2][1], 5, "second idx")
	h.assert_eq(got[2][2], "b", "second value")
end)

-- ------------------------------------------------------------
-- Snapshot semantics
-- ------------------------------------------------------------

h.test("pairs snapshot: mid-walk insert doesn't appear in the current walk", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "a", 1)
	db:set_hash_scalar(pk, "b", 2)

	local seen = {}
	local iter = db:pairs(pk)
	local k, v = iter()
	table.insert(seen, k)
	-- Insert a third entry AFTER the walk began.
	db:set_hash_scalar(pk, "c", 3)
	while true do
		k, v = iter()
		if k == nil then break end
		table.insert(seen, k)
	end

	h.assert_eq(#seen, 2, "walk saw only the two originally snapshotted entries")
end)

h.test("pairs snapshot: mid-walk delete doesn't affect the walk", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "a", 1)
	db:set_hash_scalar(pk, "b", 2)
	db:set_hash_scalar(pk, "c", 3)

	local seen = {}
	local iter = db:pairs(pk)
	local k, v = iter()
	table.insert(seen, k)
	db:delete_hash_element(pk, "b")
	while true do
		k, v = iter()
		if k == nil then break end
		table.insert(seen, k)
	end

	-- b's row is deleted so its rel_pk in iterator_elements dangles; the
	-- join step returns no row and the iterator advances past it. That
	-- leaves "a" (already returned) plus "c" — b is silently skipped.
	h.assert_eq(#seen, 2, "walk saw only what still resolves")
	h.assert_eq(seen[1], "a", "first entry")
	h.assert_eq(seen[2], "c", "b was skipped")
end)

-- ------------------------------------------------------------
-- Cleanup
-- ------------------------------------------------------------

h.test("iterator row deletes after natural exhaustion", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_scalar(pk, "a", 1)

	for _ in db:keys(pk) do end

	-- After exhaustion, no leftover rows in the iterators table.
	local count
	for row in db._conn:nrows("select count(*) as c from iterators") do
		count = row.c
	end
	h.assert_eq(count, 0, "iterator row cleaned up")
end)
