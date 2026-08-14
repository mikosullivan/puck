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

-- ==============================================================
-- Summary
-- ==============================================================

print("--------------------------------------------------------")
print(string.format("%d passed, %d failed", pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
