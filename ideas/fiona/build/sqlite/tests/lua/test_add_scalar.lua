-- Tests for db:add_scalar(value) — inserts one row into hsa with
-- type='s' and an st (n/s/b/u) derived from the Lua value's type.

local h = require("helpers")
local fiona = require("fiona")

local function row_for(db, pk)
	for row in db._conn:nrows("select type, st, value from hsa where hsa_pk = " .. pk) do
		return row
	end
end

h.test("add_scalar returns a number for the new hsa_pk", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(42)
	h.assert_eq(type(pk), "number", "pk is a number")
	h.assert_true(pk > 1, "new pk is greater than the root's pk of 1")
end)

h.test("add_scalar string stores st='s'", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar("hello")
	local row = row_for(db, pk)
	h.assert_eq(row.type, "s", "hsa.type is 's' (scalar)")
	h.assert_eq(row.st, "s", "st is 's' (string)")
	h.assert_eq(row.value, "hello", "value round-trips")
end)

h.test("add_scalar integer stores st='n'", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(42)
	local row = row_for(db, pk)
	h.assert_eq(row.st, "n", "st is 'n' for numbers")
	h.assert_eq(row.value, 42, "value round-trips")
end)

h.test("add_scalar float stores st='n'", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(3.14)
	local row = row_for(db, pk)
	h.assert_eq(row.st, "n", "st is 'n' for floats too")
	h.assert_eq(row.value, 3.14, "float value round-trips")
end)

h.test("add_scalar true stores st='b' value=1", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(true)
	local row = row_for(db, pk)
	h.assert_eq(row.st, "b", "st is 'b' for booleans")
	h.assert_eq(row.value, 1, "true stored as 1")
end)

h.test("add_scalar false stores st='b' value=0", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(false)
	local row = row_for(db, pk)
	h.assert_eq(row.st, "b", "st is 'b'")
	h.assert_eq(row.value, 0, "false stored as 0")
end)

h.test("add_scalar nil stores st='u' value=null", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar(nil)
	local row = row_for(db, pk)
	h.assert_eq(row.st, "u", "st is 'u' for null")
	h.assert_true(row.value == nil, "value column is NULL")
end)

h.test("add_scalar with no argument treated as nil", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_scalar()
	local row = row_for(db, pk)
	h.assert_eq(row.st, "u", "no-arg call produces null scalar")
end)

h.test("add_scalar rejects tables with a steering error", function()
	local db = fiona.get_db(":memory:", "rw")

	h.assert_raises(function()
		db:add_scalar({})
	end, "use add_hash / add_array", "table rejected with steering hint")
end)

h.test("add_scalar rejects functions", function()
	local db = fiona.get_db(":memory:", "rw")

	h.assert_raises(function()
		db:add_scalar(function() end)
	end, "value must be", "function rejected")
end)

h.test("add_scalar raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:add_scalar(42)
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)

h.test("consecutive add_scalar calls return distinct increasing pks", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk1 = db:add_scalar("a")
	local pk2 = db:add_scalar("b")
	local pk3 = db:add_scalar("c")
	h.assert_true(pk2 > pk1, "pk grows")
	h.assert_true(pk3 > pk2, "pk keeps growing")
end)
