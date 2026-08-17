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

Three groups:

**Utility-handler unit tests** — direct assertions on each subclass. Each verifies the subclass does what its name says, independent of dispatch. These come first because the dispatch tests use these handlers as tools; the tools have to work before the tool-users are trustworthy.

**Dispatch chain tests** — empty handlers array raises; AlwaysTrue alone returns cleanly; AlwaysFalse alone raises (all-declined fallback); AlwaysFalse-then-AlwaysTrue returns cleanly (fall-through); AlwaysRaise alone propagates its raise; AlwaysTrue-then-AlwaysRaise returns cleanly (first-wins, AlwaysRaise never fires).

**Engine integration tests** — verify the shipping engine actually uses dispatch correctly. Constructs a real engine, registers handlers into `engine.row_handlers`, calls `engine:run_row`, asserts on the outcome. Also verifies `M:run_row`'s pcall-wrap logic: dispatch's `unrecognized_caspm` raise gets re-shaped with the row-head atom's key set appended; a handler's own raise propagates unchanged.
]]

local h        = require('helpers')
local Handler  = require('handler')
local dispatch = require('dispatch')
local engine   = require('engine')

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

-- Walks an instance's metatable chain looking for the Handler base
-- class. Returns true if the instance is a Handler or any subclass;
-- false otherwise. Handles arbitrary subclass depth via metatables'
-- __index chain.
local function is_handler_instance(instance)
	local cls = getmetatable(instance)

	while cls do
		if cls == Handler then return true end

		local mt = getmetatable(cls)

		if mt and type(mt) == 'table' and mt.__index and type(mt.__index) == 'table' then
			cls = mt.__index
		else
			return false
		end
	end

	return false
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

h.test("dispatch: empty handlers array raises unrecognized_caspm", function()
	assert_raises_matching(
		function() dispatch({}) end,
		"unrecognized_caspm",
		"empty handlers array should raise unrecognized_caspm"
	)
end)

h.test("dispatch: AlwaysTrue alone returns cleanly", function()
	dispatch({ AlwaysTrue.new() })
end)

h.test("dispatch: AlwaysFalse alone raises unrecognized_caspm (all-declined fallback)", function()
	assert_raises_matching(
		function() dispatch({ AlwaysFalse.new() }) end,
		"unrecognized_caspm",
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

-- ==============================================================
-- Engine integration tests — verify the shipping engine actually
-- uses dispatch correctly, and M:run_row's pcall-wrap does the
-- expected atom-keys re-raise while passing handler raises through.
-- ==============================================================

h.test("engine:run_row returns cleanly when a handler in row_handlers claims the row", function()
	local e = engine.new()
	e:add_handler(AlwaysTrue.new())
	-- AlwaysTrue ignores the row content; any row works.
	e:run_row({{bwc = 'anything'}})
end)

h.test("engine:run_row raises unrecognized_caspm when row_handlers is empty", function()
	local e = engine.new()
	-- Clear the stock chain to test the empty-chain fallback specifically.
	e:clear_handlers()
	assert_raises_matching(
		function() e:run_row({{['in'] = 'as'}}) end,
		'unrecognized_caspm',
		"empty row_handlers should raise unrecognized_caspm"
	)
end)

h.test("engine:run_row's unrecognized_caspm raise includes the row-head atom-keys", function()
	local e = engine.new()
	-- Clear the stock chain so the empty-chain fallback fires and its
	-- reshape logic surfaces the row-head atom-keys.
	e:clear_handlers()
	assert_raises_matching(
		function() e:run_row({{['in'] = 'as'}}) end,
		'in',
		"raise should surface the row-head atom-keys detail"
	)
end)

h.test("engine:run_row propagates a handler's raise unchanged (no atom-keys re-wrap)", function()
	local e = engine.new()
	-- Replace the stock chain with just AlwaysRaise so it's the first
	-- (and only) handler consulted; if we appended, VariableScalar's
	-- always-true stub would claim first and AlwaysRaise would never fire.
	e:clear_handlers():add_handler(AlwaysRaise.new())
	-- AlwaysRaise's message contains "always_raise_fired". If M:run_row
	-- accidentally caught it and re-shaped it as unrecognized_caspm,
	-- the substring below wouldn't match.
	assert_raises_matching(
		function() e:run_row({{bwc = 'anything'}}) end,
		'always_raise_fired',
		"handler's own raise should propagate as-is through run_row"
	)
end)

-- ==============================================================
-- Stock handler roster — verify a fresh engine's row_handlers
-- contains EXACTLY the classes listed below, one instance of each.
-- Fails if any expected class is missing, if any unexpected class
-- is present, or if any expected class appears more than once.
--
-- Add new entries to `expected_classes` below when a new stock
-- handler gets registered. Test failure catches the case where
-- someone adds a handler to stock_instances() but forgets to
-- update this test — or vice versa.
-- ==============================================================

h.test("engine.new()'s row_handlers is exactly the stock roster, one of each", function()
	local handlers = require('handlers')

	local expected_classes = {
		VariableScalar = handlers.VariableScalar,
		-- add more here as new handler classes get registered:
		--   NextHandler = handlers.NextHandler,
	}

	local e = engine.new()

	-- Reverse lookup (class → name) + counter per name.
	local class_to_name = {}
	local counts = {}

	for name, cls in pairs(expected_classes) do
		class_to_name[cls] = name
		counts[name] = 0
	end

	-- Walk the chain via the public API. Every instance must (a) actually
	-- be a Handler-family instance, and (b) be one of the expected
	-- classes. Fail with a specific position + info message if not.
	for i, actual_instance in ipairs(e:handlers()) do
		h.assert_true(
			is_handler_instance(actual_instance),
			"row_handlers[" .. i .. "] isn't a Handler-family instance — metatable chain doesn't reach Handler"
		)

		local mt = getmetatable(actual_instance)
		local name = class_to_name[mt]

		h.assert_true(
			name ~= nil,
			"unexpected handler at row_handlers[" .. i .. "]: metatable not in the expected roster"
		)

		counts[name] = counts[name] + 1
	end

	-- Each expected class must appear exactly once.
	for name, count in pairs(counts) do
		h.assert_eq(
			count, 1,
			name .. " should appear exactly once in row_handlers (found " .. count .. ")"
		)
	end
end)
