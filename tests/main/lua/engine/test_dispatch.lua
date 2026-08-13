--[[
{
	"spec": "test_dispatch",
	"role": "Tests for the row-head dispatch mechanism at src/engine/dispatch.lua (chain-of-responsibility over an array of Handler instances). Three test-support Handler subclasses (AlwaysTrue / AlwaysFalse / AlwaysRaise) defined inline at the top of the file — they exist only to exercise the chain semantics without any real matching logic. Two groups of tests: unit tests for the three subclasses (each does what its name says), and dispatch chain tests (empty array, single-true, single-false, fall-through, raise-propagation, first-wins).",
	"status": "walking-skeleton"
}
]]

--[[
# `test_dispatch`

Tests for `dispatch` (the row-head dispatch function) and the three test-support `Handler` subclasses defined inline in this file (AlwaysTrue / AlwaysFalse / AlwaysRaise).

Two groups:

**Utility-handler unit tests** — direct assertions on each subclass. Each verifies the subclass does what its name says, independent of dispatch. These come first because the dispatch tests use these handlers as tools; the tools have to work before the tool-users are trustworthy.

**Dispatch chain tests** — empty handlers array raises; AlwaysTrue alone returns cleanly; AlwaysFalse alone raises (all-declined fallback); AlwaysFalse-then-AlwaysTrue returns cleanly (fall-through); AlwaysRaise alone propagates its raise; AlwaysTrue-then-AlwaysRaise returns cleanly (first-wins, AlwaysRaise never fires).
]]

local h        = require('helpers')
local Handler  = require('handler')
local dispatch = require('dispatch')

-- ------------------------------------------------------------
-- Test-support Handler subclasses — local to this test file.
-- Kept here rather than in shipping handler.lua so production
-- code doesn't ship test scaffolding.
-- ------------------------------------------------------------

local AlwaysTrue = setmetatable({}, {__index = Handler})
AlwaysTrue.__index = AlwaysTrue

function AlwaysTrue.new()
	return setmetatable(Handler.new(), AlwaysTrue)
end

function AlwaysTrue:handle(engine, row)
	return true
end

local AlwaysFalse = setmetatable({}, {__index = Handler})
AlwaysFalse.__index = AlwaysFalse

function AlwaysFalse.new()
	return setmetatable(Handler.new(), AlwaysFalse)
end

function AlwaysFalse:handle(engine, row)
	return false
end

local AlwaysRaise = setmetatable({}, {__index = Handler})
AlwaysRaise.__index = AlwaysRaise

function AlwaysRaise.new()
	return setmetatable(Handler.new(), AlwaysRaise)
end

function AlwaysRaise:handle(engine, row)
	error("always_raise_fired: AlwaysRaise handler is configured to always raise")
end

-- ------------------------------------------------------------
-- Local helper: assert a call raises with a message containing
-- an expected substring. Not in shared helpers yet.
-- ------------------------------------------------------------

local function assert_raises_matching(fn, pattern, msg)
	local ok, err = pcall(fn)

	if ok then
		error((msg or "expected raise") .. " — but call succeeded", 2)
	end

	if not string.find(tostring(err), pattern, 1, true) then
		error((msg or "expected raise") .. " — raise text didn't contain expected substring\n  substring: " .. pattern .. "\n  got:       " .. tostring(err), 2)
	end
end

-- ==============================================================
-- Utility handler unit tests
-- ==============================================================

h.test("AlwaysTrue:handle returns true", function()
	local handler = AlwaysTrue.new()
	h.assert_eq(handler:handle(), true, "AlwaysTrue:handle should return true")
end)

h.test("AlwaysFalse:handle returns false", function()
	local handler = AlwaysFalse.new()
	h.assert_eq(handler:handle(), false, "AlwaysFalse:handle should return false")
end)

h.test("AlwaysRaise:handle raises with 'always_raise_fired' id", function()
	local handler = AlwaysRaise.new()
	assert_raises_matching(
		function() handler:handle() end,
		"always_raise_fired",
		"AlwaysRaise:handle should raise with the always_raise_fired id"
	)
end)

-- ==============================================================
-- Dispatch chain tests
-- ==============================================================

h.test("dispatch: empty handlers array raises unrecognized_row_head", function()
	assert_raises_matching(
		function() dispatch({}) end,
		"unrecognized_row_head",
		"empty handlers array should raise unrecognized_row_head"
	)
end)

h.test("dispatch: AlwaysTrue alone returns cleanly", function()
	dispatch({ AlwaysTrue.new() })
end)

h.test("dispatch: AlwaysFalse alone raises unrecognized_row_head (all-declined fallback)", function()
	assert_raises_matching(
		function() dispatch({ AlwaysFalse.new() }) end,
		"unrecognized_row_head",
		"AlwaysFalse alone should trigger the all-declined fallback raise"
	)
end)

h.test("dispatch: AlwaysFalse then AlwaysTrue returns cleanly (fall-through)", function()
	dispatch({
		AlwaysFalse.new(),
		AlwaysTrue.new(),
	})
end)

h.test("dispatch: AlwaysRaise alone: raise propagates", function()
	assert_raises_matching(
		function() dispatch({ AlwaysRaise.new() }) end,
		"always_raise_fired",
		"AlwaysRaise's error message should reach the caller through dispatch"
	)
end)

h.test("dispatch: AlwaysTrue then AlwaysRaise returns cleanly (first-wins)", function()
	-- If first-wins was broken, AlwaysRaise would fire; assert_raises_matching
	-- would then not raise this test's expected error, but the dispatch
	-- call itself would raise `always_raise_fired`.
	dispatch({
		AlwaysTrue.new(),
		AlwaysRaise.new(),
	})
end)
