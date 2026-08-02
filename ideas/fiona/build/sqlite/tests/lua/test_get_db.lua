-- Tests for fiona.get_db: object creation, param validation, and
-- fresh-schema application. Runs against ':memory:' by default so no
-- disk cleanup is needed; a couple of tests use os.tmpname() for the
-- file-backed cases.

local h = require("helpers")
local fiona = require("fiona")

h.test("get_db returns a Db object for ':memory:' with 'rw'", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_true(db, "db should be truthy")
	h.assert_eq(getmetatable(db), fiona.Db, "db should be a Db instance")
end)

h.test("get_db accepts each valid mode against ':memory:'", function()
	-- 'r' isn't valid with ':memory:' — tested separately below.
	for _, mode in ipairs({"rw", "wr"}) do
		local db = fiona.get_db(":memory:", mode)
		h.assert_true(db, "mode " .. mode .. " should produce a db")
	end
end)

h.test("get_db raises on an invalid mode", function()
	h.assert_raises(function()
		fiona.get_db(":memory:", "read")
	end, "mode must be one of", "invalid mode string")

	h.assert_raises(function()
		fiona.get_db(":memory:", nil)
	end, "mode must be one of", "nil mode")
end)

h.test("get_db rejects 'w' — write-only is deliberately absent in V1", function()
	h.assert_raises(function()
		fiona.get_db(":memory:", "w")
	end, "mode must be one of", "w rejected")
end)

h.test("get_db raises when mode is 'r' against ':memory:'", function()
	h.assert_raises(function()
		fiona.get_db(":memory:", "r")
	end, "':memory:' requires write permission", "memory + r")
end)

h.test("get_db raises when path isn't a string", function()
	h.assert_raises(function()
		fiona.get_db(nil, "rw")
	end, "path must be a string", "nil path")
end)

h.test("get_db applies the schema to a fresh ':memory:' database", function()
	local db = fiona.get_db(":memory:", "rw")

	-- Peek at the underlying connection to confirm the schema landed.
	local seen = {}

	for row in db._conn:nrows("select name from sqlite_master where type = 'table' order by name") do
		seen[row.name] = true
	end

	h.assert_true(seen.collections, "collections table should exist")
	h.assert_true(seen.relationships, "relationships table should exist")
	h.assert_true(seen.meta, "meta table should exist")
end)

h.test("get_db creates a file-backed database at a new path", function()
	local path = os.tmpname()
	os.remove(path)

	local db = fiona.get_db(path, "rw")
	h.assert_true(db, "db should be created at fresh file path")

	local f = io.open(path, "r")
	h.assert_true(f, "file should exist on disk after get_db")

	if f then
		f:close()
	end

	db._conn:close()
	os.remove(path)
end)

h.test("get_db opens an existing file-backed database in 'r' mode", function()
	local path = os.tmpname()
	os.remove(path)

	-- Populate it first with a writable open.
	local w = fiona.get_db(path, "rw")
	w._conn:close()

	-- Reopen read-only; schema is already there, so no write is needed.
	local r = fiona.get_db(path, "r")
	h.assert_true(r, "r-mode open of a populated db should succeed")

	r._conn:close()
	os.remove(path)
end)

h.test("get_db raises when 'r' opens a file with no schema", function()
	local path = os.tmpname()
	os.remove(path)

	-- Create an empty SQLite file by opening + closing a bare connection.
	local sqlite3 = require("lsqlite3")
	local raw = sqlite3.open(path)
	raw:close()

	h.assert_raises(function()
		fiona.get_db(path, "r")
	end, "no Fiona schema", "r + empty file")

	os.remove(path)
end)
