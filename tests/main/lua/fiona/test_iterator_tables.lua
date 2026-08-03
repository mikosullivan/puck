-- Tests for the iterator temp tables (iterators, iterator_elements)
-- created per-connection by get_db. Verifies the tables exist, the
-- FK cascade cleans up elements when an iterator row is deleted, ids
-- don't reuse across deletions (autoincrement), duplicate positions
-- within an iterator are rejected, and the tables don't leak across
-- connections.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

local sqlite3 = require("lsqlite3")

local function exec(db, sql)
	local ok = db._conn:exec(sql)

	if ok ~= sqlite3.OK then
		error(db._conn:errmsg())
	end
end

-- ------------------------------------------------------------
-- Table existence
-- ------------------------------------------------------------

h.test("iterators table exists after get_db", function()
	local db = fiona.get_db(":memory:", "rw")
	local count

	for row in db._conn:nrows(
		"select count(*) as c from temp.sqlite_master where type = 'table' and name = 'iterators'"
	) do
		count = row.c
	end

	h.assert_eq(count, 1, "iterators temp table present")
end)

h.test("iterator_elements table exists after get_db", function()
	local db = fiona.get_db(":memory:", "rw")
	local count

	for row in db._conn:nrows(
		"select count(*) as c from temp.sqlite_master where type = 'table' and name = 'iterator_elements'"
	) do
		count = row.c
	end

	h.assert_eq(count, 1, "iterator_elements temp table present")
end)

-- ------------------------------------------------------------
-- iterators: autoincrement + basic insert
-- ------------------------------------------------------------

h.test("insert into iterators returns unique monotonic ids", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local id1 = db._conn:last_insert_rowid()
	exec(db, "insert into iterators (kind) values ('values')")
	local id2 = db._conn:last_insert_rowid()

	h.assert_true(id1 > 0, "first id is positive")
	h.assert_true(id2 > id1, "second id is greater than first")
end)

h.test("iterator ids don't reuse after deletion (autoincrement)", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local id1 = db._conn:last_insert_rowid()
	exec(db, "delete from iterators where iterator_pk = " .. id1)
	exec(db, "insert into iterators (kind) values ('keys')")
	local id2 = db._conn:last_insert_rowid()

	h.assert_true(id2 > id1, "reused id would be a bug — autoincrement guarantees monotonic")
end)

h.test("iterators.created_at defaults to current_timestamp", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")

	local ts
	for row in db._conn:nrows("select created_at from iterators") do
		ts = row.created_at
	end

	h.assert_true(ts ~= nil and ts ~= "", "created_at populated")
end)

-- ------------------------------------------------------------
-- iterator_elements: FK + cascade + PK
-- ------------------------------------------------------------

h.test("insert into iterator_elements with valid iterator_pk works", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local iter_id = db._conn:last_insert_rowid()

	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'foo')",
		iter_id))

	local count
	for row in db._conn:nrows("select count(*) as c from iterator_elements") do
		count = row.c
	end

	h.assert_eq(count, 1, "element inserted")
end)

h.test("insert with unknown iterator_pk fails the FK check", function()
	local db = fiona.get_db(":memory:", "rw")

	h.assert_raises(function()
		exec(db, "insert into iterator_elements (iterator_pk, position, key) values (999, 0, 'x')")
	end, "FOREIGN KEY", "FK enforced")
end)

h.test("deleting an iterators row cascades to its iterator_elements", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local iter_id = db._conn:last_insert_rowid()

	for i = 0, 4 do
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position, key) values (%d, %d, 'k%d')",
			iter_id, i, i))
	end

	local before
	for row in db._conn:nrows("select count(*) as c from iterator_elements where iterator_pk = " .. iter_id) do
		before = row.c
	end
	h.assert_eq(before, 5, "5 elements before delete")

	exec(db, "delete from iterators where iterator_pk = " .. iter_id)

	local after
	for row in db._conn:nrows("select count(*) as c from iterator_elements where iterator_pk = " .. iter_id) do
		after = row.c
	end
	h.assert_eq(after, 0, "cascade cleared all elements")
end)

