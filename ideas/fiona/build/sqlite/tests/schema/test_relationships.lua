-- Tests for the relationships table. Every row is EITHER a collection
-- edge (child set, st null, scalar null) OR a scalar-carrying row
-- (child null, st set, scalar has the value per st's shape). The
-- exclusive-union CHECK guards that invariant; per-st CHECKs guard
-- each scalar shape.

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

-- Set up a database with a few standard collections rows for reuse:
--   pk=1: root hash (built-in)
--   pk=2: another hash
--   pk=3: an array
local function db_with_fixtures()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into collections (type) values ('a')")  -- 3
	return db
end

-- ------------------------------------------------------------
-- Positive tests — collection-edge rows
-- ------------------------------------------------------------

h.test("insert collection-edge: hash parent + key + idx + collection child", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'a_ref', 0)")
end)

h.test("insert collection-edge: array parent + idx + collection child", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 2, 0)")
end)

h.test("insert collection-edge: root hash as parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h_ref', 0)")
end)

h.test("multiple parents can point at the same child (graph, not tree)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a_ref', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 2, 'b_ref', 0)")
end)

-- ------------------------------------------------------------
-- Positive tests — scalar-carrying rows (child null, st + scalar set)
-- ------------------------------------------------------------

h.test("insert scalar row: string under hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'name', 0, 's', 'hello')")
end)

h.test("insert scalar row: number under hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'age', 0, 'n', 42)")
end)

h.test("insert scalar row: real number under hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'pi', 0, 'n', 3.14)")
end)

h.test("insert scalar row: boolean true (stored as 1)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'flag', 0, 'b', 1)")
end)

h.test("insert scalar row: boolean false (stored as 0)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'flag', 0, 'b', 0)")
end)

h.test("insert scalar row: null flavor 'u' with null scalar", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'u', null)")
end)

h.test("insert scalar row: string under array", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, idx, st, scalar) values (3, 0, 's', 'first')")
end)

-- ------------------------------------------------------------
-- Positive tests — mixed shapes coexisting under the same parent
-- ------------------------------------------------------------

h.test("hash parent can hold both collection-edge and scalar rows", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'ref', 0)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'name', 1, 's', 'hello')")

	for row in db:nrows("select count(*) as c from relationships where parent = 2") do
		h.assert_eq(row.c, 2, "both rows landed")
		return
	end
end)

h.test("delete a scalar-carrying relationship works", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 's', 'hi')")
	exec(db, "delete from relationships where parent = 2 and key = 'x'")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship deleted")
		return
	end
end)

-- ------------------------------------------------------------
-- Positive tests — content mutability
-- ------------------------------------------------------------

h.test("update idx is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 2, 0)")
	exec(db, "update relationships set idx = 5 where parent = 3 and idx = 0")

	for row in db:nrows("select idx from relationships where parent = 3") do
		h.assert_eq(row.idx, 5, "idx updated")
		return
	end
end)

h.test("update child is allowed (content-mutable ref)", function()
	local db = db_with_fixtures()
	exec(db, "insert into collections (type) values ('h')")  -- 4
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")
	exec(db, "update relationships set child = 4 where key = 'x'")

	for row in db:nrows("select child from relationships where key = 'x'") do
		h.assert_eq(row.child, 4, "child swung in place")
	end
end)

h.test("update scalar value is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'v', 0, 'n', 1)")
	exec(db, "update relationships set scalar = 99 where key = 'v'")

	for row in db:nrows("select scalar from relationships where key = 'v'") do
		h.assert_eq(row.scalar, 99, "scalar swapped in place")
	end
end)

h.test("update st + scalar together is allowed (change scalar type)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'v', 0, 'n', 1)")
	exec(db, "update relationships set st = 's', scalar = 'now text' where key = 'v'")

	for row in db:nrows("select st, scalar from relationships where key = 'v'") do
		h.assert_eq(row.st, "s", "st changed")
		h.assert_eq(row.scalar, "now text", "scalar changed")
	end
end)

h.test("swing a row from collection-edge to scalar shape (child cleared, st set)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")
	exec(db, "update relationships set child = null, st = 's', scalar = 'now scalar' where key = 'x'")

	for row in db:nrows("select child, st, scalar from relationships where key = 'x'") do
		h.assert_true(row.child == nil, "child cleared")
		h.assert_eq(row.st, "s", "st set")
		h.assert_eq(row.scalar, "now scalar", "scalar set")
	end
