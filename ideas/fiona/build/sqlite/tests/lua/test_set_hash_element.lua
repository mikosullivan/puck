-- Tests for db:set_hash_element(parent, key, child) — insert or replace a
-- (key -> child) mapping under a hash parent, preserving key position on
-- replace and appending at max+1 for new keys.

local h = require("helpers")
local fiona = require("fiona")

local function rels_for(db, parent_pk)
	local out = {}

	for row in db._conn:nrows("select key, child, idx from relationships where parent = " .. parent_pk .. " order by idx") do
		table.insert(out, row)
	end

	return out
end

local function first_row(db, sql)
	for row in db._conn:nrows(sql) do
		return row
	end
end

h.test("set_hash_element under a hash — new key inserts at idx 0", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	local child_pk = db:add_scalar("hello")

	db:set_hash_element(hash_pk, "greeting", child_pk)

	local rels = rels_for(db, hash_pk)
	h.assert_eq(#rels, 1, "one relationship exists")
	h.assert_eq(rels[1].key, "greeting", "key stored")
	h.assert_eq(rels[1].child, child_pk, "child stored")
	h.assert_eq(rels[1].idx, 0, "first entry gets idx 0")
end)

h.test("set_hash_element appends new keys at increasing idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()

	db:set_hash_element(hash_pk, "a", db:add_scalar(1))
	db:set_hash_element(hash_pk, "b", db:add_scalar(2))
	db:set_hash_element(hash_pk, "c", db:add_scalar(3))

	local rels = rels_for(db, hash_pk)
	h.assert_eq(#rels, 3, "three entries")
	h.assert_eq(rels[1].key, "a")
	h.assert_eq(rels[1].idx, 0)
	h.assert_eq(rels[2].key, "b")
	h.assert_eq(rels[2].idx, 1)
	h.assert_eq(rels[3].key, "c")
	h.assert_eq(rels[3].idx, 2)
end)

h.test("set_hash_element replaces value in place, preserving idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()

	db:set_hash_element(hash_pk, "a", db:add_scalar(1))
	db:set_hash_element(hash_pk, "b", db:add_scalar(2))
	db:set_hash_element(hash_pk, "c", db:add_scalar(3))

	-- Replace 'b' with a new scalar.
	local new_b = db:add_scalar(99)
	db:set_hash_element(hash_pk, "b", new_b)

	local rels = rels_for(db, hash_pk)
	h.assert_eq(#rels, 3, "still three entries")
	h.assert_eq(rels[2].key, "b", "b is still at position 1")
	h.assert_eq(rels[2].idx, 1, "idx preserved")
	h.assert_eq(rels[2].child, new_b, "child updated")
end)

h.test("set_hash_element GCs the old child if it becomes unreachable", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_element(1, "root_hash", hash_pk)

	local old_child = db:add_scalar("old")
	db:set_hash_element(hash_pk, "key", old_child)

	local before = first_row(db, "select count(*) as n from hsa").n
	h.assert_true(before >= 3, "at least root, hash, old_child exist")

	-- Replace with a new scalar. old_child becomes unreachable → GC'd.
	db:set_hash_element(hash_pk, "key", db:add_scalar("new"))

	local gone = first_row(db, "select count(*) as n from hsa where hsa_pk = " .. old_child).n
	h.assert_eq(gone, 0, "old child was garbage-collected")
end)

h.test("set_hash_element rejects a non-hash parent via schema trigger", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_hash_element(arr_pk, "k", child_pk)
	end, nil, "trigger blocks hash entry under array parent")
end)

h.test("set_hash_element raises on invalid parent_pk (FK)", function()
	local db = fiona.get_db(":memory:", "rw")
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_hash_element(999999, "k", child_pk)
	end, nil, "FK on parent")
end)

h.test("set_hash_element raises on invalid child_pk (FK)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()

	h.assert_raises(function()
		db:set_hash_element(hash_pk, "k", 999999)
	end, nil, "FK on child")
end)

h.test("set_hash_element type checks — non-string key raises early", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	local child_pk = db:add_scalar("x")

	h.assert_raises(function()
		db:set_hash_element(hash_pk, 42, child_pk)
	end, "key must be a string", "non-string key")
end)

h.test("set_hash_element to the SAME child is a no-op", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_element(1, "root_hash", hash_pk)

	local child_pk = db:add_scalar("stable")
	db:set_hash_element(hash_pk, "key", child_pk)

	-- Naïve DELETE+INSERT would have BR eat the child during the delete,
	-- then FK-fail on the reinsert. The no-op short-circuit avoids that.
	db:set_hash_element(hash_pk, "key", child_pk)

	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. hash_pk .. " and key = 'key'") do
		h.assert_eq(row.c, 1, "still exactly one (hash, 'key') relationship")
	end

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. child_pk) do
		h.assert_eq(row.c, 1, "child still exists — no-op respected")
	end
