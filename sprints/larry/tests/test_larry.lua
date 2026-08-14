--[[
{
	"spec": "test_larry",
	"role": "Sprint Larry tests. Standalone runner — verifies Larry's class shape. First test: a Larry instance is an instance of the Engine class (walks the metatable chain looking for Engine at any subclass depth).",
	"status": "sprint-scoped"
}
]]

--[[
# `test_larry`

Standalone test file for [`larry`](../src/larry.lua). Run from the repo root:

~~~
lua5.4 sprints/larry/tests/test_larry.lua
~~~

Larry is a subclass of Engine; tests here verify subclass shape and (as Larry grows) any convenience features it adds. First test: a Larry is-a Engine.
]]

package.path = "./sprints/larry/src/?.lua;"
	.. "./src/engine/?.lua;"
	.. "./src/engine/?/init.lua;"
	.. "./tests/main/lua/engine/?.lua;"
	.. (os.getenv("HOME") or "") .. "/.luarocks/share/lua/5.4/?.lua;"
	.. (os.getenv("HOME") or "") .. "/.luarocks/share/lua/5.4/?/init.lua;"
	.. package.path
package.cpath = (os.getenv("HOME") or "") .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local Engine  = require("engine")
local Larry   = require("larry")
local helpers = require("helpers")

-- ------------------------------------------------------------
-- Local test infrastructure (matches other sprint tests;
-- promotes into the shared runner when the sprint closes).
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

local function assert_true(cond, msg)
	if cond then return end
	error(msg or "expected truthy", 2)
end

-- Walks an instance's metatable chain looking for a class. Returns
-- true if the instance is an instance of the class (directly or via
-- any subclass depth); false otherwise.
local function is_instance_of(instance, cls)
	local mt = getmetatable(instance)

	while mt do
		if mt == cls then return true end

		local parent = getmetatable(mt)

		if parent and type(parent) == "table" and parent.__index and type(parent.__index) == "table" then
			mt = parent.__index
		else
			return false
		end
	end

	return false
end

-- ==============================================================
-- Tests
-- ==============================================================

test("a larry is an instance of Engine", function()
	local larry = Larry.new()
	assert_true(
		is_instance_of(larry, Engine),
		"expected Larry.new() to return an instance whose metatable chain reaches Engine"
	)
end)

test("Larry.new() leaves stdout nil by default (opt-in convenience)", function()
	local larry = Larry.new()
	assert_true(
		larry.stdout == nil,
		"expected larry.stdout to be nil at construction; conveniences are opt-in"
	)
end)

test("Larry.new() leaves stderr nil by default (opt-in convenience)", function()
	local larry = Larry.new()
	assert_true(
		larry.stderr == nil,
		"expected larry.stderr to be nil at construction; conveniences are opt-in"
	)
end)

test("set_fake_stdout wires a FakeOutput into self.stdout", function()
	local larry = Larry.new()
	larry:set_fake_stdout()
	assert_true(
		getmetatable(larry.stdout) == helpers.FakeOutput,
		"expected larry.stdout to be a FakeOutput instance after set_fake_stdout()"
	)
end)

test("set_fake_stdout returns the FakeOutput it wired", function()
	local larry = Larry.new()
	local returned = larry:set_fake_stdout()
	assert_true(
		returned == larry.stdout,
		"expected set_fake_stdout to return the same instance it assigned to self.stdout"
	)
end)

test("larry.stdout (via set_fake_stdout) captures :print output", function()
	local larry = Larry.new()
	local fake = larry:set_fake_stdout()
	larry.stdout:print("hello ")
	larry.stdout:print("world")

	local captured = fake:get_all()

	if captured ~= "hello world" then
		error("expected 'hello world', got: " .. tostring(captured), 2)
	end
end)

test("set_fake_stderr wires a FakeOutput into self.stderr", function()
	local larry = Larry.new()
	larry:set_fake_stderr()
	assert_true(
		getmetatable(larry.stderr) == helpers.FakeOutput,
		"expected larry.stderr to be a FakeOutput instance after set_fake_stderr()"
	)
end)

test("set_fake_stderr returns the FakeOutput it wired", function()
	local larry = Larry.new()
	local returned = larry:set_fake_stderr()
	assert_true(
		returned == larry.stderr,
		"expected set_fake_stderr to return the same instance it assigned to self.stderr"
	)
end)

test("larry.stderr (via set_fake_stderr) captures :print output", function()
	local larry = Larry.new()
	local fake = larry:set_fake_stderr()
	larry.stderr:print("oops")

	local captured = fake:get_all()

	if captured ~= "oops" then
		error("expected 'oops', got: " .. tostring(captured), 2)
	end
end)