end)

h.test("swing a row from scalar shape to collection-edge (st cleared, child set)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 's', 'hi')")
	exec(db, "update relationships set child = 3, st = null, scalar = null where key = 'x'")

	for row in db:nrows("select child, st, scalar from relationships where key = 'x'") do
		h.assert_eq(row.child, 3, "child set")
		h.assert_true(row.st == nil, "st cleared")
		h.assert_true(row.scalar == nil, "scalar cleared")
	end
end)

-- ------------------------------------------------------------
-- Negative tests — exclusive-union CHECK
-- ------------------------------------------------------------

h.test("reject row with both child AND st set (violates exclusive union)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx, st, scalar) values (2, 3, 'x', 0, 's', 'hi')")
	end, "CHECK", "child+st both set rejected")
end)

h.test("reject row with both child null AND st null (neither shape)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx) values (2, 'x', 0)")
	end, "CHECK", "neither child nor st set rejected")
end)

-- ------------------------------------------------------------
-- Negative tests — per-st scalar shape
-- ------------------------------------------------------------

h.test("reject st = 'b' with scalar = 2 (boolean must be 0 or 1)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'b', 2)")
	end, "CHECK", "boolean value 2 rejected")
end)

h.test("reject st = 'b' with scalar = null (boolean must be 0 or 1)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'b', null)")
	end, "CHECK", "boolean null rejected")
end)

h.test("reject st = 'u' with non-null scalar", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'u', 'oops')")
	end, "CHECK", "null-flavor with a value rejected")
end)

h.test("reject st = 'n' with a text scalar", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'n', 'not a number')")
	end, "CHECK", "number st with text scalar rejected")
end)

h.test("reject st = 's' with a numeric scalar", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 's', 42)")
	end, "CHECK", "string st with numeric scalar rejected")
end)

h.test("reject invalid st value", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 0, 'z', 'hi')")
	end, "CHECK", "unknown st rejected")
end)

-- ------------------------------------------------------------
-- Negative tests — foreign keys
-- ------------------------------------------------------------

h.test("reject parent referencing non-existent collection row", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (999, 2, 'x', 0)")
	end, "FOREIGN KEY", "parent FK")
end)

h.test("reject child referencing non-existent collection row", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (2, 999, 'x', 0)")
	end, "FOREIGN KEY", "child FK")
end)

h.test("delete of parent collection row cascades to its relationships", function()
	-- FKs use `on delete cascade` on both parent and child, so the drain
	-- can remove collection rows and have their edges drop with them.
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")
	exec(db, "delete from collections where collection_pk = 2")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship cascade-deleted with parent")
		return
	end
end)

h.test("delete of child collection row cascades to its relationships", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")
	exec(db, "delete from collections where collection_pk = 3")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship cascade-deleted with child")
		return
	end
end)

-- ------------------------------------------------------------
-- Negative tests — key vs parent type
-- ------------------------------------------------------------

h.test("reject hash parent with no key (idx alone is not enough)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (2, 3, 0)")
	end, "must set key", "hash needs key")
end)

h.test("reject array parent with key set", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (3, 2, 'x', 0)")
	end, "must not set key", "array can't have key")
end)

-- ------------------------------------------------------------
-- Negative tests — idx is required for every relationship
-- ------------------------------------------------------------

h.test("reject hash parent with no idx", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key) values (2, 3, 'x')")
	end, "NOT NULL", "hash needs idx too")
end)

h.test("reject array parent with no idx", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child) values (3, 2)")
	end, "NOT NULL", "array needs idx")
end)

-- ------------------------------------------------------------
-- Negative tests — idx type / range
-- ------------------------------------------------------------

h.test("reject idx that is a text value", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 2, 'foo')")
	end, "CHECK", "idx as text")
end)

h.test("reject idx that is a numeric-looking text", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 2, '42')")
	end, "CHECK", "idx as numeric text")
end)

h.test("reject idx that is a real (float)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 2, 3.14)")
	end, "CHECK", "idx as real")
end)

h.test("reject idx that is negative", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 2, -1)")
	end, "CHECK", "idx as negative")
end)

h.test("accept idx = 0", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 2, 0)")
end)

h.test("accept idx as very large integer (well below OFFSET)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 2, 999999999999)")
end)

-- ------------------------------------------------------------
-- Negative tests — uniqueness
-- ------------------------------------------------------------

