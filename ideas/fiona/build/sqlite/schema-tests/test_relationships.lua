-- Tests for the relationships table.

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

-- Set up a database with a few standard hsa rows for reuse:
--   pk=1: root hash (built-in)
--   pk=2: another hash
--   pk=3: an array
--   pk=4: a string scalar
--   pk=5: a number scalar
local function db_with_fixtures()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")               -- 2
	exec(db, "insert into hsa (type) values ('a')")               -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'hello')") -- 4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 42)")      -- 5
	return db
end

-- ------------------------------------------------------------
-- Positive tests
-- ------------------------------------------------------------

h.test("insert relationship: hash parent + key + idx + string child", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'greeting', 0)")
end)

h.test("insert relationship: array parent + idx + number child", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 5, 0)")
end)

h.test("insert relationship: root hash as parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 4, 'msg', 0)")
end)

h.test("child can be any hsa type — hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 1, 'root_ref', 0)")
end)

h.test("child can be any hsa type — array", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'arr_ref', 0)")
end)

h.test("child can be any hsa type — scalar", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'num_ref', 0)")
end)

h.test("multiple parents can point at the same child (graph, not tree)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 4, 'a_ref', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'b_ref', 0)")
end)

h.test("distinct keys under the same hash parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'first', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'second', 1)")
end)

h.test("distinct idx values under the same array parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 4, 0)")
	exec(db, "insert into relationships (parent, child, idx) values (3, 5, 1)")
end)

-- idx accepts real and negative values used to be valid; the shift-trigger
-- design now requires non-negative integers (see fiona.sql for the OFFSET
-- rationale). The rejection cases live in the "idx type/range" section
-- below.

h.test("delete a relationship works", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	exec(db, "delete from relationships where parent = 2 and key = 'x'")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship deleted")
		return
	end
end)

-- ------------------------------------------------------------
-- Positive test — idx mutability
-- ------------------------------------------------------------

h.test("update idx is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 4, 0)")
	exec(db, "update relationships set idx = 5 where parent = 3 and idx = 0")

	for row in db:nrows("select idx from relationships where parent = 3") do
		h.assert_eq(row.idx, 5, "idx updated")
		return
	end
end)

-- ------------------------------------------------------------
-- Negative tests — foreign keys
-- ------------------------------------------------------------

h.test("reject parent referencing non-existent hsa row", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (999, 4, 'x', 0)")
	end, "FOREIGN KEY", "parent FK")
end)

h.test("reject child referencing non-existent hsa row", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (2, 999, 'x', 0)")
	end, "FOREIGN KEY", "child FK")
end)

h.test("delete of parent hsa row cascades to its relationships", function()
	-- FKs use `on delete cascade` on both parent and child so the purge
	-- trigger can remove hsa rows and have their edges drop. Same applies
	-- to a direct hsa delete: cascade removes edges, purge sweeps orphans.
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	exec(db, "delete from hsa where hsa_pk = 2")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship cascade-deleted with parent")
		return
	end
end)

h.test("delete of child hsa row cascades to its relationships", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	exec(db, "delete from hsa where hsa_pk = 4")

	for row in db:nrows("select count(*) as c from relationships") do
		h.assert_eq(row.c, 0, "relationship cascade-deleted with child")
		return
	end
end)

-- ------------------------------------------------------------
-- Negative tests — parent must be a hash or array
-- ------------------------------------------------------------

h.test("reject parent that references a scalar", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (4, 5, 'x', 0)")
	end, "hash or array", "scalar parent")
end)

-- ------------------------------------------------------------
-- Negative tests — key vs parent type
-- ------------------------------------------------------------

h.test("reject hash parent with no key (idx alone is not enough)", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (2, 4, 0)")
	end, "must set key", "hash needs key")
end)

h.test("reject array parent with key set", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (3, 4, 'x', 0)")
	end, "must not set key", "array can't have key")
end)

-- ------------------------------------------------------------
-- Negative tests — idx is required for every relationship
-- ------------------------------------------------------------

h.test("reject hash parent with no idx", function()
	-- Ruby/Caspian ordering means hashes carry idx too. Key alone isn't
	-- enough; NOT NULL fires (the trigger passes since key IS set).
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key) values (2, 4, 'x')")
	end, "NOT NULL", "hash needs idx too")
