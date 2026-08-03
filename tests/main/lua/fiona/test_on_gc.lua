-- Tests for db:on_gc / db:gc_errors and the collection handle passed
-- to the callback. Covers: callback fires on GC, callbacks fire in
-- ascending in_trace order (parent-first), the auto-mark trigger keeps
-- callback-created collections in-trace so they die with the drain,
-- callback errors go to gc_errors and don't break the drain, no
-- callback path falls through to bulk delete cleanly.

local h = require("helpers")
local fiona = require("fiona")

-- ------------------------------------------------------------
-- Registration
-- ------------------------------------------------------------

h.test("on_gc accepts a function", function()
	local db = fiona.get_db(":memory:", "rw")
	db:on_gc(function() end)
end)

h.test("on_gc(nil) clears the callback", function()
	local db = fiona.get_db(":memory:", "rw")
	db:on_gc(function() end)
	db:on_gc(nil)
	-- No callback → no fire path; a delete should still succeed.
	local pk = db:add_hash()
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")
end)

h.test("on_gc rejects non-function, non-nil arguments", function()
	local db = fiona.get_db(":memory:", "rw")
	h.assert_raises(function() db:on_gc("not a function") end,
		"must be a function", "string rejected")
end)

-- ------------------------------------------------------------
-- Basic callback fires
-- ------------------------------------------------------------