h.test("reject duplicate (parent, key) for a hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")

	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 1, 's', 'dupe')")
	end, "UNIQUE", "duplicate key under hash")
end)

h.test("same key under different hash parents is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into collections (type) values ('h')")  -- 4
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'name', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (4, 3, 'name', 0)")
end)

h.test("same idx under different array parents is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into collections (type) values ('a')")  -- 4
	exec(db, "insert into relationships (parent, child, idx) values (3, 2, 0)")
	exec(db, "insert into relationships (parent, child, idx) values (4, 2, 0)")
end)

-- ------------------------------------------------------------
-- Negative tests — immutability (rel_pk, parent, key)
-- ------------------------------------------------------------

h.test("reject update of parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into collections (type) values ('h')")  -- 4
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")

	h.assert_raises(function()
		exec(db, "update relationships set parent = 4 where key = 'x'")
	end, "immutable", "update parent")
end)

h.test("reject update of key", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")

	h.assert_raises(function()
		exec(db, "update relationships set key = 'y' where key = 'x'")
	end, "immutable", "update key")
end)

h.test("reject update of rel_pk", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'x', 0)")

	h.assert_raises(function()
		exec(db, "update relationships set rel_pk = 999 where key = 'x'")
	end, "immutable", "update rel_pk")
end)

-- ------------------------------------------------------------
-- Mark trigger — needs_trace tagging on relationship delete
-- ------------------------------------------------------------
--
-- The mark trigger fires when a collection-edge relationship is deleted
-- (or when child is swung via UPDATE OF child), and only marks children
-- that are (a) non-null and (b) not root. Scalar-carrying rows have
-- child null and don't trigger a mark on delete. The actual GC —
-- walking upward from marked seeds and deleting unreachable subgraphs
-- — is Lua-side and lives in tests/lua/test_purge.lua.

h.test("mark on delete: orphaned collection child gets needs_trace = 1", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'child', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'child'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_eq(row.needs_trace, 1, "child marked needs_trace")
	end
end)

h.test("mark on delete: scalar-carrying row delete does NOT mark anything", function()
	-- No collection to mark — the trigger's `when old.child is not null`
	-- guard short-circuits.
	local db = h.fresh_db()
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (1, 'x', 0, 's', 'leaf')")
	exec(db, "delete from relationships where parent = 1 and key = 'x'")

	for row in db:nrows("select count(*) as c from collections where needs_trace = 1") do
		h.assert_eq(row.c, 0, "no collection marked")
	end
end)

h.test("mark on delete: root as child is never marked (defense-in-depth guard)", function()
	-- Root can be a legitimate child (e.g., root → root self-loop). Deleting
	-- that edge leaves root's needs_trace null because of the `old.child <> 1`
	-- guard, avoiding a drain that would spin on root.
	local db = h.fresh_db()
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 1, 'self', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'self'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 1") do
		h.assert_true(row.needs_trace == nil, "root's needs_trace stays null")
	end
end)

h.test("mark on update of child: swinging away marks the old child", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into collections (type) values ('h')")  -- 3
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "update relationships set child = 3 where parent = 1 and key = 'x'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_eq(row.needs_trace, 1, "old child (h2) marked needs_trace")
	end

	for row in db:nrows("select needs_trace from collections where collection_pk = 3") do
		h.assert_true(row.needs_trace == nil, "new child (h3) not marked")
	end
end)

h.test("mark on update of child: swing from ref shape to scalar shape marks the old ref", function()
	-- Update sets child = null while filling in st + scalar. `is not`
	-- comparison correctly identifies the null-vs-non-null transition;
	-- the old child (still non-root, non-null) gets marked.
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "update relationships set child = null, st = 's', scalar = 'now scalar' where key = 'x'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_eq(row.needs_trace, 1, "old ref marked when row goes scalar")
	end
end)

h.test("mark on update of child: swing from scalar to ref shape does NOT mark", function()
	-- Old row had child = null, so the trigger's `old.child is not null`
	-- guard short-circuits — nothing to mark.
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (1, 'x', 0, 's', 'hi')")
	exec(db, "update relationships set child = 2, st = null, scalar = null where key = 'x'")

	for row in db:nrows("select count(*) as c from collections where needs_trace = 1") do
		h.assert_eq(row.c, 0, "no collection marked on scalar→ref swing")
	end
end)

