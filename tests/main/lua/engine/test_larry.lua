--[[
{
	"spec": "test_larry",
	"role": "Tests for the Larry class — Engine subclass for test conveniences. Verifies subclass shape (is-a-Engine via metatable-chain walk) and the opt-in FakeOutput wiring methods (set_fake_stdout / set_fake_stderr)."
}
]]

--[[
# `test_larry`

Tests for [`larry`](https://puck.uno/tests/main/lua/engine/larry.lua). A Larry IS an Engine — the tests below verify the metatable chain reaches Engine, the constructor leaves stdout/stderr nil (opt-in convenience), and each `set_fake_*` method wires a fresh FakeOutput into its slot and returns the instance for inspection.
]]

local h       = require('helpers')
local engine  = require('engine')
local Larry   = require('larry')

-- Walks an instance's metatable chain looking for a class. Returns
-- true if the instance is an instance of the class (directly or via
-- any subclass depth); false otherwise.
local function is_instance_of(instance, cls)
	local mt = getmetatable(instance)

	while mt do
		if mt == cls then return true end

		local parent = getmetatable(mt)

		if parent and type(parent) == 'table' and parent.__index and type(parent.__index) == 'table' then
			mt = parent.__index
		else
			return false
		end
	end

	return false
end

h.test('a larry is an instance of Engine', function()
	local larry = Larry.new()
	h.assert_true(
		is_instance_of(larry, engine),
		'expected Larry.new() to return an instance whose metatable chain reaches Engine'
	)
end)

h.test('Larry.new() leaves stdout nil by default (opt-in convenience)', function()
	local larry = Larry.new()
	h.assert_true(
		larry.stdout == nil,
		'expected larry.stdout to be nil at construction; conveniences are opt-in'
	)
end)

h.test('Larry.new() leaves stderr nil by default (opt-in convenience)', function()
	local larry = Larry.new()
	h.assert_true(
		larry.stderr == nil,
		'expected larry.stderr to be nil at construction; conveniences are opt-in'
	)
end)

h.test('set_fake_stdout wires a FakeOutput into self.stdout', function()
	local larry = Larry.new()
	larry:set_fake_stdout()
	h.assert_true(
		getmetatable(larry.stdout) == h.FakeOutput,
		'expected larry.stdout to be a FakeOutput instance after set_fake_stdout()'
	)
end)

h.test('set_fake_stdout returns the FakeOutput it wired', function()
	local larry = Larry.new()
	local returned = larry:set_fake_stdout()
	h.assert_true(
		returned == larry.stdout,
		'expected set_fake_stdout to return the same instance it assigned to self.stdout'
	)
end)

h.test('larry.stdout (via set_fake_stdout) captures :print output', function()
	local larry = Larry.new()
	local fake = larry:set_fake_stdout()
	larry.stdout:print('hello ')
	larry.stdout:print('world')
	h.assert_eq(fake:get_all(), 'hello world', "expected captured stdout to be 'hello world'")
end)

h.test('set_fake_stderr wires a FakeOutput into self.stderr', function()
	local larry = Larry.new()
	larry:set_fake_stderr()
	h.assert_true(
		getmetatable(larry.stderr) == h.FakeOutput,
		'expected larry.stderr to be a FakeOutput instance after set_fake_stderr()'
	)
end)

h.test('set_fake_stderr returns the FakeOutput it wired', function()
	local larry = Larry.new()
	local returned = larry:set_fake_stderr()
	h.assert_true(
		returned == larry.stderr,
		'expected set_fake_stderr to return the same instance it assigned to self.stderr'
	)
end)

h.test('larry.stderr (via set_fake_stderr) captures :print output', function()
	local larry = Larry.new()
	local fake = larry:set_fake_stderr()
	larry.stderr:print('oops')
	h.assert_eq(fake:get_all(), 'oops', "expected captured stderr to be 'oops'")
end)

h.test('set_fake_stdout and set_fake_stderr wire independent FakeOutputs', function()
	local larry = Larry.new()
	larry:set_fake_stdout()
	larry:set_fake_stderr()

	h.assert_true(
		larry.stdout ~= larry.stderr,
		'expected stdout and stderr to be independent FakeOutput instances'
	)

	-- Writing to one shouldn't affect the other.
	larry.stdout:print('out')
	larry.stderr:print('err')
	h.assert_eq(larry.stdout:get_all(), 'out', "expected stdout to hold 'out'")
	h.assert_eq(larry.stderr:get_all(), 'err', "expected stderr to hold 'err'")
end)