end)

h.test("reject array parent with no idx", function()
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child) values (3, 4)")
	end, "NOT NULL", "array needs idx")
end)

-- ------------------------------------------------------------
-- Negative tests — idx type / range
-- ------------------------------------------------------------

h.test("reject idx that is a text value", function()
	-- Untyped `idx` column (BLOB affinity) prevents SQLite from silently
	-- coercing 'foo' to a number, so typeof(idx)='text' and CHECK rejects.
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 4, 'foo')")
	end, "CHECK", "idx as text")
end)

h.test("reject idx that is a numeric-looking text", function()
	-- '42' is text (not integer); the check catches it.
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 4, '42')")
	end, "CHECK", "idx as numeric text")
end)

h.test("reject idx that is a real (float)", function()
	-- Shift-trigger design requires integer-only idx.
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 4, 3.14)")
	end, "CHECK", "idx as real")
end)

h.test("reject idx that is negative", function()
	-- Shift-trigger design requires non-negative idx (the safe range hop
	-- would collide with negatives).
	local db = db_with_fixtures()
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, idx) values (3, 4, -1)")
	end, "CHECK", "idx as negative")
end)

h.test("accept idx = 0", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 4, 0)")
end)

h.test("accept idx as very large integer (well below OFFSET)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, idx) values (3, 4, 999999999999)")
end)

-- ------------------------------------------------------------
-- Negative tests — uniqueness
-- ------------------------------------------------------------

h.test("reject duplicate (parent, key) for a hash", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'x', 1)")
	end, "UNIQUE", "duplicate key under hash")
end)

-- The old "reject duplicate (parent, idx)" tests are now covered by the
-- shift-trigger section below — the trigger auto-resolves the collision
-- by shifting the existing row up. The UNIQUE(parent, idx) constraint is
-- still active; it just never fires because the trigger clears its path.

h.test("same key under different hash parents is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into hsa (type) values ('h')")  -- 6
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'name', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (6, 4, 'name', 0)")
end)

h.test("same idx under different array parents is allowed", function()
	local db = db_with_fixtures()
	exec(db, "insert into hsa (type) values ('a')")  -- 6
	exec(db, "insert into relationships (parent, child, idx) values (3, 4, 0)")
	exec(db, "insert into relationships (parent, child, idx) values (6, 4, 0)")
end)

-- ------------------------------------------------------------
-- Negative tests — immutability (parent, child, key, rel_pk)
-- ------------------------------------------------------------

h.test("reject update of parent", function()
	local db = db_with_fixtures()
	exec(db, "insert into hsa (type) values ('h')")  -- 6
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	h.assert_raises(function()
		exec(db, "update relationships set parent = 6 where key = 'x'")
	end, "immutable", "update parent")
end)

h.test("allow update of child (content-mutable)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	exec(db, "update relationships set child = 5 where key = 'x'")
	for row in db:nrows("select child from relationships where key = 'x'") do
		h.assert_eq(row.child, 5, "child swung in place")
	end
end)

h.test("update of child fires purge trigger — old child is GCed if unreachable", function()
	-- Build root → h2, then swap h2 to a fresh h3. h2 should be GCed
	-- because the (root, 'x') edge is the only thing anchoring it.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into hsa (type) values ('h')")  -- 3
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "update relationships set child = 3 where parent = 1 and key = 'x'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk = 2") do
		h.assert_eq(row.c, 0, "old child (h2) was GCed via purge_after_update_of_child")
	end
	for row in db:nrows("select count(*) as c from hsa where hsa_pk = 3") do
		h.assert_eq(row.c, 1, "new child (h3) survives — reachable via updated edge")
	end
end)

h.test("reject update of key (hash parent)", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	h.assert_raises(function()
		exec(db, "update relationships set key = 'y' where key = 'x'")
	end, "immutable", "update key")
end)

h.test("reject update of rel_pk", function()
	local db = db_with_fixtures()
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 0)")
	h.assert_raises(function()
		exec(db, "update relationships set rel_pk = 999 where key = 'x'")
	end, "immutable", "update rel_pk")
