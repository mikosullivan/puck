--[[
{
	"spec": "test_dispatch",
	"role": "Sprint dispatch tests. Standalone runner. Two groups: (1) unit tests for the three utility handler subclasses baked into handler.lua (AlwaysTrue / AlwaysFalse / AlwaysRaise) — verify each does what it says independent of dispatch. (2) dispatch chain-of-responsibility semantics — empty array, single-true, single-false, fall-through, raise-propagation, first-wins.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_dispatch`

Standalone test file for [`dispatch`](../src/dispatch.lua) and the three utility handler subclasses in [`handler.lua`](../src/handler.lua). Run from the repo root:

~~~
lua5.4 sprints/dispatch/tests/test_dispatch.lua
~~~

Two groups of tests:

**Utility-handler unit tests** — direct assertions on `Handler.AlwaysTrue`, `Handler.AlwaysFalse`, `Handler.AlwaysRaise`. Each verifies the subclass does what its name says, independent of dispatch. These come first because the dispatch tests use these handlers as tools; the tools have to work before the tool-users are trustworthy.

**Dispatch chain tests** — empty handlers array raises; AlwaysTrue alone returns cleanly; AlwaysFalse alone raises (all-declined fallback); AlwaysFalse-then-AlwaysTrue returns cleanly (fall-through); AlwaysRaise alone propagates its raise; AlwaysTrue-then-AlwaysRaise returns cleanly (first-wins, AlwaysRaise never fires).
]]

package.path = "./sprints/dispatch/src/?.lua;" .. package.path

local Handler  = require("handler")
local dispatch = require("dispatch")

-- ------------------------------------------------------------
-- Local test infrastructure (matches the pattern of other
-- sprint tests; promotes into the shared runner on close).
-- ------------------------------------------------------------

local pass_count, fail_count = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)

	if ok then
		pass_count = pass_count + 1
		print("  PASS " .. name)
	else
		fail_count = fail_count + 1
		print("  FAIL " .. name)
		print("       " .. tostring(err))
	end
end

local function assert_eq(actual, expected, msg)
	if actual == expected then return end
	error((msg or "not equal") .. "\n  actual:   " .. tostring(actual) .. "\n  expected: " .. tostring(expected), 2)
end

local function assert_raises_matching(fn, pattern, msg)
	local ok, err = pcall(fn)
	assert_eq(ok, false, (msg or "expected raise") .. " — but call succeeded")

	if not string.find(tostring(err), pattern, 1, true) then
		error((msg or "expected raise") .. " — raise text didn't contain expected substring\n  substring: " .. pattern .. "\n  got:       " .. tostring(err), 2)
	end
end

-- ==============================================================
-- Utility handler unit tests — verify each subclass does what its
-- name says. These use the handlers directly (no dispatch involved)
-- so a failure here points at the handler, not the chain logic.
-- ==============================================================

test("Handler.AlwaysTrue:handle returns true", function()
	local h = Handler.AlwaysTrue.new()
	assert_eq(h:handle(), true, "AlwaysTrue:handle should return true")
end)

test("Handler.AlwaysFalse:handle returns false", function()
	local h = Handler.AlwaysFalse.new()
	assert_eq(h:handle(), false, "AlwaysFalse:handle should return false")
end)

test("Handler.AlwaysRaise:handle raises with 'always_raise_fired' id", function()
	local h = Handler.AlwaysRaise.new()
	assert_raises_matching(
		function() h:handle() end,
		"always_raise_fired",
		"AlwaysRaise:handle should raise with the always_raise_fired id"
	)
end)

-- ==============================================================
-- Dispatch chain tests
-- ==============================================================

test("empty handlers array raises unrecognized_row_head", function()
	assert_raises_matching(
		function() dispatch({}) end,
		"unrecognized_row_head",
		"empty handlers array should raise unrecognized_row_head"
	)
end)

test("AlwaysTrue alone: dispatch returns cleanly", function()
	local handlers = { Handler.AlwaysTrue.new() }
	dispatch(handlers)   -- should not raise; asserted by not-pcall
end)

test("AlwaysFalse alone: raises unrecognized_row_head (all-declined fallback)", function()
	local handlers = { Handler.AlwaysFalse.new() }
	assert_raises_matching(
		function() dispatch(handlers) end,
		"unrecognized_row_head",
		"AlwaysFalse alone should trigger the all-declined fallback raise"
	)
end)

test("AlwaysFalse then AlwaysTrue: dispatch returns cleanly (fall-through)", function()
	local handlers = {
		Handler.AlwaysFalse.new(),
		Handler.AlwaysTrue.new(),
	}
	dispatch(handlers)   -- false doesn't stop the walk; true stops it
end)

test("AlwaysRaise alone: raise propagates", function()
	local handlers = { Handler.AlwaysRaise.new() }
	assert_raises_matching(
		function() dispatch(handlers) end,
		"always_raise_fired",
		"AlwaysRaise's error message should reach the caller through dispatch"
	)
end)

test("AlwaysTrue then AlwaysRaise: dispatch returns cleanly (first-wins)", function()
	local handlers = {
		Handler.AlwaysTrue.new(),
		Handler.AlwaysRaise.new(),
	}
	-- Should not raise: AlwaysTrue's `true` return stops the loop
	-- before AlwaysRaise ever gets called. If first-wins was broken,
	-- AlwaysRaise would fire and the pcall inside `test` would catch
	-- always_raise_fired here.
	dispatch(handlers)
end)

-- ==============================================================
-- Summary
-- ==============================================================

print("--------------------------------------------------------")
print(string.format("%d passed, %d failed", pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