h.test("duplicate (iterator_pk, position) is rejected by the primary key", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local iter_id = db._conn:last_insert_rowid()
	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'a')",
		iter_id))

	h.assert_raises(function()
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'b')",
			iter_id))
	end, "UNIQUE", "duplicate position rejected")
end)

h.test("negative position is rejected by CHECK", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local iter_id = db._conn:last_insert_rowid()

	h.assert_raises(function()
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position, key) values (%d, -1, 'a')",
			iter_id))
	end, "CHECK", "negative position rejected")
end)

-- ------------------------------------------------------------
-- Multiple iterators coexist without stepping on each other
-- ------------------------------------------------------------

h.test("multiple iterators can hold same positions independently", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local a = db._conn:last_insert_rowid()
	exec(db, "insert into iterators (kind) values ('keys')")
	local b = db._conn:last_insert_rowid()

	-- Both iterators have position 0, but distinct iterator_pks.
	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'from_a')", a))
	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'from_b')", b))

	local keys = {}
	for row in db._conn:nrows("select iterator_pk, key from iterator_elements order by iterator_pk") do
		keys[row.iterator_pk] = row.key
	end

	h.assert_eq(keys[a], "from_a", "iterator a's element intact")
	h.assert_eq(keys[b], "from_b", "iterator b's element intact")
end)

h.test("deleting one iterator's row leaves other iterators' rows alone", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local keep = db._conn:last_insert_rowid()
	exec(db, "insert into iterators (kind) values ('keys')")
	local drop = db._conn:last_insert_rowid()

	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'keep')", keep))
	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'drop')", drop))

	exec(db, "delete from iterators where iterator_pk = " .. drop)

	local count
	for row in db._conn:nrows("select count(*) as c from iterator_elements") do
		count = row.c
	end
	h.assert_eq(count, 1, "only surviving iterator's element remains")

	local remaining_key
	for row in db._conn:nrows("select key from iterator_elements") do
		remaining_key = row.key
	end
	h.assert_eq(remaining_key, "keep", "correct row survived")
end)

-- ------------------------------------------------------------
-- Payload columns: key vs rel_pk are both null-allowed
-- (populated distinctly by keys vs values iterators)
-- ------------------------------------------------------------

h.test("iterator_elements accepts key-only rows (hash-keys iterator shape)", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('keys')")
	local iter_id = db._conn:last_insert_rowid()

	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, key) values (%d, 0, 'name')", iter_id))

	for row in db._conn:nrows("select key, rel_pk from iterator_elements where iterator_pk = " .. iter_id) do
		h.assert_eq(row.key, "name", "key populated")
		h.assert_true(row.rel_pk == nil, "rel_pk null")
	end
end)

h.test("iterator_elements accepts rel_pk-only rows (value / array iterator shape)", function()
	local db = fiona.get_db(":memory:", "rw")

	-- Set up a real relationship to reference.
	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	local rel_pk
	for row in db._conn:nrows("select rel_pk from relationships where parent = 1 and key = 'k'") do
		rel_pk = row.rel_pk
	end

	exec(db, "insert into iterators (kind) values ('values')")
	local iter_id = db._conn:last_insert_rowid()

	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, rel_pk) values (%d, 0, %d)",
		iter_id, rel_pk))

	for row in db._conn:nrows("select key, rel_pk from iterator_elements where iterator_pk = " .. iter_id) do
		h.assert_eq(row.rel_pk, rel_pk, "rel_pk populated")
		h.assert_true(row.key == nil, "key null")
	end
end)

h.test("iterator_elements rejects row with both key and rel_pk (exclusive union)", function()
	local db = fiona.get_db(":memory:", "rw")

	-- Use a real rel_pk so the FK trigger passes; the CHECK is what
	-- should fire.
	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	local rel_pk
	for row in db._conn:nrows("select rel_pk from relationships where parent = 1 and key = 'k'") do
		rel_pk = row.rel_pk
	end

	exec(db, "insert into iterators (kind) values ('mixed')")
	local iter_id = db._conn:last_insert_rowid()

	h.assert_raises(function()
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position, key, rel_pk) values (%d, 0, 'foo', %d)",
			iter_id, rel_pk))
	end, "CHECK", "both key and rel_pk rejected")