end)

-- ------------------------------------------------------------
-- Purge trigger — garbage collection on relationship delete
-- ------------------------------------------------------------

h.test("purge: orphaned child is deleted after its only edge is removed", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'leaf')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'child', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'child'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk = 2") do
		h.assert_eq(row.c, 0, "orphaned child purged")
		return
	end
end)

h.test("purge: child still reachable via another parent survives", function()
	-- Graph shape:
	--   root -> h2 (via 'a')
	--   root -> h3 (via 'b')        <-- extra anchor
	--   h2   -> h3 (via 'shared')   <-- edge we delete
	-- Deleting h2 -> h3 leaves h3 reachable via root -> h3, so h3 stays.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into hsa (type) values ('h')")  -- 3
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'b', 1)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'shared', 0)")
	exec(db, "delete from relationships where parent = 2 and key = 'shared'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk = 3") do
		h.assert_eq(row.c, 1, "child stays; other parent still anchors it")
		return
	end
end)

h.test("purge: whole subtree of an orphaned root is deleted", function()
	-- Chain: root -> h2 -> h3 -> string s4. Cutting root -> h2 orphans all.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into hsa (type) values ('h')")  -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'leaf')")  -- 4
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'branch', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'sub', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (3, 4, 'leaf', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'branch'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk in (2,3,4)") do
		h.assert_eq(row.c, 0, "whole subtree purged")
		return
	end
end)

h.test("purge: fully detached cycle is deleted", function()
	-- root -> h2, h2 <-> h3 (mutual). Cutting root -> h2 detaches the
	-- {h2, h3} cycle. Reachable-from-root can't see it, so both purge.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into hsa (type) values ('h')")  -- 3
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'entry', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'forward', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (3, 2, 'back', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'entry'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk in (2,3)") do
		h.assert_eq(row.c, 0, "detached cycle purged")
		return
	end
end)

h.test("purge: cycle still connected to root stays intact", function()
	-- root -> h2, root -> h3, h2 <-> h3. Cutting root -> h2 leaves h3
	-- reachable via root -> h3, and h2 still reachable via root -> h3 -> h2.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into hsa (type) values ('h')")  -- 3
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'b', 1)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'forward', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (3, 2, 'back', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'a'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk in (2,3)") do
		h.assert_eq(row.c, 2, "both cycle members still reachable")
		return
	end
end)

h.test("purge: root itself is never deleted even when all its edges go", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'x')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'x', 0)")
	exec(db, "delete from relationships where parent = 1 and key = 'x'")

	for row in db:nrows("select count(*) as c from hsa where hsa_pk = 1") do
		h.assert_eq(row.c, 1, "root always survives (base case of the CTE)")
		return
	end
end)

-- ------------------------------------------------------------
-- Shift triggers — new record inserted at an occupied idx
-- ------------------------------------------------------------

-- Small helper for shift tests: build an array under root with N scalar
-- children packed at idx 0..N-1. Returns the array's hsa_pk (2). The
-- children get hsa_pk 3..N+2.
local function fresh_array(n)
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('a')")                                     -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")

	for i = 0, n - 1 do
		exec(db, string.format(
			"insert into hsa (type, st, value) values ('s', 'n', %d)", i * 10))         -- 3..n+2
		exec(db, string.format(
			"insert into relationships (parent, child, idx) values (2, %d, %d)", 3 + i, i))
	end

	return db
end

-- Read the array under parent 2 as an ordered array of children (indexed
-- 1..n in Lua, i.e., idx 0..n-1 in the DB).
local function read_array(db)
	local out = {}

	for row in db:nrows("select idx, child from relationships where parent = 2 order by idx") do
		out[#out + 1] = row.child
	end

	return out
end

h.test("shift on insert: collision at existing idx bumps sibling up", function()
	local db = fresh_array(2)  -- array holds [3, 4] at idx 0, 1
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 999)")  -- 5
	exec(db, "insert into relationships (parent, child, idx) values (2, 5, 0)")

	local children = read_array(db)
	h.assert_eq(children[1], 5, "new child at idx 0")
	h.assert_eq(children[2], 3, "old idx 0 shifted to 1")
	h.assert_eq(children[3], 4, "old idx 1 shifted to 2")
end)

