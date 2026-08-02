-- Tests for the collections table. Collections hold hashes and arrays
-- only; scalars live inline in the relationships table (see
-- test_relationships.lua).

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

local sqlite3 = require("lsqlite3")

local function exec(db, sql)
	local ok = db:exec(sql)

	if ok ~= sqlite3.OK then
		error(db:errmsg())
	end
end

-- ------------------------------------------------------------
-- Positive tests
-- ------------------------------------------------------------

h.test("root row exists", function()
	local db = h.fresh_db()

	for row in db:nrows("select collection_pk, type from collections where collection_pk = 1") do
		h.assert_eq(row.collection_pk, 1, "root collection_pk")
		h.assert_eq(row.type, "h", "root type")
		return
	end

	error("root row not found")
end)

h.test("root has no trace flags at rest", function()
	local db = h.fresh_db()

	for row in db:nrows("select needs_trace, in_trace from collections where collection_pk = 1") do
		h.assert_true(row.needs_trace == nil, "root needs_trace null")
		h.assert_true(row.in_trace == nil, "root in_trace null")
		return
	end
end)

h.test("insert hash", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
end)

h.test("insert array", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('a')")
end)

h.test("delete non-root row", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	local new_pk = db:last_insert_rowid()
	exec(db, "delete from collections where collection_pk = " .. new_pk)

	for row in db:nrows("select count(*) as c from collections where collection_pk = " .. new_pk) do
		h.assert_eq(row.c, 0, "row deleted")
		return
	end
end)

-- ------------------------------------------------------------
-- Negative tests — type column
-- ------------------------------------------------------------

h.test("reject type null", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into collections (type) values (null)") end,
		"NOT NULL", "type null")
end)

h.test("reject scalar type 's' — scalars are not collections", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into collections (type) values ('s')") end,
		"CHECK", "type s rejected")
end)

h.test("reject type unknown value 'x'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into collections (type) values ('x')") end,
		"CHECK", "type x")
end)

h.test("reject type uppercase 'H'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into collections (type) values ('H')") end,
		"CHECK", "type H")
end)

h.test("reject type empty string", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into collections (type) values ('')") end,
		"CHECK", "type empty")
end)

-- ------------------------------------------------------------
-- Negative tests — needs_trace / in_trace column shape
-- ------------------------------------------------------------

h.test("reject needs_trace = 0", function()
	local db = h.fresh_db()
	h.assert_raises(function()
		exec(db, "insert into collections (type, needs_trace) values ('h', 0)")
	end, "CHECK", "needs_trace = 0 rejected")
end)

h.test("reject needs_trace = 2", function()
	local db = h.fresh_db()
	h.assert_raises(function()
		exec(db, "insert into collections (type, needs_trace) values ('h', 2)")
	end, "CHECK", "needs_trace = 2 rejected")
end)

h.test("reject in_trace = 0", function()
	local db = h.fresh_db()
	h.assert_raises(function()
		exec(db, "insert into collections (type, in_trace) values ('h', 0)")
	end, "CHECK", "in_trace = 0 rejected")
end)

-- ------------------------------------------------------------
-- Negative tests — immutability trigger
-- ------------------------------------------------------------

h.test("reject update of type on non-root", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	h.assert_raises(function()
		exec(db, "update collections set type = 'a' where collection_pk = 2")
	end, "immutable", "update type")
end)

h.test("reject update of collection_pk on non-root", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	h.assert_raises(function()
		exec(db, "update collections set collection_pk = 42 where collection_pk = 2")
	end, "immutable", "update collection_pk")
end)

h.test("allow update of needs_trace on non-root (mark cycle)", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	exec(db, "update collections set needs_trace = 1 where collection_pk = 2")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_eq(row.needs_trace, 1, "flag set")
	end

	exec(db, "update collections set needs_trace = null where collection_pk = 2")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_true(row.needs_trace == nil, "flag cleared")
	end
end)

h.test("allow update of in_trace on non-root (drain cycle)", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	exec(db, "update collections set in_trace = 1 where collection_pk = 2")

	for row in db:nrows("select in_trace from collections where collection_pk = 2") do
		h.assert_eq(row.in_trace, 1, "flag set")
	end
end)

-- ------------------------------------------------------------
-- Negative tests — root protection
-- ------------------------------------------------------------

h.test("reject delete of the root row", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "delete from collections where collection_pk = 1") end,
		"root", "delete root")
end)

h.test("reject blanket delete (includes root)", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")
	h.assert_raises(function() exec(db, "delete from collections") end,
		"root", "delete all")
end)

h.test("reject setting needs_trace on root", function()
	local db = h.fresh_db()
	h.assert_raises(function()
		exec(db, "update collections set needs_trace = 1 where collection_pk = 1")
	end, "root", "root needs_trace")
end)

h.test("allow setting in_trace on root (drain propagation lands here)", function()
	local db = h.fresh_db()
	exec(db, "update collections set in_trace = 1 where collection_pk = 1")

	for row in db:nrows("select in_trace from collections where collection_pk = 1") do
		h.assert_eq(row.in_trace, 1, "root can carry in_trace")
	end

	exec(db, "update collections set in_trace = null where collection_pk = 1")

	for row in db:nrows("select in_trace from collections where collection_pk = 1") do
		h.assert_true(row.in_trace == nil, "root in_trace cleared")
	end
end)

h.test("reject update of type on root", function()
	local db = h.fresh_db()
	h.assert_raises(function()
		exec(db, "update collections set type = 'a' where collection_pk = 1")
	end, "immutable", "root type update")
end)
