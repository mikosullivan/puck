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
	for row in db._conn:nrows("select count(*) as c from hsa where needs_trace = 1 or in_trace = 1") do
		count = row.c
	end
	h.assert_eq(count, 0, (label or "flags clean") .. ": no needs_trace or in_trace should survive drain")
end

-- ------------------------------------------------------------
-- Simple orphan cases
-- ------------------------------------------------------------

h.test("purge: orphaned child is deleted after its only edge is removed", function()
	local db = fiona.get_db(":memory:", "rw")

	local child = db:atomic(function()
		local pk = db:add_scalar("leaf")
		db:set_hash_element(1, "child", pk)
		return pk
	end)

	db:delete_hash_element(1, "child")

	local n
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. child) do
		n = row.c
	end
	h.assert_eq(n, 0, "orphaned child collected")
	assert_flags_clean(db)
end)

h.test("purge: child still reachable via another parent survives", function()
	-- root -> h2 -> shared, root -> shared. Delete h2 -> shared.
	local db = fiona.get_db(":memory:", "rw")

	local h2, shared = db:atomic(function()
		local hh = db:add_hash()
		db:set_hash_element(1, "h2", hh)
		local sh = db:add_scalar("shared")
		db:set_hash_element(hh, "s", sh)
		db:set_hash_element(1, "backup_anchor", sh)
		return hh, sh
	end)

	db:delete_hash_element(h2, "s")

	local n
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. shared) do
		n = row.c
	end
	h.assert_eq(n, 1, "shared survives via the root's backup_anchor edge")
	assert_flags_clean(db)
end)

h.test("purge: whole subtree of an orphaned branch is deleted", function()
	-- root -> h2 -> h3 -> leaf. Cut root -> h2 → whole chain goes.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3, leaf = db:atomic(function()
		local a = db:add_hash()
		db:set_hash_element(1, "branch", a)
		local b = db:add_hash()
		db:set_hash_element(a, "sub", b)
		local l = db:add_scalar("leaf")
		db:set_hash_element(b, "leaf", l)
		return a, b, l
	end)

	db:delete_hash_element(1, "branch")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from hsa where hsa_pk in (" .. h2 .. "," .. h3 .. "," .. leaf .. ")"
	) do
		n = row.c
	end
	h.assert_eq(n, 0, "subtree fully collected")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Cycles
-- ------------------------------------------------------------

h.test("purge: fully detached cycle is deleted", function()
	-- root -> h2, h2 <-> h3. Cut root -> h2 → cycle detaches, both die.
	-- This is Drinian's two-hash example.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3 = db:atomic(function()
		local a = db:add_hash()
		local b = db:add_hash()
		db:set_hash_element(1, "entry", a)
		db:set_hash_element(a, "forward", b)
		db:set_hash_element(b, "back", a)
		return a, b
	end)

	db:delete_hash_element(1, "entry")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from hsa where hsa_pk in (" .. h2 .. "," .. h3 .. ")"
	) do
		n = row.c
	end
	h.assert_eq(n, 0, "both cycle members collected in one pass")
	assert_flags_clean(db)
end)

h.test("purge: cycle still connected to root stays intact", function()
	-- root -> h2, root -> h3, h2 <-> h3. Cut root -> h2. h2 still
	-- reachable via root -> h3 -> h2, so both stay.
	local db = fiona.get_db(":memory:", "rw")

	local h2, h3 = db:atomic(function()
		local a = db:add_hash()
		local b = db:add_hash()
		db:set_hash_element(1, "a", a)
		db:set_hash_element(1, "b", b)
		db:set_hash_element(a, "forward", b)
		db:set_hash_element(b, "back", a)
		return a, b
	end)

	db:delete_hash_element(1, "a")

	local n
	for row in db._conn:nrows(
		"select count(*) as c from hsa where hsa_pk in (" .. h2 .. "," .. h3 .. ")"
	) do
		n = row.c
	end
	h.assert_eq(n, 2, "both cycle members still reachable via the surviving root edge")
	assert_flags_clean(db)
end)

-- ------------------------------------------------------------
-- Child-swap (update path)
-- ------------------------------------------------------------

h.test("purge: update-of-child collects the swapped-out old child if unreachable", function()
	local db = fiona.get_db(":memory:", "rw")

	local old_child = db:add_scalar("old")
	db:set_hash_element(1, "x", old_child)

	local new_child = db:add_scalar("new")
	db:set_hash_element(1, "x", new_child)

	local n
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. old_child) do
		n = row.c
	end
	h.assert_eq(n, 0, "old child collected after swap")

	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. new_child) do
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

	local child = db:add_scalar("x")
	db:set_hash_element(1, "x", child)
	db:delete_hash_element(1, "x")

	local n
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = 1") do
		n = row.c
	end
	h.assert_eq(n, 1, "root survives")

	for row in db._conn:nrows("select needs_trace, in_trace from hsa where hsa_pk = 1") do
		h.assert_true(row.needs_trace == nil, "root never marked needs_trace")
		h.assert_true(row.in_trace == nil, "root never marked in_trace")
	end
end)

-- ------------------------------------------------------------
-- Deep chain — the whole point of moving GC out of triggers
-- ------------------------------------------------------------

h.test("purge: 2000-deep linear chain unwinds without a depth cap", function()
	-- Under the previous cascade-based purge trigger, this would abort
	-- at SQLITE_LIMIT_TRIGGER_DEPTH (1000). The Lua drain iterates in
	-- Lua, so depth is bounded by heap not by trigger recursion.
	local depth = 2000
	local db = fiona.get_db(":memory:", "rw")

	local top = db:atomic(function()
		local parent = 1
		local top_pk

		for i = 1, depth do
			local h_pk = db:add_hash()

			if i == 1 then
				db:set_hash_element(1, "top", h_pk)
				top_pk = h_pk
			else
				db:set_hash_element(parent, "next", h_pk)
			end

			parent = h_pk
		end

		return top_pk
	end)

	-- Sanity: chain is populated. depth hashes + root = depth + 1 rows.
	local pre_count
	for row in db._conn:nrows("select count(*) as c from hsa") do
		pre_count = row.c
	end
	h.assert_eq(pre_count, depth + 1, "chain built at expected size")

	-- Cut the top edge — everything downstream is unreachable.
	db:delete_hash_element(1, "top")

	local post_count
	for row in db._conn:nrows("select count(*) as c from hsa") do
		post_count = row.c
	end
	h.assert_eq(post_count, 1, "only root survives after chain teardown")
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

	local scalar = db:add_scalar("value")
	db:set_hash_element(1, "k", scalar)

	db:atomic(function()
		db:delete_hash_element(1, "k")
		db:set_hash_element(1, "k2", scalar)  -- re-anchor at a different key
	end)

	local n
	for row in db._conn:nrows("select count(*) as c from hsa where hsa_pk = " .. scalar) do
		n = row.c
	end
	h.assert_eq(n, 1, "scalar survives — was re-anchored before drain")
	assert_flags_clean(db)
end)
