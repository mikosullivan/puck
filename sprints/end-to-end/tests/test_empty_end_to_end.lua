--[[
{
	"spec": "test_empty_end_to_end",
	"role": "DB-state assertions for the sprint's end-to-end empty-program scenario. Runs an empty program through StmtWalker and inspects the resulting CVM tables — with and without keep-alive — to confirm the shutdown behavior lands as designed. The return-hash shape check is in test_end_to_end.lua.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_empty_end_to_end`

DB-state suite for the empty-program end-to-end scenario. What does the CVM look like after `walker.caspm = {}; walker:run()` returns? These tests check the `processes` and `objects` tables in both the auto-delete-default and keep-alive configurations.

The flagship shape check (empty array in → hash with two fields out) lives in [test_end_to_end.lua](https://puck.uno/sprints/end-to-end/tests/test_end_to_end.lua).

~~~
lua5.4 sprints/end-to-end/tests/test_empty_end_to_end.lua
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

-- Fetch a single scalar from a one-row-one-column query. Returns nil
-- if no rows.
local function scalar(cvm, sql, ...)
	local stmt = cvm:prepare(sql)

	if select('#', ...) > 0 then
		stmt:bind_values(...)
	end

	local out

	for row in stmt:rows() do
		out = row[1]
	end

	stmt:reset()

	return out
end

-- ==============================================================
-- Tests
-- ==============================================================

-- The "empty program runs cleanly" and "returned hash has complete/message"
-- shape checks live in test_end_to_end.lua — this file is the DB-state
-- suite: what does the CVM look like after an empty run completes, with
-- and without keep-alive?

test('after empty run with keep-alive, the process row has complete = 1', function()
	local walker = StmtWalker.new()
	walker.auto_delete_process = false
	walker.caspm = {}
	walker:run()

	local count = scalar(walker.cvm, 'select count(*) from processes where complete = 1')
	assert_eq(count, 1, 'expected exactly one process with complete = 1')

	local total = scalar(walker.cvm, 'select count(*) from processes')
	assert_eq(total, 1, 'expected exactly one process row total')
end)

test('after empty run, the process row is auto-deleted by default', function()
	local walker = StmtWalker.new()
	walker.caspm = {}
	walker:run()

	local total = scalar(walker.cvm, 'select count(*) from processes')
	assert_eq(total, 0, 'expected the process row to be gone after default auto-delete')
end)

test('after empty run, the frame row is gone from objects', function()
	local walker = StmtWalker.new()
	walker.caspm = {}
	walker:run()

	local frame_count = scalar(walker.cvm, "select count(*) from objects where primitive = 'f'")
	assert_eq(frame_count, 0, 'expected zero frame rows after shutdown')
end)

test('after empty run, only the user seed remains in objects', function()
	local walker = StmtWalker.new()
	walker.caspm = {}
	walker:run()

	local total = scalar(walker.cvm, 'select count(*) from objects')
	assert_eq(total, 1, 'expected one object row (the user seed) after shutdown')

	local user_count = scalar(walker.cvm, 'select count(*) from objects where user = 1')
	assert_eq(user_count, 1, 'expected the surviving row to be the user seed')
end)

test('after empty run, refs is still empty', function()
	local walker = StmtWalker.new()
	walker.caspm = {}
	walker:run()

	local refs_count = scalar(walker.cvm, 'select count(*) from refs')
	assert_eq(refs_count, 0, 'expected refs to remain empty')
end)

test('after empty run with keep-alive, message stays null (nothing set it)', function()
	local walker = StmtWalker.new()
	walker.auto_delete_process = false
	walker.caspm = {}
	walker:run()

	local null_result_count = scalar(walker.cvm, 'select count(*) from processes where message is null')
	assert_eq(null_result_count, 1, 'expected the process row to have message = null')
end)

-- ==============================================================
-- Summary
-- ==============================================================

print('--------------------------------------------------------')
print(string.format('%d passed, %d failed', pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