h.test("callback fires for a simple GC", function()
	local db = fiona.get_db(":memory:", "rw")
	local seen = {}
	db:on_gc(function(handle) table.insert(seen, handle.pk) end)

	local pk = db:add_hash()
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")

	h.assert_eq(#seen, 1, "callback fired once")
	h.assert_eq(seen[1], pk, "fired for the deleted collection")
end)

h.test("callback receives the handle's pk and type", function()
	local db = fiona.get_db(":memory:", "rw")
	local seen_type, seen_pk
	db:on_gc(function(handle) seen_type = handle.type; seen_pk = handle.pk end)

	local pk = db:add_array()
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")

	h.assert_eq(seen_type, "a", "type is 'a' for array")
	h.assert_eq(seen_pk, pk, "pk matches")
end)

h.test("handle is_hash and is_array", function()
	local db = fiona.get_db(":memory:", "rw")
	local h_type, a_type
	db:on_gc(function(handle)
		if handle:is_hash() then h_type = handle.pk end
		if handle:is_array() then a_type = handle.pk end
	end)

	local hash_pk = db:add_hash()
	local arr_pk = db:add_array()
	db:set_hash_ref(1, "h", hash_pk)
	db:set_hash_ref(1, "a", arr_pk)
	db:delete_hash_element(1, "h")
	db:delete_hash_element(1, "a")

	h.assert_eq(h_type, hash_pk, "hash reported is_hash")
	h.assert_eq(a_type, arr_pk, "array reported is_array")
end)

h.test("handle reads its own scalars via metatable", function()
	local db = fiona.get_db(":memory:", "rw")
	local read
	db:on_gc(function(handle) read = handle.name end)

	local pk = db:add_hash()
	db:set_hash_scalar(pk, "name", "victim")
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")

	h.assert_eq(read, "victim", "handle.name reads the scalar")
end)

-- ------------------------------------------------------------
-- Ordering — parent-first via in_trace numbering
-- ------------------------------------------------------------

h.test("cycle: seed fires first, back-reference second", function()
	-- Build a cycle:
	--   root.session → session
	--   session.logger → logger
	--   logger.session_back → session  (back-reference)
	-- Cut root.session: session is the seed. Trace picks up logger via
	-- logger→session. Callback order: session, logger.
	local db = fiona.get_db(":memory:", "rw")
	local order = {}
	db:on_gc(function(handle) table.insert(order, handle.pk) end)

	local session = db:add_hash()
	local logger = db:add_hash()

	db:set_hash_ref(1, "session", session)
	db:set_hash_ref(session, "logger", logger)
	db:set_hash_ref(logger, "session_back", session)

	db:delete_hash_element(1, "session")

	h.assert_eq(#order, 2, "both fired")
	h.assert_eq(order[1], session, "seed fires first")
	h.assert_eq(order[2], logger, "back-reffer fires second")
end)

h.test("linear chain: parent fires before child (via cascade + repeated seeds)", function()
	local db = fiona.get_db(":memory:", "rw")
	local order = {}
	db:on_gc(function(handle) table.insert(order, handle.pk) end)

	local a = db:add_hash()
	local b = db:add_hash()
	local c = db:add_hash()

	db:set_hash_ref(1, "a", a)
	db:set_hash_ref(a, "b", b)
	db:set_hash_ref(b, "c", c)

	db:delete_hash_element(1, "a")

	h.assert_eq(#order, 3, "all three fired")
	h.assert_eq(order[1], a, "a fires first (seed)")
	h.assert_eq(order[2], b, "b fires next (cascade)")
	h.assert_eq(order[3], c, "c fires last")
end)

-- ------------------------------------------------------------
-- Auto-mark: callback-created collections die with the drain
-- ------------------------------------------------------------

h.test("callback creating a new hash — the new hash dies too", function()
	local db = fiona.get_db(":memory:", "rw")
	local created_pk
	db:on_gc(function(handle)
		if handle.pk ~= created_pk then
			created_pk = db:add_hash()
		end
	end)

	local victim = db:add_hash()
	db:set_hash_ref(1, "child", victim)
	db:delete_hash_element(1, "child")

	-- The new collection was auto-marked in_trace, so the drain also
	-- deleted it. It shouldn't exist in collections.
	local count
	for row in db._conn:nrows("select count(*) as c from collections where collection_pk = " .. created_pk) do
		count = row.c
	end
	h.assert_eq(count, 0, "auto-marked collection was collected")
end)

h.test("callback creating a new hash — the new hash gets its own callback", function()
	local db = fiona.get_db(":memory:", "rw")
	local seen = {}
	local created_once = false
	db:on_gc(function(handle)
		table.insert(seen, handle.pk)
		if not created_once then
			created_once = true
			db:add_hash()  -- auto-marked, fires its own callback in the same drain
		end
	end)

	local victim = db:add_hash()
	db:set_hash_ref(1, "child", victim)
	db:delete_hash_element(1, "child")

	h.assert_eq(#seen, 2, "original + auto-marked both fired")
end)

-- ------------------------------------------------------------
-- gc_errors
-- ------------------------------------------------------------

h.test("callback error goes to gc_errors and doesn't break the drain", function()
	local db = fiona.get_db(":memory:", "rw")
	local seen = {}
	db:on_gc(function(handle)
		table.insert(seen, handle.pk)
		if #seen == 1 then error("callback boom") end
	end)

	local a, b
	db:atomic(function()
		a = db:add_hash()
		b = db:add_hash()
		db:set_hash_ref(1, "a", a)
		db:set_hash_ref(1, "b", b)
	end)

	-- Bundle both deletes in one atomic so one drain sees both — the
	-- first callback raises, the second one fires anyway.
	db:atomic(function()
		db:delete_hash_element(1, "a")
		db:delete_hash_element(1, "b")
	end)

	local errors = db:gc_errors()
	h.assert_eq(#errors, 1, "one error recorded")
	h.assert_true(errors[1].message:find("callback boom"), "error message preserved")
	h.assert_eq(errors[1].collection_pk, a, "error tagged with the failing collection_pk")
	h.assert_eq(#seen, 2, "second callback still fired")
end)

h.test("gc_errors is cleared at the start of each drain", function()
	local db = fiona.get_db(":memory:", "rw")
	db:on_gc(function() error("boom") end)

	local a = db:add_hash()
	db:set_hash_ref(1, "a", a)
	db:delete_hash_element(1, "a")
	h.assert_eq(#db:gc_errors(), 1, "first drain accumulated one error")

	local b = db:add_hash()
	db:set_hash_ref(1, "b", b)
	db:delete_hash_element(1, "b")
	h.assert_eq(#db:gc_errors(), 1, "second drain cleared and re-accumulated")
end)

-- ------------------------------------------------------------
-- No-callback path: bulk delete still works
-- ------------------------------------------------------------

h.test("no callback registered: GC still runs (bulk-delete path)", function()
	local db = fiona.get_db(":memory:", "rw")
	local pk = db:add_hash()
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")

	local count
	for row in db._conn:nrows("select count(*) as c from collections") do
		count = row.c
	end
	h.assert_eq(count, 1, "only root remains")
end)

-- ------------------------------------------------------------
-- Process rows are cleaned up
-- ------------------------------------------------------------

h.test("process rows are absent after a successful drain", function()
	local db = fiona.get_db(":memory:", "rw")
	db:on_gc(function() end)

	local pk = db:add_hash()
	db:set_hash_ref(1, "child", pk)
	db:delete_hash_element(1, "child")

	local count
	for row in db._conn:nrows("select count(*) as c from process") do
		count = row.c
	end
	h.assert_eq(count, 0, "no process rows survive drain exit")
end)

-- ------------------------------------------------------------
-- Alive branch: no callback fires
-- ------------------------------------------------------------

h.test("alive branch does not fire callbacks", function()
	local db = fiona.get_db(":memory:", "rw")
	local seen = {}
	db:on_gc(function(handle) table.insert(seen, handle.pk) end)

	-- Two anchors to the same hash. Cut one; still anchored via the
	-- other. Nothing should be GC'd.
	local pk = db:add_hash()
	db:set_hash_ref(1, "a", pk)
	db:set_hash_ref(1, "b", pk)
	db:delete_hash_element(1, "a")

	h.assert_eq(#seen, 0, "callback did not fire")
end)
