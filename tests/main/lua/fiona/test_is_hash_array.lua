-- Tests for db:is_hash / db:is_array — cheap type probes for a given
-- collection_pk. Return true only when the row exists AND matches the
-- requested type. Complement of each other for existing rows; both
-- return false for nonexistent pks.

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- is_hash
-- ------------------------------------------------------------

h.test("is_hash returns true for the root collection", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:is_hash(1), true, "root is a hash")
end)

h.test("is_hash returns true for a fresh add_hash", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	h.assert_eq(db:is_hash(pk), true, "new hash reports true")
end)

h.test("is_hash returns false for an array", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_array()
	h.assert_eq(db:is_hash(pk), false, "array reports false")
end)

h.test("is_hash returns false for a nonexistent pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:is_hash(9999), false, "missing row reports false")
end)

h.test("is_hash raises on non-number argument", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:is_hash("root") end,
		"must be a number", "string arg rejected")
end)

-- ------------------------------------------------------------
-- is_array
-- ------------------------------------------------------------

h.test("is_array returns false for the root collection", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:is_array(1), false, "root is not an array")
end)

h.test("is_array returns true for a fresh add_array", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_array()
	h.assert_eq(db:is_array(pk), true, "new array reports true")
end)

h.test("is_array returns false for a hash", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	h.assert_eq(db:is_array(pk), false, "hash reports false")
end)

h.test("is_array returns false for a nonexistent pk", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:is_array(9999), false, "missing row reports false")
end)

h.test("is_array raises on non-number argument", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:is_array(nil) end,
		"must be a number", "nil arg rejected")
end)
