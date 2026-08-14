--[[
{
	"spec": "test_ast_shape",
	"role": "Sprint test for StmtWalker's ast shape check. Verifies the walker raises `caspm_not_array` when the frame's ast decodes to something other than a JSON array (e.g., a JSON object).",
	"status": "sprint-scoped"
}
]]

--[[
# `test_ast_shape`

Standalone runner for the walker's warm-fuzzy shape check on the decoded ast. The check inside `run_frame` fires when the JSON in the frame's `ast` column doesn't decode as a JSON array — a corrupted row, a caller that stuffed a hash in by mistake, anything of the shape `{"foo": "bar"}`.

~~~
lua5.4 sprints/end-to-end/tests/test_ast_shape.lua
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

-- ==============================================================
-- Tests
-- ==============================================================

-- The shape check has two enforcement layers now: the SQLite trigger
-- fires at INSERT time in create_frame_0, and the Lua check inside
-- run_frame's decode step is defense-in-depth. The trigger fires
-- first, so `run()` on a bad caspm surfaces the trigger's error id
-- rather than the Lua raise.

test('caspm shaped as a JSON object is rejected at insert by the ast_not_array trigger', function()
	local walker = StmtWalker.new()
	walker.caspm = {foo = 'bar'}  -- Lua hash → JSON object

	local ok, err = pcall(function() walker:run() end)

	assert_true(not ok, 'expected run() to raise')
	assert_true(
		tostring(err):find('ast_not_array') ~= nil,
		'expected error to mention ast_not_array; got: ' .. tostring(err)
	)
end)

-- ==============================================================
-- Summary
-- ==============================================================

print('--------------------------------------------------------')
print(string.format('%d passed, %d failed', pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