h.test("mark on update of child: swinging to root is not the marked child (old was non-root)", function()
	-- Old child = h2 (non-root); new child = 1 (root). Old h2 gets marked
	-- (it's what left the row); root is the new destination, not the old.
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "update relationships set child = 1 where key = 'x'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_eq(row.needs_trace, 1, "old child h2 marked")
	end

	for row in db:nrows("select needs_trace from collections where collection_pk = 1") do
		h.assert_true(row.needs_trace == nil, "root is not marked")
	end
end)

h.test("mark on update of child: same target is a schema-level no-op", function()
	-- `old.child is not new.child` returns false when both sides are the
	-- same value; trigger doesn't fire.
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "update relationships set child = 2 where key = 'x'")

	for row in db:nrows("select needs_trace from collections where collection_pk = 2") do
		h.assert_true(row.needs_trace == nil, "no mark on identity update")
	end
end)

-- ------------------------------------------------------------
-- Shift triggers — new record inserted at an occupied idx
-- ------------------------------------------------------------

-- Small helper: build an array under root with N scalar-carrying entries
-- packed at idx 0..N-1 with values (i+1)*10. Returns the db.
local function fresh_array(n)
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('a')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")

	for i = 0, n - 1 do
		exec(db, string.format(
			"insert into relationships (parent, idx, st, scalar) values (2, %d, 'n', %d)",
			i, (i + 1) * 10))
	end

	return db
end

-- Read the array under parent 2 as an ordered list of scalar values.
local function read_array(db)
	local out = {}

	for row in db:nrows("select idx, scalar from relationships where parent = 2 order by idx") do
		out[#out + 1] = row.scalar
	end

	return out
end

h.test("shift on insert: collision at existing idx bumps sibling up", function()
	local db = fresh_array(2)  -- [10, 20] at idx 0, 1
	exec(db, "insert into relationships (parent, idx, st, scalar) values (2, 0, 'n', 999)")

	local values = read_array(db)
	h.assert_eq(values[1], 999, "new value at idx 0")
	h.assert_eq(values[2], 10,  "old idx 0 shifted to 1")
	h.assert_eq(values[3], 20,  "old idx 1 shifted to 2")
end)

h.test("shift on insert: cascade — insert at 0 in a 5-item array", function()
	local db = fresh_array(5)  -- [10, 20, 30, 40, 50] at idx 0..4
	exec(db, "insert into relationships (parent, idx, st, scalar) values (2, 0, 'n', 999)")

	local values = read_array(db)
	h.assert_eq(values[1], 999)
	h.assert_eq(values[2], 10)
	h.assert_eq(values[3], 20)
	h.assert_eq(values[4], 30)
	h.assert_eq(values[5], 40)
	h.assert_eq(values[6], 50)
end)

h.test("shift on insert: insert in the middle shifts only rows at or above", function()
	local db = fresh_array(5)  -- [10, 20, 30, 40, 50]
	exec(db, "insert into relationships (parent, idx, st, scalar) values (2, 2, 'n', 999)")

	local values = read_array(db)
	-- Expected: [10, 20, 999, 30, 40, 50]
	h.assert_eq(values[1], 10)
	h.assert_eq(values[2], 20)
	h.assert_eq(values[3], 999)
	h.assert_eq(values[4], 30)
	h.assert_eq(values[5], 40)
	h.assert_eq(values[6], 50)
end)

h.test("shift on insert: sparse insert (no collision) is a no-op", function()
	local db = fresh_array(3)  -- [10, 20, 30] at idx 0..2
	exec(db, "insert into relationships (parent, idx, st, scalar) values (2, 100, 'n', 999)")

	local at_100
	for row in db:nrows("select scalar from relationships where parent = 2 and idx = 100") do
		at_100 = row.scalar
	end
	h.assert_eq(at_100, 999, "sparse insert lands at 100 with no shift")

	for row in db:nrows("select count(*) as c from relationships where parent = 2 and idx in (0,1,2)") do
		h.assert_eq(row.c, 3, "originals still at 0..2")
	end
end)

h.test("shift on insert: hash collision at (parent, idx) shifts, key uniqueness still enforced", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'a', 0, 'n', 10)")
	-- New entry with different key + same idx: shift lets it in.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'b', 0, 'n', 20)")

	local at_0, at_1
	for row in db:nrows("select idx, key from relationships where parent = 2 order by idx") do
		if row.idx == 0 then at_0 = row.key
		elseif row.idx == 1 then at_1 = row.key end
	end
	h.assert_eq(at_0, "b", "new key 'b' at idx 0")
	h.assert_eq(at_1, "a", "key 'a' shifted to idx 1")

	-- Same key as existing entry still raises regardless of idx.
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'a', 5, 'n', 30)")
	end, "UNIQUE", "duplicate key under hash still rejected")