h.test("shift on insert: cascade — insert at 0 in a 5-item array", function()
	local db = fresh_array(5)  -- array holds [3, 4, 5, 6, 7] at idx 0..4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 999)")  -- 8
	exec(db, "insert into relationships (parent, child, idx) values (2, 8, 0)")

	local children = read_array(db)
	h.assert_eq(children[1], 8, "new at 0")
	h.assert_eq(children[2], 3, "3 shifted to 1")
	h.assert_eq(children[3], 4, "4 shifted to 2")
	h.assert_eq(children[4], 5, "5 shifted to 3")
	h.assert_eq(children[5], 6, "6 shifted to 4")
	h.assert_eq(children[6], 7, "7 shifted to 5")
end)

h.test("shift on insert: insert in the middle shifts only rows at or above", function()
	local db = fresh_array(5)  -- [3, 4, 5, 6, 7]
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 999)")  -- 8
	exec(db, "insert into relationships (parent, child, idx) values (2, 8, 2)")

	local children = read_array(db)
	-- Expected: [3, 4, 8, 5, 6, 7]
	h.assert_eq(children[1], 3, "0 unchanged")
	h.assert_eq(children[2], 4, "1 unchanged")
	h.assert_eq(children[3], 8, "new at 2")
	h.assert_eq(children[4], 5, "old 2 shifted to 3")
	h.assert_eq(children[5], 6, "old 3 shifted to 4")
	h.assert_eq(children[6], 7, "old 4 shifted to 5")
end)

h.test("shift on insert: sparse insert (no collision) is a no-op", function()
	local db = fresh_array(3)  -- [3, 4, 5] at idx 0..2
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 999)")  -- 6
	exec(db, "insert into relationships (parent, child, idx) values (2, 6, 100)")

	local at_100
	for row in db:nrows("select child from relationships where parent = 2 and idx = 100") do
		at_100 = row.child
	end
	h.assert_eq(at_100, 6, "sparse insert lands at 100 with no shift")

	-- Existing rows unchanged.
	for row in db:nrows("select count(*) as c from relationships where parent = 2 and idx in (0,1,2)") do
		h.assert_eq(row.c, 3, "originals still at 0..2")
	end
end)

h.test("shift on insert: hash — collision at (parent, idx) shifts, key uniqueness still enforced", function()
	-- Hash parent: (parent, key) is unique too. A collision on idx alone
	-- shifts as normal; a collision on key alone raises.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")                                              -- 2
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")                          -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 20)")                          -- 4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 30)")                          -- 5
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'a', 0)")
	-- New entry with different key + same idx: shift lets it in.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'b', 0)")

	local at_0, at_1
	for row in db:nrows("select idx, key from relationships where parent = 2 order by idx") do
		if row.idx == 0 then at_0 = row.key
		elseif row.idx == 1 then at_1 = row.key end
	end
	h.assert_eq(at_0, "b", "new key 'b' at idx 0")
	h.assert_eq(at_1, "a", "key 'a' shifted to idx 1")

	-- Same key as existing entry still raises regardless of idx.
	h.assert_raises(function()
		exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'a', 5)")
	end, "UNIQUE", "duplicate key under hash still rejected")
end)

-- ------------------------------------------------------------
-- Shift triggers — moving an existing record via UPDATE OF idx
-- ------------------------------------------------------------

h.test("shift on move: up-move shifts intervening siblings up by 1", function()
	local db = fresh_array(5)  -- [3, 4, 5, 6, 7] at idx 0..4
	-- Move child 6 (currently at idx 3) to idx 1.
	exec(db, "update relationships set idx = 1 where parent = 2 and child = 6")

	local children = read_array(db)
	-- Expected: [3, 6, 4, 5, 7]
	h.assert_eq(children[1], 3, "3 stays at 0")
	h.assert_eq(children[2], 6, "6 moved to 1")
	h.assert_eq(children[3], 4, "4 shifted to 2")
	h.assert_eq(children[4], 5, "5 shifted to 3")
	h.assert_eq(children[5], 7, "7 stays at 4 (outside shift range)")
end)

