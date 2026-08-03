-- Tests for Db:get_hash_element and Db:get_array_element. Point-lookup
-- returns a collection_pk for ref rows, a Lua-typed scalar for scalar
-- rows, or nil for empty slots.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- get_hash_element
-- ------------------------------------------------------------

h.test("get_hash_element returns nil for a missing key", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_true(db:get_hash_element(1, "nope") == nil, "missing key returns nil")
end)

h.test("get_hash_element returns a string scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "name", "alice")
	h.assert_eq(db:get_hash_element(1, "name"), "alice", "string round-trips")
end)

h.test("get_hash_element returns a number scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "count", 42)
	h.assert_eq(db:get_hash_element(1, "count"), 42, "number round-trips")
end)

h.test("get_hash_element returns a float scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "pi", 3.14)
	h.assert_eq(db:get_hash_element(1, "pi"), 3.14, "float round-trips")
end)

h.test("get_hash_element returns boolean true", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "flag", true)
	h.assert_eq(db:get_hash_element(1, "flag"), true, "true round-trips")
end)

h.test("get_hash_element returns boolean false", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "flag", false)
	h.assert_eq(db:get_hash_element(1, "flag"), false, "false round-trips")
end)

h.test("get_hash_element returns nil for a stored null scalar (V1 collapses to nil)", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "unset", nil)
	h.assert_true(db:get_hash_element(1, "unset") == nil, "null scalar reads back as nil")
end)

h.test("get_hash_element returns collection_pk for a ref row", function()
	local db = fiona.get_db(":memory:", "rw")
	local child = db:add_hash()
	db:set_hash_ref(1, "child", child)
	h.assert_eq(db:get_hash_element(1, "child"), child, "ref returns collection_pk")
end)

h.test("get_hash_element after swing from ref to scalar returns scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	db:set_hash_scalar(1, "k", "now a scalar")
	h.assert_eq(db:get_hash_element(1, "k"), "now a scalar", "swing observed")
end)

h.test("get_hash_element after swing from scalar to ref returns ref", function()
	local db = fiona.get_db(":memory:", "rw")
	db:set_hash_scalar(1, "k", "was scalar")
	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	h.assert_eq(db:get_hash_element(1, "k"), child, "swing observed")
end)

h.test("get_hash_element raises on non-string key", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_hash_element(1, 42) end,
		"must be a string", "integer key rejected")
end)

h.test("get_hash_element raises on non-number parent_pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:get_hash_element("root", "k") end,
		"must be a number", "string parent rejected")
end)

-- ------------------------------------------------------------
-- get_array_element
-- ------------------------------------------------------------

h.test("get_array_element returns nil for an empty slot", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	h.assert_true(db:get_array_element(arr, 0) == nil, "empty slot returns nil")
end)

h.test("get_array_element returns a scalar at a populated slot", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 3, "value at 3")
	h.assert_eq(db:get_array_element(arr, 3), "value at 3", "scalar round-trips")
end)

h.test("get_array_element returns collection_pk at a populated ref slot", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	local child = db:add_hash()
	db:set_array_ref(arr, 0, child)
	h.assert_eq(db:get_array_element(arr, 0), child, "ref returns collection_pk")
end)

h.test("get_array_element returns nil for gaps in a sparse array", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	db:set_array_scalar(arr, 0, "first")
	db:set_array_scalar(arr, 1000, "far")
	h.assert_true(db:get_array_element(arr, 500) == nil, "middle-of-sparse-array is nil")
end)

h.test("get_array_element raises on non-integer idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	h.assert_raises(function() db:get_array_element(arr, 1.5) end,
		"non-negative integer", "float idx rejected")
end)

h.test("get_array_element raises on negative idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:add_array()
	db:set_hash_ref(1, "arr", arr)
	h.assert_raises(function() db:get_array_element(arr, -1) end,
		"non-negative integer", "negative idx rejected")
end)

