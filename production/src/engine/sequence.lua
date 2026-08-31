--[[
{
	"module": "sequence",
	"role": "A monotonically incrementing string-integer counter. Every allocation in CVM (object IDs, reference IDs, hash-element IDs, src keys, ast keys) draws from a shared Sequence stashed on the state hash. Encapsulates the counter's value + the increment algorithm so callers just say `:next()` at the allocation site.",
	"exports": {
		"new": "(start?: string-integer, default '1') -> Sequence"
	},
	"why_string_integer": "Lua 5.4's integer type tops out at 2^63-1 (fine for realistic programs), and its float type loses integer precision past 2^53. Keeping the counter as a decimal string dodges both cliffs — the counter grows indefinitely with no precision loss and no bigint machinery."
}
]]

--[[
# Sequence

`sequence.new()` returns a fresh Sequence starting at `"1"` — at rest, the
Sequence's next-to-hand-out value is `"1"`. `:next()` returns the current
value and advances the counter in place.

Every ID kind in the engine draws from one shared Sequence per state:
object IDs, reference IDs, hash-element IDs, src keys, ast keys. First
`:next()` returns `"1"`; subsequent calls return `"2"`, `"3"`, and so on
without ever repeating within a program's lifetime.

Nested-object stack IDs are the one exception — they use UUIDs
because they appear as keys inside user buckets where integer-strings
could collide with user-chosen field names. See the `object_pk`
description in [cvm](https://puck.uno/requirements/cvm/sqlite/) for
the UUID shape rule.
]]

local M = {}

local Sequence = {}
Sequence.__index = Sequence

--[[
## The Sequence constructor

`sequence.new()` creates a fresh Sequence — the small counter object,
NOT the CVM state hash. State creation goes through `state.new()`
in [state.lua](../engine/state.lua), which calls `sequence.new()`
internally as one of its first acts and stashes the returned Sequence
as `state.sequence`. Called on its own, `sequence.new()` just mints a
standalone counter that anybody can hold and call `:next()` on.

The returned Sequence starts at `"1"`, so the first `:next()` returns
`"1"`. Optional `start` seeds the counter at any decimal-integer
string — useful in tests that want to hit specific carry cases
without calling `:next()` thousands of times to reach them.
]]
function M.new(start)
	return setmetatable({value = start or '1'}, Sequence)
end

--[[
## Handing out an ID

`seq:next()` returns the Sequence's current value and increments it in
place — the returned value IS the ID to use for whatever the caller
is about to allocate.

The increment algorithm walks digits right-to-left. If a digit is less
than 9, bump it and zero out any trailing 9s (`"129"` → `"130"`). If
every digit was 9, prepend `'1'` and zero the whole original length
(`"999"` → `"1000"`).

Byte-level: `'0'`–`'9'` are bytes 48–57 in ASCII, so `s:byte(i) - 48`
gives the digit as an integer and `string.char(48 + d + 1)` puts it
back as a character. No Lua-number conversion happens, so the counter
grows past `2^53` (the Lua 5.4 integer-vs-float boundary) with no
precision loss.
]]
function Sequence:next()
	local current = self.value
	local i = #current

	while i > 0 do
		local d = current:byte(i) - 48

		if d < 9 then
			self.value = current:sub(1, i - 1) .. string.char(48 + d + 1) .. string.rep('0', #current - i)
			return current
		end

		i = i - 1
	end

	self.value = '1' .. string.rep('0', #current)
	return current
end

return M