h.test("shift on move: down-move shifts intervening siblings down by 1", function()
	local db = fresh_array(5)  -- [3, 4, 5, 6, 7] at idx 0..4
	-- Move child 4 (currently at idx 1) to idx 3.
	exec(db, "update relationships set idx = 3 where parent = 2 and child = 4")

	local children = read_array(db)
	-- Expected: [3, 5, 6, 4, 7]
	h.assert_eq(children[1], 3, "3 stays at 0")
	h.assert_eq(children[2], 5, "5 shifted to 1")
	h.assert_eq(children[3], 6, "6 shifted to 2")
	h.assert_eq(children[4], 4, "4 moved to 3")
	h.assert_eq(children[5], 7, "7 stays at 4 (outside shift range)")
end)

h.test("shift on move: no collision means no shift", function()
	local db = fresh_array(3)  -- [3, 4, 5] at idx 0..2
	-- Move child 3 (idx 0) to idx 100 (fresh position).
	exec(db, "update relationships set idx = 100 where parent = 2 and child = 3")

	local at_100
	for row in db:nrows("select child from relationships where parent = 2 and idx = 100") do
		at_100 = row.child
	end
	h.assert_eq(at_100, 3, "3 at 100")

	-- Others unchanged at 1, 2 (0 now vacant).
	local at_1, at_2
	for row in db:nrows("select idx, child from relationships where parent = 2 order by idx") do
		if row.idx == 1 then at_1 = row.child
		elseif row.idx == 2 then at_2 = row.child end
	end
	h.assert_eq(at_1, 4, "4 unchanged at 1")
	h.assert_eq(at_2, 5, "5 unchanged at 2")
end)

h.test("shift on move: density preserved for both directions", function()
	local db = fresh_array(6)  -- [3, 4, 5, 6, 7, 8]

	-- Up-move: 8 (idx 5) to idx 0.
	exec(db, "update relationships set idx = 0 where parent = 2 and child = 8")
	local after_up = read_array(db)
	h.assert_eq(#after_up, 6, "still 6 children")
	local max_idx_up
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx_up = row.m
	end
	h.assert_eq(max_idx_up, 5, "max idx still 5 — dense after up-move")

	-- Now move 3 (currently at idx 1 after the shift) to idx 5.
	exec(db, "update relationships set idx = 5 where parent = 2 and child = 3")
	local after_down = read_array(db)
	h.assert_eq(#after_down, 6, "still 6 children")
	local max_idx_down
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx_down = row.m
	end
	h.assert_eq(max_idx_down, 5, "max idx still 5 — dense after down-move")
end)

h.test("shift on move: identity update (NEW.idx = OLD.idx) is a no-op", function()
	local db = fresh_array(3)  -- [3, 4, 5] at idx 0..2
	exec(db, "update relationships set idx = 1 where parent = 2 and child = 4")

	local children = read_array(db)
	h.assert_eq(children[1], 3, "unchanged")
	h.assert_eq(children[2], 4, "unchanged")
	h.assert_eq(children[3], 5, "unchanged")
end)

-- ------------------------------------------------------------
-- Shift-by-1 on array delete — Ruby arr.delete_at() semantics
-- ------------------------------------------------------------

h.test("array delete shifts every higher-idx sibling down by 1 (dense case)", function()
	local db = fresh_array(5)  -- [3, 4, 5, 6, 7] at idx 0..4
	-- Delete idx 2 (child 5); expect 3, 4 stay at 0, 1 and 6, 7 shift to 2, 3.
	exec(db, "delete from relationships where parent = 2 and idx = 2")

	local by_idx = {}
	for row in db:nrows("select idx, child from relationships where parent = 2") do
		by_idx[row.idx] = row.child
	end

	h.assert_eq(by_idx[0], 3, "3 stays at 0")
	h.assert_eq(by_idx[1], 4, "4 stays at 1")
	h.assert_eq(by_idx[2], 6, "6 shifted from 3 to 2")
	h.assert_eq(by_idx[3], 7, "7 shifted from 4 to 3")
	h.assert_eq(by_idx[4], nil, "idx 4 no longer occupied")
end)

h.test("array delete preserves sparseness — shifts by exactly 1, doesn't collapse gaps", function()
	-- Sparse array: two elements, one at idx 0 and one at idx 1000.
	-- Deleting idx 0 shifts the b element from 1000 → 999, NOT 0.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('a')")                                      -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")                  -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 20)")                  -- 4
	exec(db, "insert into relationships (parent, child, idx) values (2, 3, 0)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 4, 1000)")

	exec(db, "delete from relationships where parent = 2 and idx = 0")

	local at
	for row in db:nrows("select idx, child from relationships where parent = 2") do
		at = row
	end
	h.assert_eq(at.child, 4, "only child 4 remains")
	h.assert_eq(at.idx, 999, "shifted by exactly 1 (1000 → 999); sparseness preserved")
end)

