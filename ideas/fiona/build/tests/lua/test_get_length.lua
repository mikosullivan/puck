-- Tests for Db:get_hash_length and Db:get_array_length. Hash length =
-- count of entries. Array length = highest occupied idx + 1 (Ruby
-- semantic). Both raise on type mismatch.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- get_hash_length
-- ------------------------------------------------------------

h.test("get_hash_length: 0 for an empty hash", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:get_hash_length(1), 0, "root starts empty")
end)

h.test("get_hash_length: reflects added entries", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "a", 1)
	db:set_hash_scalar(1, "b", 2)
	db:set_hash_scalar(1, "c", 3)
	h.assert_eq(db:get_hash_length(1), 3, "three entries")
end)

h.test("get_hash_length: mixed scalar and ref entries both count", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "name", "alice")
	local child = db:add_hash()
	db:set_hash_ref(1, "child", child)
	h.assert_eq(db:get_hash_length(1), 2, "scalar and ref both counted")
end)

h.test("get_hash_length: drops after delete", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "a", 1)
	db:set_hash_scalar(1, "b", 2)
	db:delete_hash_element(1, "a")
	h.assert_eq(db:get_hash_length(1), 1, "one entry left")
end)

h.test("get_hash_length: raises on an array parent", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	h.assert_raises(function() db:get_hash_length(arr) end,
		"must be a hash", "array parent rejected")
end)

h.test("get_hash_length: raises on nonexistent parent", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_hash_length(9999) end,
		"no collection", "nonexistent parent rejected")
end)

h.test("get_hash_length: raises on non-number parent_pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_hash_length("root") end,
		"must be a number", "string parent rejected")
end)

-- ------------------------------------------------------------
-- get_array_length
-- ------------------------------------------------------------

h.test("get_array_length: 0 for an empty array", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	h.assert_eq(db:get_array_length(arr), 0, "empty array has length 0")
end)

h.test("get_array_length: max idx + 1 for a dense array", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 1, "b")
	db:set_array_scalar(arr, 2, "c")
	h.assert_eq(db:get_array_length(arr), 3, "dense array of 3 → length 3")
end)

h.test("get_array_length: Ruby semantic — sparse array reports 1001 for arr[1000] = value", function()
	-- The whole point of the split from get_hash_length.
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 1000, "foo")
	h.assert_eq(db:get_array_length(arr), 1001, "sparse array length is max idx + 1")
end)

h.test("get_array_length: sparse with multiple entries", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 5, "b")
	db:set_array_scalar(arr, 100, "c")
	h.assert_eq(db:get_array_length(arr), 101, "length tracks max idx, not entry count")
end)

h.test("get_array_length: shrinks after delete of the top element", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, "a")
	db:set_array_scalar(arr, 5, "b")

	h.assert_eq(db:get_array_length(arr), 6, "length 6 before delete")

	db:delete_array_element(arr, 5)  -- shifts nothing above; but 5 was the top

	-- After delete_array_element on the top element, arr has only 'a' at
	-- idx 0. Length is 1.
	h.assert_eq(db:get_array_length(arr), 1, "length collapses to 1 after top delete")
end)

h.test("get_array_length: raises on a hash parent", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_array_length(1) end,
		"must be an array", "hash parent rejected")
end)

h.test("get_array_length: raises on nonexistent parent", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_array_length(9999) end,
		"no collection", "nonexistent parent rejected")
end)

h.test("get_array_length: raises on non-number parent_pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_array_length("arr") end,
		"must be a number", "string parent rejected")
end)
