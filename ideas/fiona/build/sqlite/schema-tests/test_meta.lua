-- Tests for the meta table.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

h.test("meta table exists after fresh_db", function()
	local db = h.fresh_db()
	local found = false

	for row in db:nrows("select name from sqlite_master where type = 'table' and name = 'meta'") do
		if row.name == "meta" then found = true end
	end

	h.assert_true(found, "meta table exists in the schema")
end)

h.test("meta table has schema = '1.0' after fresh_db", function()
	local db = h.fresh_db()
	local schema

	for row in db:nrows("select value from meta where key = 'schema'") do
		schema = row.value
	end

	h.assert_eq(schema, "1.0", "initial schema version")
end)

h.test("meta.key is a primary key — duplicate insert raises", function()
	local db = h.fresh_db()

	h.assert_raises(function()
		db:exec("insert into meta (key, value) values ('schema', '2.0')")
		if db:errmsg() ~= "not an error" then error(db:errmsg()) end
	end, "UNIQUE", "duplicate schema key raises")
end)

h.test("meta setting can be updated", function()
	local db = h.fresh_db()

	db:exec("update meta set value = '2.0' where key = 'schema'")

	local schema
	for row in db:nrows("select value from meta where key = 'schema'") do
		schema = row.value
	end

	h.assert_eq(schema, "2.0", "schema updated to 2.0")
end)

h.test("meta supports arbitrary settings — insert new keys works", function()
	local db = h.fresh_db()

	db:exec("insert into meta (key, value) values ('last_migrated', '2026-08-01')")

	local val
	for row in db:nrows("select value from meta where key = 'last_migrated'") do
		val = row.value
	end

	h.assert_eq(val, "2026-08-01", "custom setting stored and retrieved")
end)