h.test("array delete of last idx: no siblings to shift, straightforward removal", function()
	local db = fresh_array(3)  -- [3, 4, 5] at idx 0..2
	exec(db, "delete from relationships where parent = 2 and idx = 2")

	local children = read_array(db)
	h.assert_eq(#children, 2, "two remain")
	h.assert_eq(children[1], 3, "3 stays at 0")
	h.assert_eq(children[2], 4, "4 stays at 1")
end)

h.test("array delete of only element leaves an empty array", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('a')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")  -- 3
	exec(db, "insert into relationships (parent, child, idx) values (2, 3, 0)")

	exec(db, "delete from relationships where parent = 2 and idx = 0")

	for row in db:nrows("select count(*) as c from relationships where parent = 2") do
		h.assert_eq(row.c, 0, "no siblings left in the array")
		return
	end
end)

h.test("hash delete does NOT shift; leaves a gap (hash idx is internal)", function()
	-- Hashes get gap-preserving delete — users don't observe hash idx directly.
	-- Confirms the WHEN clause on the shift trigger correctly excludes hashes.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")                                             -- 2 (hash)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")                         -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 20)")                         -- 4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 30)")                         -- 5

	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'a', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'b', 1)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'c', 2)")

	-- Delete the middle entry by key.
	exec(db, "delete from relationships where parent = 2 and key = 'b'")

	local by_idx = {}
	for row in db:nrows("select idx, key from relationships where parent = 2") do
		by_idx[row.idx] = row.key
	end
	h.assert_eq(by_idx[0], "a", "a stays at 0")
	h.assert_eq(by_idx[1], nil, "idx 1 (was b) is a gap; hash does not shift")
	h.assert_eq(by_idx[2], "c", "c stays at 2 (no shift for hash)")
end)

h.test("array shift-down handles a large sparse gap correctly", function()
	-- Regression test for the empirical UPDATE processing order. If SQLite
	-- ever changes planner behavior to process in a non-ascending order,
	-- shifting a dense-then-sparse-then-dense pattern would fail with
	-- unique-constraint violations. This test catches that.
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('a')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'a', 0)")

	for i = 3, 8 do
		exec(db, string.format("insert into hsa (type, st, value) values ('s', 'n', %d)", i))
	end

	-- Three-cluster pattern: [3 at 0, 4 at 1, 5 at 2, 6 at 100, 7 at 101, 8 at 102].
	exec(db, "insert into relationships (parent, child, idx) values (2, 3, 0)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 4, 1)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 5, 2)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 6, 100)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 7, 101)")
	exec(db, "insert into relationships (parent, child, idx) values (2, 8, 102)")

	-- Delete an entry in the first cluster.
	exec(db, "delete from relationships where parent = 2 and idx = 1")

	local by_idx = {}
	for row in db:nrows("select idx, child from relationships where parent = 2") do
		by_idx[row.idx] = row.child
	end
	h.assert_eq(by_idx[0], 3,  "3 stays at 0")
	h.assert_eq(by_idx[1], 5,  "5 shifted from 2 to 1")
	h.assert_eq(by_idx[2], nil, "idx 2 vacated by the shift")
	h.assert_eq(by_idx[99],  6, "6 shifted from 100 to 99 — sparse gap preserved")
	h.assert_eq(by_idx[100], 7, "7 shifted from 101 to 100")
	h.assert_eq(by_idx[101], 8, "8 shifted from 102 to 101")
