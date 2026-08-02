-- Query-plan tests. Asserts the important read/write patterns actually
-- use indexes (no full table scans) and, where relevant, that ORDER BY
-- gets a free ride from the index (no separate sort step).
--
-- These tests don't check specific auto-index names (`sqlite_autoindex_relationships_2`
-- would shift if we added another UNIQUE constraint). They check structural
-- properties instead: no SCAN, no TEMP B-TREE FOR ORDER BY.

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

h.test("all parents of a child uses relationships_child index", function()
	-- The multi-parent case (Fiona is a graph, not a tree). Also the
	-- inbound-edge lookup used by the purge trigger's reachability walk.
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select parent from relationships where child = 42",
		"all parents of child")
end)

-- ------------------------------------------------------------
-- Purge trigger's reachability CTE
-- ------------------------------------------------------------

h.test("purge reachability walk uses index for parent joins", function()
	-- The recursive CTE joins relationships r on r.parent = reachable.hsa_pk.
	-- The outbound edge from each reachable node is a parent-side lookup,
	-- which should hit a (parent, *) composite index.
	local db = h.fresh_db()
	h.assert_uses_index(db, [[
		with recursive reachable(hsa_pk) as (
			select 1
			union
			select r.child from relationships r
			join reachable on r.parent = reachable.hsa_pk
		)
		select hsa_pk from reachable
	]], "purge reachability walk")
end)

-- ------------------------------------------------------------
-- hsa primary-key access
-- ------------------------------------------------------------

h.test("hsa lookup by hsa_pk uses primary key", function()
	local db = h.fresh_db()
	h.assert_uses_index(db,
		"select type, st, value from hsa where hsa_pk = 1",
		"hsa by primary key")
end)