end)

h.test("set_hash_element preserves the hash element's index when replacing (already-covered restatement)", function()
	-- Explicit restatement of the position-preservation guarantee: after a
	-- replace, the (parent, key) entry occupies the same idx it did before.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_element(1, "root_hash", hash_pk)

	db:set_hash_element(hash_pk, "alpha", db:add_scalar(1))
	db:set_hash_element(hash_pk, "beta",  db:add_scalar(2))
	db:set_hash_element(hash_pk, "gamma", db:add_scalar(3))

	local before = {}
	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk .. " order by idx") do
		before[row.key] = row.idx
	end

	-- Replace beta (currently at idx 1) with a fresh scalar.
	db:set_hash_element(hash_pk, "beta", db:add_scalar(99))

	local after = {}
	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk .. " order by idx") do
		after[row.key] = row.idx
	end

	h.assert_eq(after.alpha, before.alpha, "alpha's idx unchanged")
	h.assert_eq(after.beta,  before.beta,  "beta's idx unchanged (position preserved on replace)")
	h.assert_eq(after.gamma, before.gamma, "gamma's idx unchanged")
end)

h.test("set_hash_element: replacing with a descendant of the old child now works (formerly pathological)", function()
	-- Setup: root → hash → old_parent → deep_child
	-- Call: db:set_hash_element(hash, "key", deep_child)
	--   With the mutable-child move, this is a single UPDATE that swings
	--   the (hash, "key") edge from old_parent to deep_child.
	--   purge_after_update_of_child fires with OLD.child = old_parent:
	--     walk upward from old_parent finds nothing (its only edge was the
	--     one just re-pointed away), so old_parent gets GCed. Cascade
	--     removes (old_parent, "sub"). purge_after_delete fires with
	--     OLD.child = deep_child; walk from deep_child finds the newly
	--     rewired (hash, "key") edge → root; deep_child survives.
	local db = fiona.get_db(":memory:", "rw")

	local hash = db:add_hash()
	db:set_hash_element(1, "root_hash", hash)

	local old_parent = db:add_hash()
	db:set_hash_element(hash, "key", old_parent)

	local deep_child = db:add_scalar("i live under old_parent")
	db:set_hash_element(old_parent, "sub", deep_child)

	db:set_hash_element(hash, "key", deep_child)  -- used to raise FK; now clean

	-- The (hash, "key") edge now points at deep_child.
	local child_after
	for row in db._conn:nrows("select child from relationships where parent = " .. hash .. " and key = 'key'") do
		child_after = row.child
	end
	h.assert_eq(child_after, deep_child, "hash['key'] now points at deep_child")

	-- old_parent is gone (was only reachable through the just-rewired edge).
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. old_parent) do
		h.assert_eq(row.c, 0, "old_parent was GCed")
	end

	-- deep_child survives (reachable through the new edge).
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. deep_child) do
		h.assert_eq(row.c, 1, "deep_child survived — still reachable via new (hash, 'key') edge")
	end
end)

h.test("set_hash_element raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_hash_element(1, "k", 1)
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
