local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;' .. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local h        = require('helpers')
local sequence = require('sequence')

--[[
## Constructor

`sequence.new()` returns a fresh Sequence at `"1"`. Optional `start`
argument seeds the counter at any decimal-integer string.
]]

h.test('sequence.new() with no args starts at "1"', function()
	local seq = sequence.new()
	h.assert_eq(seq:next(), '1', 'first :next() returns "1"')
end)

h.test('sequence.new(start) seeds the counter at the given value', function()
	local seq = sequence.new('42')
	h.assert_eq(seq:next(), '42', 'first :next() returns the seeded value')
	h.assert_eq(seq:next(), '43', 'next :next() advances by one')
end)

h.test('two Sequences advance independently', function()
	local a = sequence.new()
	local b = sequence.new()
	a:next()
	a:next()
	h.assert_eq(a:next(), '3', 'a is on its third handout')
	h.assert_eq(b:next(), '1', 'b is still on its first')
end)

--[[
## Handing out IDs

`seq:next()` returns the current value and increments in place — so
the returned value IS the ID the caller should use.
]]

h.test('successive :next() calls hand out sequential IDs', function()
	local seq = sequence.new()
	local ids = {}

	for _ = 1, 5 do
		table.insert(ids, seq:next())
	end

	h.assert_eq(ids[1], '1', 'first ID')
	h.assert_eq(ids[2], '2', 'second ID')
	h.assert_eq(ids[3], '3', 'third ID')
	h.assert_eq(ids[4], '4', 'fourth ID')
	h.assert_eq(ids[5], '5', 'fifth ID')
end)

--[[
## Carry propagation

Interesting cases for the string-integer increment: single-digit
rollover, no-carry mid-number, multi-digit carry, all-nines
length-grows.
]]

h.test('increment: single-digit rollover 9 → 10', function()
	local seq = sequence.new('9')
	h.assert_eq(seq:next(), '9',  'returned the current value')
	h.assert_eq(seq:next(), '10', 'incremented past a single-digit 9')
end)

h.test('increment: no-carry mid-number 129 → 130', function()
	local seq = sequence.new('129')
	seq:next()
	h.assert_eq(seq:next(), '130', 'trailing 9 became 0, tens digit bumped')
end)

h.test('increment: two-digit carry 99 → 100', function()
	local seq = sequence.new('99')
	seq:next()
	h.assert_eq(seq:next(), '100', 'length grew from 2 to 3')
end)

h.test('increment: all-nines 999 → 1000', function()
	local seq = sequence.new('999')
	seq:next()
	h.assert_eq(seq:next(), '1000', 'length grew from 3 to 4')
end)

h.test('increment: interior digit bump 1234 → 1235', function()
	local seq = sequence.new('1234')
	seq:next()
	h.assert_eq(seq:next(), '1235', 'ones digit bumped, other digits untouched')
end)

h.test('increment: carry stops at the first non-nine 1999 → 2000', function()
	local seq = sequence.new('1999')
	seq:next()
	h.assert_eq(seq:next(), '2000', 'carry propagated three positions and stopped at the 1')
end)

h.test('increment: past Lua 5.4 integer boundary preserves precision', function()
	-- 2^53 = 9007199254740992 — the point Lua floats stop representing integers exactly
	local seq = sequence.new('9007199254740992')
	seq:next()
	h.assert_eq(seq:next(), '9007199254740993', 'no precision loss past 2^53')
end)