end)

h.test("iterator_elements rejects rel_pk that doesn't reference a real relationships row", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('values')")
	local iter_id = db._conn:last_insert_rowid()

	h.assert_raises(function()
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position, rel_pk) values (%d, 0, 99999)",
			iter_id))
	end, "must reference", "unknown rel_pk rejected")
end)

h.test("iterator_elements accepts rel_pk pointing at a real relationships row", function()
	local db = fiona.get_db(":memory:", "rw")

	-- Set up a real relationship so we have a valid rel_pk to reference.
	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	local rel_pk
	for row in db._conn:nrows("select rel_pk from relationships where parent = 1 and key = 'k'") do
		rel_pk = row.rel_pk
	end

	exec(db, "insert into iterators (kind) values ('values')")
	local iter_id = db._conn:last_insert_rowid()

	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, rel_pk) values (%d, 0, %d)",
		iter_id, rel_pk))

	local count
	for row in db._conn:nrows("select count(*) as c from iterator_elements where iterator_pk = " .. iter_id) do
		count = row.c
	end
	h.assert_eq(count, 1, "valid rel_pk accepted")
end)

h.test("deleting a relationships row leaves the iterator_element's rel_pk dangling (no cascade)", function()
	-- The referenced row disappears; the iterator element stays with
	-- its now-stale rel_pk. Walk-time lookup returns null (tested at
	-- the iterator API layer once that lands).
	local db = fiona.get_db(":memory:", "rw")

	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)
	local rel_pk
	for row in db._conn:nrows("select rel_pk from relationships where parent = 1 and key = 'k'") do
		rel_pk = row.rel_pk
	end

	exec(db, "insert into iterators (kind) values ('values')")
	local iter_id = db._conn:last_insert_rowid()
	exec(db, string.format(
		"insert into iterator_elements (iterator_pk, position, rel_pk) values (%d, 0, %d)",
		iter_id, rel_pk))

	-- Drop the underlying relationship (via the API, which also GCs the child).
	db:delete_hash_element(1, "k")

	-- The iterator_element still exists with its now-stale rel_pk.
	local stored_rel_pk
	for row in db._conn:nrows("select rel_pk from iterator_elements where iterator_pk = " .. iter_id) do
		stored_rel_pk = row.rel_pk
	end
	h.assert_eq(stored_rel_pk, rel_pk, "iterator_element retains dangling rel_pk")

	-- Confirm the referenced relationships row is actually gone.
	local exists
	for row in db._conn:nrows("select count(*) as c from relationships where rel_pk = " .. rel_pk) do
		exists = row.c
	end
	h.assert_eq(exists, 0, "underlying relationships row is gone")
end)

h.test("iterator_elements rejects row with neither key nor rel_pk (payload-less)", function()
	local db = fiona.get_db(":memory:", "rw")
	exec(db, "insert into iterators (kind) values ('empty')")
	local iter_id = db._conn:last_insert_rowid()

	h.assert_raises(function()
		exec(db, string.format(
			"insert into iterator_elements (iterator_pk, position) values (%d, 0)",
			iter_id))
	end, "CHECK", "both null rejected")
end)

-- ------------------------------------------------------------
-- Cross-connection isolation (temp tables are per-connection)
-- ------------------------------------------------------------

h.test("iterators from one connection don't leak into another", function()
	local path = "/tmp/fiona-iter-test.db"
	os.remove(path)
	os.remove(path .. "-journal")

	local db1 = fiona.get_db(path, "rw")
	exec(db1, "insert into iterators (kind) values ('keys')")
	exec(db1, "insert into iterators (kind) values ('values')")

	local db2 = fiona.get_db(path, "rw")

	-- db2 opened the same file, but its temp schema is separate.
	local count
	for row in db2._conn:nrows("select count(*) as c from iterators") do
		count = row.c
	end
	h.assert_eq(count, 0, "second connection has empty temp iterators")

	os.remove(path)
	os.remove(path .. "-journal")
end)