test("set_fake_stdout and set_fake_stderr wire independent FakeOutputs", function()
	local larry = Larry.new()
	larry:set_fake_stdout()
	larry:set_fake_stderr()

	assert_true(
		larry.stdout ~= larry.stderr,
		"expected stdout and stderr to be independent FakeOutput instances"
	)

	-- Writing to one shouldn't affect the other.
	larry.stdout:print("out")
	larry.stderr:print("err")

	if larry.stdout:get_all() ~= "out" then
		error("expected stdout to hold 'out'; got: " .. tostring(larry.stdout:get_all()), 2)
	end

	if larry.stderr:get_all() ~= "err" then
		error("expected stderr to hold 'err'; got: " .. tostring(larry.stderr:get_all()), 2)
	end
end)

-- --------------------------------------------------------------
-- Row-handler chain: add / prepend / remove / clear / handlers
-- --------------------------------------------------------------

test("add_handler appends to row_handlers", function()
	local larry = Larry.new()
	local stock_count = #larry.row_handlers
	local h = {}
	larry:add_handler(h)
	assert_true(#larry.row_handlers == stock_count + 1, "expected chain length to grow by 1")
	assert_true(larry.row_handlers[#larry.row_handlers] == h, "expected new handler at the end of the chain")
end)

test("add_handler returns self for chaining", function()
	local larry = Larry.new()
	local returned = larry:add_handler({})
	assert_true(returned == larry, "expected add_handler to return self")
end)

test("prepend_handler inserts at index 1", function()
	local larry = Larry.new()
	local h = {}
	larry:prepend_handler(h)
	assert_true(larry.row_handlers[1] == h, "expected new handler at the front of the chain")
end)

test("prepend_handler returns self for chaining", function()
	local larry = Larry.new()
	local returned = larry:prepend_handler({})
	assert_true(returned == larry, "expected prepend_handler to return self")
end)

test("prepend_handler orders itself before stock handlers", function()
	local larry = Larry.new()
	local stock_first = larry.row_handlers[1]
	local h = {}
	larry:prepend_handler(h)
	assert_true(larry.row_handlers[1] == h, "new handler is at index 1")
	assert_true(larry.row_handlers[2] == stock_first, "previous first handler shifted to index 2")
end)

test("remove_handler removes by identity", function()
	local larry = Larry.new()
	local h = {}
	larry:add_handler(h)
	local before = #larry.row_handlers
	larry:remove_handler(h)
	assert_true(#larry.row_handlers == before - 1, "expected chain length to shrink by 1")

	local still_present = false

	for _, x in ipairs(larry.row_handlers) do
		if x == h then still_present = true end
	end

	assert_true(not still_present, "expected handler to be gone from the chain")
end)

test("remove_handler returns self for chaining", function()
	local larry = Larry.new()
	local h = {}
	larry:add_handler(h)
	local returned = larry:remove_handler(h)
	assert_true(returned == larry, "expected remove_handler to return self")
end)

test("remove_handler raises handler_not_found when handler is not in the chain", function()
	local larry = Larry.new()
	local h = {}
	local ok, err = pcall(function() larry:remove_handler(h) end)
	assert_true(not ok, "expected an error to be raised")
	assert_true(
		tostring(err):find("handler_not_found") ~= nil,
		"expected error to mention handler_not_found; got: " .. tostring(err)
	)
end)

test("remove_handler removes only the first occurrence when the same handler is added twice", function()
	local larry = Larry.new()
	larry:clear_handlers()
	local h = {}
	larry:add_handler(h)
	larry:add_handler(h)
	assert_true(#larry.row_handlers == 2, "sanity: chain has two entries")
	larry:remove_handler(h)
	assert_true(#larry.row_handlers == 1, "one entry left after single remove")
	assert_true(larry.row_handlers[1] == h, "remaining entry is still the handler")
end)

test("clear_handlers empties the chain", function()
	local larry = Larry.new()
	larry:clear_handlers()
	assert_true(#larry.row_handlers == 0, "expected chain to be empty after clear")
end)

test("clear_handlers returns self for chaining", function()
	local larry = Larry.new()
	local returned = larry:clear_handlers()
	assert_true(returned == larry, "expected clear_handlers to return self")
end)

test("handlers() returns the chain in order", function()
	local larry = Larry.new()
	larry:clear_handlers()
	local h1, h2, h3 = {}, {}, {}
	larry:add_handler(h1)
	larry:add_handler(h2)
	larry:add_handler(h3)

	local list = larry:handlers()

	assert_true(#list == 3, "expected handlers() to return 3 items")
	assert_true(list[1] == h1, "list[1] is h1")
	assert_true(list[2] == h2, "list[2] is h2")
	assert_true(list[3] == h3, "list[3] is h3")
end)

test("handlers() returns a copy — mutating the returned list does NOT affect the live chain", function()
	local larry = Larry.new()
	local list = larry:handlers()
	local before = #larry.row_handlers
	table.insert(list, {})
	assert_true(
		#larry.row_handlers == before,
		"live row_handlers should be unchanged after mutating the returned list"
	)
end)

-- ==============================================================
-- Summary
-- ==============================================================

print("--------------------------------------------------------")
print(string.format("%d passed, %d failed", pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