end)

-- ------------------------------------------------------------
-- Shift triggers — moving an existing record via UPDATE OF idx
-- ------------------------------------------------------------

h.test("shift on move: up-move shifts intervening siblings up by 1", function()
	local db = fresh_array(5)  -- [10, 20, 30, 40, 50] at idx 0..4
	-- Move value 40 (currently at idx 3) to idx 1.
	exec(db, "update relationships set idx = 1 where parent = 2 and scalar = 40")

	local values = read_array(db)
	-- Expected: [10, 40, 20, 30, 50]
	h.assert_eq(values[1], 10)
	h.assert_eq(values[2], 40)
	h.assert_eq(values[3], 20)
	h.assert_eq(values[4], 30)
	h.assert_eq(values[5], 50)
end)

h.test("shift on move: down-move shifts intervening siblings down by 1", function()
	local db = fresh_array(5)  -- [10, 20, 30, 40, 50] at idx 0..4
	-- Move value 20 (currently at idx 1) to idx 3.
	exec(db, "update relationships set idx = 3 where parent = 2 and scalar = 20")

	local values = read_array(db)
	-- Expected: [10, 30, 40, 20, 50]
	h.assert_eq(values[1], 10)
	h.assert_eq(values[2], 30)
	h.assert_eq(values[3], 40)
	h.assert_eq(values[4], 20)
	h.assert_eq(values[5], 50)
end)

h.test("shift on move: no collision means no shift", function()
	local db = fresh_array(3)  -- [10, 20, 30] at idx 0..2
	-- Move value 10 (idx 0) to idx 100 (fresh position).
	exec(db, "update relationships set idx = 100 where parent = 2 and scalar = 10")

	local at_100
	for row in db:nrows("select scalar from relationships where parent = 2 and idx = 100") do
		at_100 = row.scalar
	end
	h.assert_eq(at_100, 10, "10 landed at 100")

	local at_1, at_2
	for row in db:nrows("select idx, scalar from relationships where parent = 2 order by idx") do
		if row.idx == 1 then at_1 = row.scalar
		elseif row.idx == 2 then at_2 = row.scalar end
	end
	h.assert_eq(at_1, 20, "20 unchanged at 1")
	h.assert_eq(at_2, 30, "30 unchanged at 2")
end)

h.test("shift on move: density preserved for both directions", function()
	local db = fresh_array(6)  -- [10, 20, 30, 40, 50, 60]

	-- Up-move: 60 (idx 5) to idx 0.
	exec(db, "update relationships set idx = 0 where parent = 2 and scalar = 60")

	local max_idx_up
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx_up = row.m
	end
	h.assert_eq(max_idx_up, 5, "max idx still 5 — dense after up-move")

	-- Down-move: 10 (currently at idx 1) to idx 5.
	exec(db, "update relationships set idx = 5 where parent = 2 and scalar = 10")

	local max_idx_down
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx_down = row.m
	end
	h.assert_eq(max_idx_down, 5, "max idx still 5 — dense after down-move")
end)

h.test("shift on move: identity update (NEW.idx = OLD.idx) is a no-op", function()
	local db = fresh_array(3)
	exec(db, "update relationships set idx = 1 where parent = 2 and idx = 1")

	local values = read_array(db)
	h.assert_eq(values[1], 10)
	h.assert_eq(values[2], 20)
	h.assert_eq(values[3], 30)
end)

-- ------------------------------------------------------------
-- Hash gap semantics — raw DELETE on a hash leaves a gap
-- ------------------------------------------------------------

h.test("hash delete leaves a gap (no shift for hashes)", function()
	-- Users don't observe hash idx directly. Confirms shift-down on
	-- delete is not a schema trigger.
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'a', 0, 'n', 10)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'b', 1, 'n', 20)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'c', 2, 'n', 30)")

	exec(db, "delete from relationships where parent = 2 and key = 'b'")

	local by_idx = {}
	for row in db:nrows("select idx, key from relationships where parent = 2") do
		by_idx[row.idx] = row.key
	end
	h.assert_eq(by_idx[0], "a", "a stays at 0")
	h.assert_eq(by_idx[1], nil, "idx 1 (was b) is a gap; hash does not shift")
	h.assert_eq(by_idx[2], "c", "c stays at 2 (no shift for hash)")
