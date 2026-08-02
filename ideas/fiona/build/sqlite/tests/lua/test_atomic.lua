-- Tests for Db:atomic(fn) — the caller-facing wrapper that bundles a
-- sequence of Fiona API calls into one SAVEPOINT so they commit
-- together (no partial write, no orphan collections row observable
-- between calls) or roll back together on error. The outermost atomic()
-- boundary also runs Db:_drain_needs_trace before release.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- Commit path
-- ------------------------------------------------------------

h.test("atomic commits when fn returns normally", function()
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()
	db:set_hash_ref(1, "p", parent)

	db:atomic(function()
		db:set_hash_scalar(parent, "k", "hello")
	end)

	local st, scalar
	for row in db._conn:nrows("select st, scalar from relationships where parent = " .. parent .. " and key = 'k'") do
		st = row.st
		scalar = row.scalar
	end

	h.assert_eq(st, "s", "st landed")
	h.assert_eq(scalar, "hello", "scalar value landed")
end)

h.test("atomic returns fn's value", function()
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()
	db:set_hash_ref(1, "p", parent)

	local returned = db:atomic(function()
		local pk = db:add_hash()
		db:set_hash_ref(parent, "k", pk)
		return pk
	end)

	h.assert_true(type(returned) == "number", "atomic returned the collection_pk")
end)

-- ------------------------------------------------------------
-- Rollback path — the core orphan-avoidance guarantee
-- ------------------------------------------------------------

h.test("atomic rolls back both operations when fn errors between them", function()
	-- add_hash creates a collections row; if the next call errors, the
	-- savepoint rolls the whole thing back and no orphan collection
	-- survives.
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()
	db:set_hash_ref(1, "p", parent)

	local before
	for row in db._conn:nrows("select count(*) as c from collections") do
		before = row.c
	end

	h.assert_raises(function()
		db:atomic(function()
			db:add_hash()  -- would-be orphan
			error("simulated failure between add and associate")
		end)
	end, "simulated failure", "error propagated")

	local after
	for row in db._conn:nrows("select count(*) as c from collections") do
		after = row.c
	end

	h.assert_eq(after, before, "no orphan collection row survived rollback")
end)

h.test("atomic rolls back when a Fiona call itself raises", function()
	-- Trigger a real Fiona-level error mid-atomic: set_hash_ref on a
	-- non-existent parent. The prior add_hash in the same atomic() should
	-- also roll back.
	local db = fiona.get_db(":memory:", "rw")

	local before
	for row in db._conn:nrows("select count(*) as c from collections") do
		before = row.c
	end

	h.assert_raises(function()
		db:atomic(function()
			db:add_hash()  -- bogus
			db:set_hash_ref(9999, "k", 1)  -- parent 9999 doesn't exist
		end)
	end, nil, "some Fiona error propagated")

	local after
	for row in db._conn:nrows("select count(*) as c from collections") do
		after = row.c
	end

	h.assert_eq(after, before, "add_hash rolled back with the failing set_hash_ref")
end)

-- ------------------------------------------------------------
-- Nesting
-- ------------------------------------------------------------

h.test("atomic nests — inner atomic rolls back without affecting outer", function()
	-- Outer atomic() opens SAVEPOINT sp. Inner atomic() opens another
	-- SAVEPOINT sp. Inner rollback should restore state to the inner's
	-- start point, leaving outer's earlier work intact.
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()
	db:set_hash_ref(1, "p", parent)

	db:atomic(function()
		db:set_hash_scalar(parent, "outer_key", "outer")

		local ok = pcall(function()
			db:atomic(function()
				db:set_hash_scalar(parent, "inner_key", "inner")
				error("inner explodes")
			end)
		end)

		h.assert_true(not ok, "inner atomic raised")
	end)

	-- Outer committed. outer_key should be present; inner_key should not.
	local outer_hits, inner_hits = 0, 0

	for row in db._conn:nrows("select key from relationships where parent = " .. parent) do
		if row.key == "outer_key" then
			outer_hits = outer_hits + 1
		elseif row.key == "inner_key" then
			inner_hits = inner_hits + 1
		end
	end

	h.assert_eq(outer_hits, 1, "outer scalar row persisted")
	h.assert_eq(inner_hits, 0, "inner scalar row rolled back")
end)
