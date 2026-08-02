-- Tests for db:add_array() — inserts one collections row with type='a'
-- and null trace flags.

local h = require("helpers")
local fiona = require("fiona")

local function row_for(db, pk)
	for row in db._conn:nrows("select type, needs_trace, in_trace from collections where collection_pk = " .. pk) do
		return row
	end

	return nil
end

h.test("add_array returns a number for the new collection_pk", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_array()
	h.assert_eq(type(pk), "number", "pk is a number")
	h.assert_true(pk > 1, "new pk is above the root's pk of 1")
end)

h.test("add_array inserts row with type='a' and null trace flags", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_array()
	local row = row_for(db, pk)
	h.assert_eq(row.type, "a", "collections.type is 'a' (array)")
	h.assert_true(row.needs_trace == nil, "needs_trace is null at rest")
	h.assert_true(row.in_trace == nil, "in_trace is null at rest")
end)

h.test("add_array raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:add_array()
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)

h.test("consecutive add_array calls return distinct increasing pks", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk1 = db:add_array()
	local pk2 = db:add_array()
	h.assert_true(pk2 > pk1, "pk grows monotonically")
end)