end)

-- ------------------------------------------------------------
-- normalize_hashes — explicit safety-valve API method
-- ------------------------------------------------------------

h.test("normalize_hashes: renumbers hash entries to dense 0..n-1", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2 (hash)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")  -- 3
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 20)")  -- 4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 30)")  -- 5

	-- Sparse idx values.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'a', 100)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'b', 200)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'c', 300)")

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
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	for i = 3, 6 do
		exec(db, string.format("insert into hsa (type, st, value) values ('s', 'n', %d)", i))
	end

	-- Ascending idx values, insertion order == first/second/third/fourth.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'first',  10)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'second', 500)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'third',  9000)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 6, 'fourth', 100000)")

	h.normalize_hashes(db)

	local order = {}
	for row in db:nrows("select key from relationships where parent = 2 order by idx") do
		order[#order + 1] = row.key
	end
	h.assert_eq(order[1], "first",  "first at idx 0")
	h.assert_eq(order[2], "second", "second at idx 1")
	h.assert_eq(order[3], "third",  "third at idx 2")
	h.assert_eq(order[4], "fourth", "fourth at idx 3")
end)

h.test("normalize_hashes: does NOT touch array idx values", function()
	local db = h.fresh_db()
	-- Set up a hash AND an array under root.
	exec(db, "insert into hsa (type) values ('h')")  -- 2 (hash)
	exec(db, "insert into hsa (type) values ('a')")  -- 3 (array)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'a', 1)")
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 10)")  -- 4
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 20)")  -- 5

	-- Put both in with sparse idx.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 100)")
	exec(db, "insert into relationships (parent, child, idx) values (3, 5, 100000)")

	h.normalize_hashes(db)

	-- Hash entry renumbered.
	local hash_idx
	for row in db:nrows("select idx from relationships where parent = 2 and key = 'x'") do
		hash_idx = row.idx
	end
	h.assert_eq(hash_idx, 0, "hash entry normalized to idx 0")

	-- Array entry unchanged.
	local array_idx
	for row in db:nrows("select idx from relationships where parent = 3") do
		array_idx = row.idx
	end
	h.assert_eq(array_idx, 100000, "array entry idx preserved (100000)")
end)

h.test("normalize_hashes: multiple hash parents normalized independently", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2 (hash A)
	exec(db, "insert into hsa (type) values ('h')")  -- 3 (hash B)
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'ha', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 3, 'hb', 1)")

	for i = 4, 7 do
		exec(db, string.format("insert into hsa (type, st, value) values ('s', 'n', %d)", i))
	end

	-- Hash A: two entries at sparse idx.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'x', 500)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'y', 900)")
	-- Hash B: two entries at sparse idx.
	exec(db, "insert into relationships (parent, child, key, idx) values (3, 6, 'p', 1000)")
	exec(db, "insert into relationships (parent, child, key, idx) values (3, 7, 'q', 2000)")

	h.normalize_hashes(db)

	-- Each hash independently 0..1.
	local a_max, b_max
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do a_max = row.m end
	for row in db:nrows("select max(idx) as m from relationships where parent = 3") do b_max = row.m end
	h.assert_eq(a_max, 1, "hash A: dense 0..1")
	h.assert_eq(b_max, 1, "hash B: dense 0..1")
end)

h.test("normalize_hashes: no-op on already-dense hash", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")  -- 2
	exec(db, "insert into relationships (parent, child, key, idx) values (1, 2, 'h', 0)")

	for i = 3, 5 do
		exec(db, string.format("insert into hsa (type, st, value) values ('s', 'n', %d)", i))
	end

	-- Already dense: idx 0, 1, 2.
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 3, 'a', 0)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 4, 'b', 1)")
	exec(db, "insert into relationships (parent, child, key, idx) values (2, 5, 'c', 2)")

	h.normalize_hashes(db)

	local max_idx
	for row in db:nrows("select max(idx) as m from relationships where parent = 2") do
		max_idx = row.m
	end
	h.assert_eq(max_idx, 2, "still dense 0..2, order preserved")
end)

