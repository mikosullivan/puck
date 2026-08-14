--[[
{
	"spec": "test_end_to_end",
	"role": "The sprint's flagship test. Runs an empty program through StmtWalker end-to-end and verifies the returned hash carries `complete` (1) and `message` (nil) — the two-field shape the caller sees when a process runs to completion.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_end_to_end`

The sprint's flagship test. An empty program (`walker.caspm = {}`) goes through StmtWalker; when `run` returns, it hands back a hash with two fields:

- `complete` — `1`, the process finished.
- `message` — `nil`, the empty program set no message.

Everything else along the way (frame 0 pushed, empty ast walked, frame deleted, process marked complete via trigger, process auto-deleted) happens as the design specifies but isn't asserted here — those DB-state checks live in [test_empty_end_to_end.lua](https://puck.uno/sprints/end-to-end/tests/test_empty_end_to_end.lua). This test's whole job is: **empty array in → hash with two fields out.**

~~~
lua5.4 sprints/end-to-end/tests/test_end_to_end.lua
~~~
]]

package.path = './sprints/end-to-end/src/?.lua;'
	.. './tests/main/lua/engine/?.lua;'
	.. './src/engine/?.lua;'
	.. './src/engine/?/init.lua;'
	.. (os.getenv('HOME') or '') .. '/.luarocks/share/lua/5.4/?.lua;'
	.. (os.getenv('HOME') or '') .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = (os.getenv('HOME') or '') .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local StmtWalker = require('stmt_walker')

local pass_count, fail_count = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)

	if ok then
		pass_count = pass_count + 1
		print('  PASS ' .. name)
	else
		fail_count = fail_count + 1
		print('  FAIL ' .. name)
		print('       ' .. tostring(err))
	end
end

local function assert_true(cond, msg)
	if cond then return end
	error(msg or 'expected truthy', 2)
end

local function assert_eq(actual, expected, msg)
	if actual == expected then return end
	error((msg or 'assertion failed') .. ' — expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
end

-- ==============================================================
-- Flagship: empty array in, hash with two fields out.
-- ==============================================================

test('empty program end-to-end: run() returns { complete = 1, message = nil }', function()
	local walker = StmtWalker.new()
	walker.caspm = {}

	local returned = walker:run()

	assert_true(type(returned) == 'table', 'expected run() to return a table')
	assert_eq(returned.complete, 1, 'expected returned.complete to be 1')
	assert_eq(returned.message, nil, 'expected returned.message to be nil (empty program sets no message)')
end)

-- ==============================================================
-- Summary
-- ==============================================================

print('--------------------------------------------------------')
print(string.format('%d passed, %d failed', pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