end)

h.test("array raw DELETE leaves a gap (shift-down is Lua-side, not a schema trigger)", function()
	-- The API's delete_array_element runs the two-phase 10^18 hop in Lua.
	-- Direct raw-SQL DELETE on the array leaves the sibling positions
	-- untouched — the schema does not shift.
	local db = fresh_array(3)  -- [10, 20, 30] at idx 0..2
	exec(db, "delete from relationships where parent = 2 and idx = 1")

	local by_idx = {}
	for row in db:nrows("select idx, scalar from relationships where parent = 2") do
		by_idx[row.idx] = row.scalar
	end
	h.assert_eq(by_idx[0], 10, "10 stays at 0")
	h.assert_eq(by_idx[1], nil, "idx 1 is a gap; schema doesn't shift")
	h.assert_eq(by_idx[2], 30, "30 stays at 2")
end)

-- ------------------------------------------------------------
-- normalize_hashes — the safety-valve helper
-- ------------------------------------------------------------

h.test("normalize_hashes: renumbers hash entries to dense 0..n-1", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	-- Sparse idx values on scalar rows.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'a', 100, 'n', 10)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'b', 200, 'n', 20)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'c', 300, 'n', 30)")

	h.normalize_hashes(db)

	local max_idx, count
	for row in db:nrows("select max(idx) as m, count(*) as c from relationships where parent = 2") do
		max_idx = row.m
		count = row.c
	end
	h.assert_eq(count, 3, "three entries")
	h.assert_eq(max_idx, 2, "max idx is 2 after normalize (0, 1, 2)")
end)

h.test("normalize_hashes: preserves insertion order", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	-- Ascending idx values (insertion order).
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'first',  10,     'n', 1)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'second', 500,    'n', 2)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'third',  9000,   'n', 3)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'fourth', 100000, 'n', 4)")

	h.normalize_hashes(db)

	local order = {}
	for row in db:nrows("select key from relationships where parent = 2 order by idx") do
		order[#order + 1] = row.key
	end
	h.assert_eq(order[1], "first")
	h.assert_eq(order[2], "second")
	h.assert_eq(order[3], "third")
	h.assert_eq(order[4], "fourth")
end)

h.test("normalize_hashes: does NOT touch array idx values", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2 (hash)
	exec(db, "insert into collections (type) values ('a')")  -- 3 (array)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'a', 1)")

	-- Both with sparse idx.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 100, 'n', 10)")
	exec(db, "insert into relationships (parent, idx, st, scalar) values (3, 100000, 'n', 20)")

	h.normalize_hashes(db)

	local hash_idx
	for row in db:nrows("select idx from relationships where parent = 2 and key = 'x'") do
		hash_idx = row.idx
	end
	h.assert_eq(hash_idx, 0, "hash entry normalized to idx 0")

	local array_idx
	for row in db:nrows("select idx from relationships where parent = 3") do
		array_idx = row.idx
	end
	h.assert_eq(array_idx, 100000, "array entry idx preserved (100000)")
end)

h.test("normalize_hashes: multiple hash parents normalized independently", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2 (hash A)
	exec(db, "insert into collections (type) values ('h')")  -- 3 (hash B)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'ha', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'hb', 1)")

	-- Hash A: two entries at sparse idx.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'x', 500, 'n', 4)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'y', 900, 'n', 5)")
	-- Hash B: two entries at sparse idx.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (3, 'p', 1000, 'n', 6)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (3, 'q', 2000, 'n', 7)")

	h.normalize_hashes(db)

	local a_max, b_max
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do a_max = row.m end
	for row in db:nrows("select max(idx) as m from relationships where parent = 3") do b_max = row.m end
	h.assert_eq(a_max, 1, "hash A: dense 0..1")
	h.assert_eq(b_max, 1, "hash B: dense 0..1")
end)

h.test("normalize_hashes: no-op on already-dense hash", function()
	local db = h.fresh_db()
	exec(db, "insert into collections (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	-- Already dense.
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'a', 0, 'n', 3)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'b', 1, 'n', 4)")
	exec(db, "insert into relationships (parent, key, idx, st, scalar) values (2, 'c', 2, 'n', 5)")

	h.normalize_hashes(db)

	local max_idx
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx = row.m
	end
	h.assert_eq(max_idx, 2, "still dense 0..2")
end)
