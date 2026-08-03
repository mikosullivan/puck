-- Tests for db:set_hash_ref(parent, key, ref_pk) — anchor a collection
-- reference under a hash parent. Covers the three shape-transition cases:
-- fresh insert, in-place update (same target = no-op, swing target),
-- and swing from scalar-shape to ref-shape. Fresh keys append at
-- max(idx) + 1; replacements keep the existing idx.

local h = require("helpers")
local fiona = require("fiona")

local function rels_for(db, parent_pk)
	local out = {}

	for row in db._conn:nrows("select key, child, idx, st, scalar from relationships where parent = " .. parent_pk .. " order by idx") do
		table.insert(out, row)
	end

	return out
end

local function row_count(db, sql)
	for row in db._conn:nrows(sql) do
		return row.c
	end

	return 0
end

h.test("set_hash_ref: fresh insert lands at idx 0", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	local child_pk = db:add_hash()
	db:set_hash_ref(hash_pk, "child", child_pk)

	local rels = rels_for(db, hash_pk)
	h.assert_eq(#rels, 1, "one relationship exists")
	h.assert_eq(rels[1].key, "child", "key stored")
	h.assert_eq(rels[1].child, child_pk, "child stored")
	h.assert_eq(rels[1].idx, 0, "first entry gets idx 0")
	h.assert_true(rels[1].st == nil, "st null on ref row")
	h.assert_true(rels[1].scalar == nil, "scalar null on ref row")
end)

h.test("set_hash_ref: appends new keys at increasing idx", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	db:set_hash_ref(hash_pk, "a", db:add_hash())
	db:set_hash_ref(hash_pk, "b", db:add_hash())
	db:set_hash_ref(hash_pk, "c", db:add_hash())

	local rels = rels_for(db, hash_pk)
	h.assert_eq(#rels, 3, "three entries")
	h.assert_eq(rels[1].key, "a")
	h.assert_eq(rels[1].idx, 0)
	h.assert_eq(rels[2].key, "b")
	h.assert_eq(rels[2].idx, 1)
	h.assert_eq(rels[3].key, "c")
	h.assert_eq(rels[3].idx, 2)
end)

h.test("set_hash_ref: same target is a no-op — child still alive", function()
	-- Setting the SAME child again short-circuits without touching the row.
	-- If it did a delete/reinsert, the mark trigger would fire and the drain
	-- would collect a child with no other anchor.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	local child_pk = db:add_hash()
	db:set_hash_ref(hash_pk, "k", child_pk)

	-- Second call with the same ref_pk — no change.
	db:set_hash_ref(hash_pk, "k", child_pk)

	h.assert_eq(row_count(db, "select count(*) as c from relationships where parent = " .. hash_pk .. " and key = 'k'"), 1,
		"still exactly one (parent, 'k') row")
	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. child_pk), 1,
		"child survived the no-op")
end)

h.test("set_hash_ref: swing target GCs the old child if it becomes unreachable", function()
	-- Only anchor for old_child is the (hash_pk, 'k') edge. Swinging that
	-- edge to a different collection fires the mark trigger on old_child;
	-- the drain walks upward from it, finds no root path, and collects it.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	local old_child = db:add_hash()
	db:set_hash_ref(hash_pk, "k", old_child)

	local new_child = db:add_hash()
	db:set_hash_ref(hash_pk, "k", new_child)

	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. old_child), 0,
		"old child GCed after ref swung away")
	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. new_child), 1,
		"new child survives — anchored by the swung edge")
end)

h.test("set_hash_ref: swing target preserves idx (position stays put)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	db:set_hash_ref(hash_pk, "alpha", db:add_hash())
	db:set_hash_ref(hash_pk, "beta",  db:add_hash())
	db:set_hash_ref(hash_pk, "gamma", db:add_hash())

	local before = {}

	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk) do
		before[row.key] = row.idx
	end

	-- Replace beta with a fresh collection.
	db:set_hash_ref(hash_pk, "beta", db:add_hash())

	local after = {}

	for row in db._conn:nrows("select key, idx from relationships where parent = " .. hash_pk) do
		after[row.key] = row.idx
	end

	h.assert_eq(after.alpha, before.alpha, "alpha's idx unchanged")
	h.assert_eq(after.beta,  before.beta,  "beta's idx unchanged (position preserved)")
	h.assert_eq(after.gamma, before.gamma, "gamma's idx unchanged")
end)

h.test("set_hash_ref: swing from scalar shape to ref shape — no old collection to mark", function()
	-- Start with a scalar row, then swing to a ref. The mark trigger's guard
	-- (old.child is not null) skips this update: nothing to mark. New shape:
	-- child set, st null, scalar null.
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "root_hash", hash_pk)

	db:set_hash_scalar(hash_pk, "k", "old scalar")

	local ref_pk = db:add_hash()
	db:set_hash_ref(hash_pk, "k", ref_pk)

	for row in db._conn:nrows("select child, st, scalar from relationships where parent = " .. hash_pk .. " and key = 'k'") do
		h.assert_eq(row.child, ref_pk, "child now points at ref_pk")
		h.assert_true(row.st == nil, "st cleared to null")
		h.assert_true(row.scalar == nil, "scalar cleared to null")
	end

	-- Ref survives — it's anchored via the (hash_pk, 'k') edge.
	h.assert_eq(row_count(db, "select count(*) as c from collections where collection_pk = " .. ref_pk), 1,
		"ref survives")
end)

h.test("set_hash_ref: rejects a non-hash parent (schema trigger)", function()
	local db = fiona.get_db(":memory:", "rw")
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "arr", arr_pk)

	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_hash_ref(arr_pk, "k", child_pk)
	end, nil, "trigger blocks hash-style entry under array parent")
end)

h.test("set_hash_ref: rejects non-existent parent_pk (FK)", function()
	local db = fiona.get_db(":memory:", "rw")
	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_hash_ref(999999, "k", child_pk)
	end, nil, "FK on parent")
end)

h.test("set_hash_ref: rejects non-existent ref_pk (FK)", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	db:set_hash_ref(1, "h", hash_pk)

	h.assert_raises(function()
		db:set_hash_ref(hash_pk, "k", 999999)
	end, nil, "FK on child")
end)

h.test("set_hash_ref: rejects non-string key at the Lua boundary", function()
	local db = fiona.get_db(":memory:", "rw")
	local hash_pk = db:add_hash()
	local child_pk = db:add_hash()

	h.assert_raises(function()
		db:set_hash_ref(hash_pk, 42, child_pk)
	end, "key must be a string", "non-string key")
end)

h.test("set_hash_ref: raises on a read-only handle", function()
	local path = os.tmpname()
	os.remove(path)

	local w = fiona.get_db(path, "rw")
	w._conn:close()

	local r = fiona.get_db(path, "r")

	h.assert_raises(function()
		r:set_hash_ref(1, "k", 1)
	end, "read-only", "write blocked in 'r' mode")

	r._conn:close()
	os.remove(path)
end)
