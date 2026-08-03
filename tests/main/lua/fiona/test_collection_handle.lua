-- Tests for db:collection(pk) — the public handle API that makes
-- Fiona collections look like regular Lua hashes and arrays.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- Construction and identity
-- ------------------------------------------------------------

h.test("db:collection(pk) returns a handle for an existing hash", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	local handle = db:collection(pk)
	h.assert_eq(handle.pk, pk, "handle wraps the given pk")
	h.assert_eq(handle.type, "h", "type is 'h' for a hash")
end)

h.test("db:collection(pk) returns a handle for an existing array", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_array()
	local handle = db:collection(pk)
	h.assert_eq(handle.type, "a", "type is 'a' for an array")
end)

h.test("db:collection(pk) raises on nonexistent pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:collection(9999) end,
		"no collection", "nonexistent pk rejected")
end)

h.test("db:collection(1) wraps the root", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	h.assert_eq(root.pk, 1, "root pk is 1")
	h.assert_eq(root.type, "h", "root is a hash")
end)

-- ------------------------------------------------------------
-- Type predicates
-- ------------------------------------------------------------

h.test("handle:is_hash() returns true for hashes", function()
	local db = fiona.get_db(":memory:", "rw")
	local h1 = db:collection(db:add_hash())
	h.assert_eq(h1:is_hash(), true, "hash reports is_hash")
	h.assert_eq(h1:is_array(), false, "hash is not an array")
end)

h.test("handle:is_array() returns true for arrays", function()
	local db = fiona.get_db(":memory:", "rw")
	local a1 = db:collection(db:add_array())
	h.assert_eq(a1:is_array(), true, "array reports is_array")
	h.assert_eq(a1:is_hash(), false, "array is not a hash")
end)

-- ------------------------------------------------------------
-- Read: hashes
-- ------------------------------------------------------------

h.test("handle.key reads a scalar back", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "name", "alice")
	h.assert_eq(root.name, "alice", "scalar round-trip")
end)

h.test("handle.key reads a number scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "count", 42)
	h.assert_eq(root.count, 42, "number scalar")
end)

h.test("handle.key reads a boolean scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "flag", true)
	h.assert_eq(root.flag, true, "boolean scalar")
end)

h.test("handle.key returns nil for a missing key", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	h.assert_true(root.nope == nil, "missing key is nil")
end)

h.test("handle.key returns a handle when the slot is a ref", function()
	local db = fiona.get_db(":memory:", "rw")
	local child_pk = db:add_hash()
	db:set_hash_ref(1, "child", child_pk)
	local root = db:collection(1)
	local child = root.child
	h.assert_eq(type(child), "table", "ref returns a table (handle)")
	h.assert_eq(child.pk, child_pk, "wrapped handle's pk matches")
	h.assert_eq(child.type, "h", "wrapped handle's type is 'h'")
end)

h.test("nested access: handle.child.foo", function()
	local db = fiona.get_db(":memory:", "rw")
	local child_pk = db:add_hash()
	db:set_hash_ref(1, "child", child_pk)
	db:set_hash_scalar(child_pk, "value", "nested")
	local root = db:collection(1)
	h.assert_eq(root.child.value, "nested", "nested read works")
end)

-- ------------------------------------------------------------
-- Read: arrays
-- ------------------------------------------------------------

h.test("handle[idx] reads an array scalar (0-indexed)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_array_scalar(arr_pk, 0, "first")
	db:set_array_scalar(arr_pk, 1, "second")
	local arr = db:collection(arr_pk)
	h.assert_eq(arr[0], "first", "position 0")
	h.assert_eq(arr[1], "second", "position 1")
end)

h.test("handle[idx] returns nil for empty slot", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr = db:collection(db:add_array())
	h.assert_true(arr[3] == nil, "unset idx is nil")
end)

h.test("handle[idx] returns a handle when the slot is a ref", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_hash()
	db:set_array_ref(arr_pk, 0, child_pk)
	local arr = db:collection(arr_pk)
	local child = arr[0]
	h.assert_eq(type(child), "table", "ref returns a handle")
	h.assert_eq(child.pk, child_pk, "wrapped pk matches")
end)

-- ------------------------------------------------------------
-- Write: hashes via __newindex
-- ------------------------------------------------------------

h.test("handle.key = scalar writes a scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	root.name = "bob"
	h.assert_eq(db:get_hash_element(1, "name"), "bob", "write visible via direct API")
end)

h.test("handle.key = number writes a number scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	root.count = 7
	h.assert_eq(db:get_hash_element(1, "count"), 7, "number written")
end)

h.test("handle.key = boolean writes a boolean scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	root.flag = false
	h.assert_eq(db:get_hash_element(1, "flag"), false, "boolean written")
end)

