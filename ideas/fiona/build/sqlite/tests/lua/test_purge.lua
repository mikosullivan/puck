-- Tests for the Lua-side GC drain — Drinian-style backward-trace.
-- Every mutating API call runs Db:_drain_needs_trace at its atomic()
-- boundary, so after each op the DB is in a fully-resolved state:
-- unreachable subgraphs are gone, no needs_trace or in_trace flags
-- linger. These tests exercise the observable outcomes: what's still
-- present, what got collected, and the invariant that flags are always
-- clean at rest.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- Utility — assert the drain left the DB clean
-- ------------------------------------------------------------

local function assert_flags_clean(db, label)
	local count

	for row in db._conn:nrows("select count(*) as c from collections where needs_trace = 1 or in_trace = 1") do
		count = row.c
	end

	h.assert_eq(count, 0, (label or "flags clean") .. ": no needs_trace or in_trace should survive drain")
end

-- ------------------------------------------------------------
-- Simple orphan cases (scalar children live inline — no collection to
-- collect, but the schema-level mark/drain still exercises correctly)
-- ------------------------------------------------------------

h.test("purge: orphaned collection child is deleted after its only edge is removed", function()
	local db = fiona.get_db(":memory:", "rw")

	local child = db:atomic(function()
		local pk = db:add_hash()
		db:set_hash_ref(1, "child", pk)
		return pk
	end)

	db:delete_hash_element(1, "child")

	local n
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. child) do
		n = row.c
	end

	h.assert_eq(n, 0, "orphaned child collected")
	assert_flags_clean(db)
end)

h.test("purge: collection child still reachable via another parent survives", function()
	-- root -> h2 -> shared, root -> shared. Delete h2 -> shared.
	local db = fiona.get_db(":memory:", "rw")

	local h2, shared = db:atomic(function()
		local hh = db:add_hash()
		db:set_hash_ref(1, "h2", hh)
		local sh = db:add_hash()
		db:set_hash_ref(hh, "s", sh)
		db:set_hash_ref(1, "backup_anchor", sh)
		return hh, sh
	end)

	db:delete_hash_element(h2, "s")

	local n
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. shared) do
		n = row.c
	end

	h.assert_eq(n, 1, "shared survives via the root's backup_anchor edge")
	assert_flags_clean(db)
end)

h.test("purge: whole subtree of an orphaned branch is deleted", function()
	-- root -> h2 -> h3 -> h4 (leaf). Cut root -> h2 → whole chain goes.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3, h4 = db:atomic(function()
		local a = db:add_hash()
		db:set_hash_ref(1, "branch", a)
		local b = db:add_hash()
		db:set_hash_ref(a, "sub", b)
		local c = db:add_hash()
		db:set_hash_ref(b, "leaf", c)
		return a, b, c
	end)

	db:delete_hash_element(1, "branch")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from collections where collection_pk in (" .. h2 .. "," .. h3 .. "," .. h4 .. ")"
	) do
		n = row.c
	end

	h.assert_eq(n, 0, "subtree fully collected")
	assert_flags_clean(db)
end)

