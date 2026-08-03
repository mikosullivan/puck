-- Query-plan tests. Asserts the important read/write patterns actually
-- use indexes (no full table scans) and, where relevant, that ORDER BY
-- gets a free ride from the index (no separate sort step).
--
-- These tests don't check specific auto-index names
-- (`sqlite_autoindex_relationships_2` would shift if we added another
-- UNIQUE constraint). They check structural properties instead: no
-- SCAN, no TEMP B-TREE FOR ORDER BY.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

-- ------------------------------------------------------------
-- Array element access
-- ------------------------------------------------------------

h.test("array element at specific idx uses (parent, idx) index", function()
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select child from relationships where parent = 1 and idx = 5",
		"array element by idx")
end)

h.test("array ordered iteration uses index and needs no sort", function()
	local db = h.fresh_db()
	local sql = "select child from relationships where parent = 1 order by idx"
	h.assert_uses_index(db, sql, "array ordered iteration — index")
	h.assert_ordered_via_index(db, sql, "array ordered iteration — no sort")
end)

h.test("array range scan uses (parent, idx) index", function()
	-- The shift triggers do this shape a lot.
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select rel_pk from relationships where parent = 1 and idx >= 5",
		"array idx range scan")
end)

h.test("array between-range scan uses (parent, idx) index", function()
	-- The UPDATE-shift trigger uses `idx between X and Y`.
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select rel_pk from relationships where parent = 1 and idx between 3 and 7",
		"array idx between-range scan")
end)

-- ------------------------------------------------------------
-- Hash element access
-- ------------------------------------------------------------

h.test("hash element by key uses (parent, key) index", function()
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select child from relationships where parent = 1 and key = 'foo'",
		"hash element by key")
end)

h.test("hash ordered iteration (insertion order) uses index and needs no sort", function()
	-- Ruby/Caspian ordered-hash semantics: iterate by idx, which is
	-- insertion order.
	local db = h.fresh_db()
	local sql = "select key, child from relationships where parent = 1 order by idx"
	h.assert_uses_index(db, sql, "hash insertion-order iteration — index")
	h.assert_ordered_via_index(db, sql, "hash insertion-order iteration — no sort")
end)

-- ------------------------------------------------------------
-- Parent / child lookups
-- ------------------------------------------------------------

h.test("all children of a parent uses (parent, *) index", function()
	-- Bare parent lookup. Prefix of both (parent, key) and (parent, idx)
	-- composite indexes; either serves it.
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select child from relationships where parent = 1",
		"all children of parent")
end)

h.test("all parents of a child uses the partial relationships_child index", function()
	-- The multi-parent case (Fiona is a graph, not a tree). Also the
	-- inbound-edge lookup used by the drain's upward reachability walk.
	-- relationships_child is partial (where child is not null) — scalar
	-- rows have child = null and are not indexed, but this query filters
	-- to child = 42 which is not null, so the partial index applies.
	local db = h.fresh_db()
	local sql = "select parent from relationships where child = 42"
	h.assert_uses_index(db, sql, "all parents of child")

	local plan = h.plan(db, sql)
	local seen = false

	for _, detail in ipairs(plan) do
		if detail:find("relationships_child") then
			seen = true
		end
	end

	h.assert_true(seen, "plan mentions relationships_child")
end)

-- ------------------------------------------------------------
-- Drain's upward reachability CTE
-- ------------------------------------------------------------

h.test("drain upward-reachability walk uses index for child joins", function()
	-- The recursive CTE joins relationships r on r.child = upward.pk.
	-- Should hit the partial (child) index.
	local db = h.fresh_db()
	h.assert_uses_index(db, [[
		with recursive upward(pk) as (
			select collection_pk from collections where in_trace = 1
			union
			select r.parent from relationships r
			join upward on r.child = upward.pk
		)
		select pk from upward
	]], "drain upward-reachability walk")
end)

-- ------------------------------------------------------------
-- Partial indexes for the trace flags — cheap seed and closure lookup
-- ------------------------------------------------------------

h.test("collections_needs_trace partial index used to find seeds", function()
	-- The drain does `select collection_pk from collections where
	-- needs_trace = 1 limit 1`. The partial index keeps this near-zero
	-- when the resting state (most rows) has needs_trace null.
	local db = h.fresh_db()
	local sql = "select collection_pk from collections where needs_trace = 1"
	h.assert_uses_index(db, sql, "needs_trace seed lookup")

	local plan = h.plan(db, sql)
	local seen = false

	for _, detail in ipairs(plan) do
		if detail:find("collections_needs_trace") then
			seen = true
		end
	end

	h.assert_true(seen, "plan mentions collections_needs_trace")
end)

h.test("collections_in_trace partial index used to sweep the closure", function()
	-- Drain does `delete from collections where in_trace = 1` in the
	-- dead branch, and clears the flag with `update collections set
	-- in_trace = null where in_trace = 1` in the alive branch.
	local db = h.fresh_db()
	local sql = "select collection_pk from collections where in_trace = 1"
	h.assert_uses_index(db, sql, "in_trace closure lookup")

	local plan = h.plan(db, sql)
	local seen = false

	for _, detail in ipairs(plan) do
		if detail:find("collections_in_trace") then
			seen = true
		end
	end

	h.assert_true(seen, "plan mentions collections_in_trace")
end)

-- ------------------------------------------------------------
-- collections primary-key access
-- ------------------------------------------------------------

h.test("collections lookup by collection_pk uses primary key", function()
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select type from collections where collection_pk = 1",
		"collections by primary key")
end)
