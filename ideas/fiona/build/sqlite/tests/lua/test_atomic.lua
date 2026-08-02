-- Tests for Db:atomic(fn) — the caller-facing wrapper that bundles a
-- sequence of Fiona API calls into one SAVEPOINT so they commit
-- together (no partial write, no orphan hsa row observable between
-- calls) or roll back together on error.

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

	db:atomic(function()
		local pk = db:add_scalar("hello")
		db:set_hash_element(parent, "k", pk)
	end)

	local child
	for row in db._conn:nrows("select child from relationships where parent = " .. parent .. " and key = 'k'") do
		child = row.child
	end

	h.assert_true(child ~= nil, "edge landed")

	local value
	for row in db._conn:nrows("select value from hsa where hsa_pk = " .. child) do
		value = row.value
	end

	h.assert_eq(value, "hello", "scalar value landed")
end)

h.test("atomic returns fn's value", function()
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()

	local returned = db:atomic(function()
		local pk = db:add_scalar(42)
		db:set_hash_element(parent, "k", pk)
		return pk
	end)

	h.assert_true(type(returned) == "number", "atomic returned the scalar's pk")
end)

-- ------------------------------------------------------------
-- Rollback path — the core orphan-avoidance guarantee
-- ------------------------------------------------------------

h.test("atomic rolls back both operations when fn errors between them", function()
	-- Simulate a crash between add_scalar and set_hash_element. Without
	-- atomic() the scalar would persist as an orphan. With atomic() the
	-- savepoint rolls back and nothing lands.
	local db = fiona.get_db(":memory:", "rw")
	local parent = db:add_hash()

	local hsa_before
	for row in db._conn:nrows("select count(*) as c from hsa") do
		hsa_before = row.c
	end

	h.assert_raises(function()
		db:atomic(function()
			db:add_scalar("would-be orphan")
			error("simulated failure between add and associate")
		end)
	end, "simulated failure", "error propagated")

	local hsa_after
	for row in db._conn:nrows("select count(*) as c from hsa") do
		hsa_after = row.c
	end

	h.assert_eq(hsa_after, hsa_before, "no orphan hsa row survived rollback")

	local rel_count
	for row in db._conn:nrows("select count(*) as c from relationships where parent = " .. parent) do
		rel_count = row.c
	end

	h.assert_eq(rel_count, 0, "no partial edge from parent")
end)

h.test("atomic rolls back when a Fiona call itself raises", function()
	-- Trigger a real Fiona-level error mid-atomic: try to set_hash_element
	-- on a non-existent parent. The prior add_scalar in the same atomic()
	-- should also roll back.
	local db = fiona.get_db(":memory:", "rw")

	local hsa_before
	for row in db._conn:nrows("select count(*) as c from hsa") do
		hsa_before = row.c
	end

	h.assert_raises(function()
		db:atomic(function()
			db:add_scalar("bogus")
			db:set_hash_element(9999, "k", 1)  -- parent 9999 doesn't exist
		end)
	end, nil, "some Fiona error propagated")

	local hsa_after
	for row in db._conn:nrows("select count(*) as c from hsa") do
		hsa_after = row.c
	end

	h.assert_eq(hsa_after, hsa_before, "scalar rolled back with the failing set_hash_element")
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

	db:atomic(function()
		local pk_outer = db:add_scalar("outer")
		db:set_hash_element(parent, "outer_key", pk_outer)

		local ok = pcall(function()
			db:atomic(function()
				db:add_scalar("inner")
				error("inner explodes")
			end)
		end)

		h.assert_true(not ok, "inner atomic raised")
	end)

	-- The outer atomic committed. The scalar "outer" should be present;
	-- the scalar "inner" from the inner-rolled-back atomic should not.
	local outer_hits, inner_hits = 0, 0
	for row in db._conn:nrows("select value from hsa where value in ('outer', 'inner')") do
		if row.value == "outer" then
			outer_hits = outer_hits + 1
		elseif row.value == "inner" then
			inner_hits = inner_hits + 1
		end
	end

	h.assert_eq(outer_hits, 1, "outer scalar persisted")
	h.assert_eq(inner_hits, 0, "inner scalar rolled back")
end)
