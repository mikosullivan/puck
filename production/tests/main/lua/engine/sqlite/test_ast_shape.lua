--[[
{
	"spec": "test_ast_shape",
	"role": "Tests for the frame_ast-shape validation on frame INSERT. The `objects_ast_valid_insert` trigger fires on any INSERT into objects with control = 'f' and rejects non-array JSON (a hash-shaped frame_ast, a scalar, corrupted text). This test verifies the trigger fires on an frame_ast that decodes as a JSON object."
}
]]

--[[
# `test_ast_shape`

The engine's shape check for a frame's `frame_ast` value. Enforcement lives at the schema layer — the `objects_ast_valid_insert` trigger fires at INSERT time and rejects any frame_ast that isn't a JSON array. This test sets `caspm` to a Lua hash (which cjson encodes as a JSON object) and verifies the trigger fires with `ast_not_array`.

Also covered by defense-in-depth: `run_frame` shape-checks the decoded frame_ast after fetching it from the DB, raising `caspm_not_array` if the trigger somehow missed something. Under normal code paths the trigger fires first (at INSERT), so `caspm_not_array` is rarely observed.
]]

local h      = require('helpers')
local engine = require('engine')

local function assert_raises_matching(fn, pattern, msg)
	local ok, err = pcall(fn)

	if ok then
		error((msg or 'expected raise') .. ' — but call succeeded', 2)
	end

	if not string.find(tostring(err), pattern, 1, true) then
		error(
			(msg or 'expected raise') .. " — raise text didn't contain expected substring"
			.. '\n  substring: ' .. pattern
			.. '\n  got:       ' .. tostring(err),
			2
		)
	end
end

h.test('caspm shaped as a JSON object is rejected at insert by the ast_not_array trigger', function()
	local e = engine.new()
	e.caspm = {foo = 'bar'}  -- Lua hash → JSON object

	assert_raises_matching(
		function() e:run() end,
		'ast_not_array',
		'expected the ast_not_array trigger to fire on a hash-shaped frame_ast'
	)
end)
