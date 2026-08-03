-- Tests for db:meta() — returns every row in the meta table as
-- {[key] = value}. Fresh DB has exactly one row: schema = '2.0'.

local h = require("helpers")
local fiona = require("fiona")

h.test("db:meta() returns a table", function()
	local db = fiona.get_db(":memory:", "rw")
	local m = db:meta()
	h.assert_eq(type(m), "table", "meta should return a table")
end)

h.test("db:meta().schema is '2.0' on a fresh DB", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_eq(db:meta().schema, "2.0", "schema row on fresh DB")
end)

h.test("db:meta() reflects new rows inserted into the meta table", function()
	local db = fiona.get_db(":memory:", "rw")
	db._conn:exec("insert into meta (key, value) values ('note', 'hello')")

	local m = db:meta()
	h.assert_eq(m.schema, "2.0", "schema still present")
	h.assert_eq(m.note, "hello", "new row shows up")
end)

h.test("db:meta() reflects updated values", function()
	local db = fiona.get_db(":memory:", "rw")
	db._conn:exec("update meta set value = '3.0' where key = 'schema'")
	h.assert_eq(db:meta().schema, "3.0", "updated value visible")
end)

h.test("db:meta() works on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")
	h.assert_eq(r:meta().schema, "2.0", "meta readable in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