h.test("purge: deleting a scalar-carrying edge doesn't fire the mark trigger", function()
	-- Scalar rows have child = null; the mark trigger's `when old.child
	-- is not null` guard means deleting them is a plain no-op on the
	-- drain worklist. Nothing should get GC'd or marked.
	local db = fiona.get_db(":memory:", "rw")

	db:set_hash_scalar(1, "k", "leaf")

	local before
	for row in db._conn:nrows("select count(*) as c from collections") do
		before = row.c
	end

	db:delete_hash_element(1, "k")

	local after
	for row in db._conn:nrows("select count(*) as c from collections") do
		after = row.c
	end

	h.assert_eq(after, before, "collection count unchanged — no collection GCed")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Cycles
-- ------------------------------------------------------------

h.test("purge: fully detached cycle is deleted", function()
	-- root -> h2, h2 <-> h3. Cut root -> h2 → cycle detaches, both die.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3 = db:atomic(function()
		local a = db:add_hash()
		local b = db:add_hash()
		db:set_hash_ref(1, "entry", a)
		db:set_hash_ref(a, "forward", b)
		db:set_hash_ref(b, "back", a)
		return a, b
	end)

	db:delete_hash_element(1, "entry")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from collections where collection_pk in (" .. h2 .. "," .. h3 .. ")"
	) do
		n = row.c
	end

	h.assert_eq(n, 0, "both cycle members collected in one pass")
	assert_flags_clean(db)
end)

h.test("purge: root refs a circular set — delete root edge collapses to 1 collection, 0 relationships", function()
	-- root → h2, h2 ↔ h3. Root's edge is the only anchor. After deleting
	-- root's edge, the DB should contain exactly the root row and no
	-- relationships whatsoever.
	local db = fiona.get_db(":memory:", "rw")

	db:atomic(function()
		local a = db:add_hash()
		local b = db:add_hash()
		db:set_hash_ref(1, "entry", a)
		db:set_hash_ref(a, "next", b)
		db:set_hash_ref(b, "back", a)
	end)

	db:delete_hash_element(1, "entry")

	local coll_count
	for row in db._conn:nrows("select count(*) as c from collections") do
		coll_count = row.c
	end

	h.assert_eq(coll_count, 1, "exactly one collection row (root)")

	local rel_count
	for row in db._conn:nrows("select count(*) as c from relationships") do
		rel_count = row.c
	end

	h.assert_eq(rel_count, 0, "zero relationships")

	assert_flags_clean(db)
end)

h.test("purge: cycle still connected to root stays intact", function()
	-- root -> h2, root -> h3, h2 <-> h3. Cut root -> h2. h2 still
	-- reachable via root -> h3 -> h2, so both stay.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3 = db:atomic(function()
		local a = db:add_hash()
		local b = db:add_hash()
		db:set_hash_ref(1, "a", a)
		db:set_hash_ref(1, "b", b)
		db:set_hash_ref(a, "forward", b)
		db:set_hash_ref(b, "back", a)
		return a, b
	end)

	db:delete_hash_element(1, "a")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from collections where collection_pk in (" .. h2 .. "," .. h3 .. ")"
	) do
		n = row.c
	end

	h.assert_eq(n, 2, "both cycle members still reachable via the surviving root edge")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Child-swap (update path via set_hash_ref)
-- ------------------------------------------------------------

h.test("purge: update-of-child collects the swapped-out old child if unreachable", function()
	local db = fiona.get_db(":memory:", "rw")

	local old_child = db:add_hash()
	db:set_hash_ref(1, "x", old_child)

	local new_child = db:add_hash()
	db:set_hash_ref(1, "x", new_child)

	local n
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. old_child) do
		n = row.c
	end

	h.assert_eq(n, 0, "old child collected after swap")

	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. new_child) do
		n = row.c
	end

	h.assert_eq(n, 1, "new child survives — anchored via the swapped edge")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Root safety
-- ------------------------------------------------------------

h.test("purge: root is never deleted or marked, even when its only edge goes", function()
	local db = fiona.get_db(":memory:", "rw")

	local child = db:add_hash()
	db:set_hash_ref(1, "x", child)
	db:delete_hash_element(1, "x")

	local n
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = 1") do
		n = row.c
	end

	h.assert_eq(n, 1, "root survives")

	for row in db._conn:nrows("select needs_trace, in_trace from collections where collection_pk = 1") do
		h.assert_true(row.needs_trace == nil, "root never marked needs_trace")
		h.assert_true(row.in_trace == nil, "root never marked in_trace")
	end

	assert_flags_clean(db)
end)

h.test("purge: root → root self-loop deletion leaves root alive and unmarked", function()
	-- Edge case: root references itself. When we delete that relationship,
	-- old.child = 1, which the mark trigger's `when old.child <> 1` guard
	-- rejects, so nothing gets flagged. Root survives, the self-loop is
	-- gone, and no drain state leaks.
	local db = fiona.get_db(":memory:", "rw")

	db:set_hash_ref(1, "self", 1)

	-- Sanity: the self-loop is present.
	local pre
	for row in db._conn:nrows("select count(*) as c from relationships where parent = 1 and key = 'self' and child = 1") do
		pre = row.c
	end

	h.assert_eq(pre, 1, "root → root edge established")

	db:delete_hash_element(1, "self")

	-- Root is still there.
	local root_count
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = 1") do
		root_count = row.c
	end

	h.assert_eq(root_count, 1, "root untouched by the self-loop deletion")

	-- The relationship is gone.
	local rel_count
	for row in db._conn:nrows("select count(*) as c from relationships") do
		rel_count = row.c
	end

	h.assert_eq(rel_count, 0, "self-loop relationship removed")

	assert_flags_clean(db)
end)

h.test("purge: root → root self-loop with other children — deleting self-loop preserves everything", function()
	local db = fiona.get_db(":memory:", "rw")

	local child = db:add_hash()
	db:set_hash_ref(1, "child", child)
	db:set_hash_ref(1, "self", 1)

	db:delete_hash_element(1, "self")

	-- The other child stays.
	local child_count
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. child) do
		child_count = row.c
	end

	h.assert_eq(child_count, 1, "unrelated child survives the self-loop delete")

	-- Its edge stays.
	local edge_count
	for row in db._conn:nrows(
		"select count(*) as c from relationships where parent = 1 and key = 'child'"
	) do
		edge_count = row.c
	end

	h.assert_eq(edge_count, 1, "unrelated edge intact")

	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Deep chain — the whole point of moving GC out of triggers
-- ------------------------------------------------------------

h.test("purge: 10000-deep linear chain unwinds without a depth cap", function()
	-- The Lua drain iterates in Lua, so depth is bounded by heap not by
	-- trigger recursion — no SQLITE_LIMIT_TRIGGER_DEPTH concern (which
	-- caps at 1000 by default). 10k demonstrates the cap is truly gone.
	local depth = 10000
	local db = fiona.get_db(":memory:", "rw")

	db:atomic(function()
		local parent = 1

		for i = 1, depth do
			local h_pk = db:add_hash()

			if i == 1 then
				db:set_hash_ref(1, "top", h_pk)
			else
				db:set_hash_ref(parent, "next", h_pk)
			end

			parent = h_pk
		end
	end)

	-- Sanity: chain is populated. depth hashes + root = depth + 1 rows.
	local pre_count
	for row in db._conn:nrows("select count(*) as c from collections") do
		pre_count = row.c
	end

	h.assert_eq(pre_count, depth + 1, "chain built at expected size")

	-- Cut the top edge — everything downstream is unreachable.
	db:delete_hash_element(1, "top")

	local post_count
	for row in db._conn:nrows("select count(*) as c from collections") do
		post_count = row.c
	end

	h.assert_eq(post_count, 1, "only root survives after chain teardown")

	local rel_count
	for row in db._conn:nrows("select count(*) as c from relationships") do
		rel_count = row.c
	end

	h.assert_eq(rel_count, 0, "no relationships remain")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Bundled atomic — delete + re-anchor in the same block
-- ------------------------------------------------------------

h.test("atomic: delete + re-anchor in the same block preserves the child", function()
	-- The drain runs at the outer atomic() boundary. If we delete an
	-- edge and then re-anchor the same child within the same atomic,
	-- the child ends up reachable at drain time, so it survives.
	local db = fiona.get_db(":memory:", "rw")

	local child = db:add_hash()
	db:set_hash_ref(1, "k", child)

	db:atomic(function()
		db:delete_hash_element(1, "k")
		db:set_hash_ref(1, "k2", child)  -- re-anchor at a different key
	end)

	local n
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. child) do
		n = row.c
	end

	h.assert_eq(n, 1, "child survives — was re-anchored before drain")
	assert_flags_clean(db)
end)