h.test("handle.key = other_handle writes a ref", function()
	local db = fiona.get_db(":memory:", "rw")
	local child_pk = db:add_hash()
	local child = db:collection(child_pk)
	local root = db:collection(1)
	root.child = child
	h.assert_eq(db:get_hash_element(1, "child"), child_pk, "ref stored as child pk")
end)

h.test("handle.key = nil deletes the key", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "foo", "bar")
	root.foo = nil
	h.assert_true(db:get_hash_element(1, "foo") == nil, "key gone after nil write")
end)

-- ------------------------------------------------------------
-- Write: arrays via __newindex
-- ------------------------------------------------------------

h.test("handle[idx] = scalar writes an array scalar", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local arr = db:collection(arr_pk)
	arr[0] = "hello"
	h.assert_eq(db:get_array_element(arr_pk, 0), "hello", "array write visible")
end)

h.test("handle[idx] = other_handle writes a ref", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_hash()
	local arr = db:collection(arr_pk)
	arr[0] = db:collection(child_pk)
	h.assert_eq(db:get_array_element(arr_pk, 0), child_pk, "ref stored")
end)

-- ------------------------------------------------------------
-- Length
-- ------------------------------------------------------------

h.test("#handle for a hash returns entry count", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "a", 1)
	db:set_hash_scalar(1, "b", 2)
	h.assert_eq(#root, 2, "two entries")
end)

h.test("#handle for an array returns max idx + 1 (Ruby semantic)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local arr = db:collection(arr_pk)
	db:set_array_scalar(arr_pk, 0, "a")
	db:set_array_scalar(arr_pk, 5, "b")
	h.assert_eq(#arr, 6, "max idx 5 + 1 = length 6")
end)

-- ------------------------------------------------------------
-- Iteration
-- ------------------------------------------------------------

h.test("pairs(handle) iterates hash entries", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	db:set_hash_scalar(1, "a", 1)
	db:set_hash_scalar(1, "b", 2)

	local seen = {}
	for k, v in pairs(root) do
		seen[k] = v
	end

	h.assert_eq(seen.a, 1, "a=1")
	h.assert_eq(seen.b, 2, "b=2")
end)

h.test("pairs(handle) wraps refs as handles", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	local child_pk = db:add_hash()
	db:set_hash_scalar(child_pk, "name", "inner")
	db:set_hash_ref(1, "child", child_pk)

	local found_handle = nil
	for k, v in pairs(root) do
		if k == "child" then found_handle = v end
	end

	h.assert_eq(type(found_handle), "table", "ref yielded as handle")
	h.assert_eq(found_handle.name, "inner", "handle drills through")
end)

-- ------------------------------------------------------------
-- Equality and tostring
-- ------------------------------------------------------------

h.test("two handles for the same pk compare equal", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	local h1 = db:collection(pk)
	local h2 = db:collection(pk)
	h.assert_true(h1 == h2, "same-pk handles are equal")
end)

h.test("two handles for different pks compare unequal", function()
	local db = fiona.get_db(":memory:", "rw")
	local h1 = db:collection(db:add_hash())
	local h2 = db:collection(db:add_hash())
	h.assert_true(h1 ~= h2, "different-pk handles are unequal")
end)

h.test("tostring(handle) shows pk and type", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	local s = tostring(db:collection(pk))
	h.assert_true(s:find("pk=" .. pk), "tostring mentions pk")
	h.assert_true(s:find("type=h"), "tostring mentions type")
end)

-- ------------------------------------------------------------
-- Reserved field protection
-- ------------------------------------------------------------

h.test("writing to reserved field 'pk' raises", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	h.assert_raises(function() root.pk = 5 end,
		"reserved", "pk write refused")
end)

h.test("writing to reserved field 'type' raises", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)
	h.assert_raises(function() root.type = "a" end,
		"reserved", "type write refused")
end)

-- ------------------------------------------------------------
-- Full round-trip: build a small tree via handles only
-- ------------------------------------------------------------

h.test("build a small tree using handles end to end", function()
	local db = fiona.get_db(":memory:", "rw")
	local root = db:collection(1)

	-- Create user + admin children as hashes anchored via root.
	local user = db:collection(db:add_hash())
	user.name = "alice"
	user.age = 30
	root.user = user

	local admin = db:collection(db:add_hash())
	admin.name = "root"
	admin.level = 10
	root.admin = admin

	-- Read back through the root handle.
	h.assert_eq(root.user.name, "alice", "root.user.name")
	h.assert_eq(root.user.age, 30, "root.user.age")
	h.assert_eq(root.admin.name, "root", "root.admin.name")
	h.assert_eq(root.admin.level, 10, "root.admin.level")
end)
