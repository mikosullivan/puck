#!/usr/bin/env lua5.4

--[[
{
	"module": "test_larry",
	"role": "End-to-end tests for the sprint's Larry (Engine subclass) exercising the new scopes-based variable-storage design. Builds up frame 0 by hand and calls `frame:set_local_to_scalar` directly — the variable-scalar handler is still a stub in shipping, so we don't drive this from Caspian source yet. Verifies the resulting object graph (`bucket → scopes → scopes[0] → x → scalar`) and the marker-then-advance flow.",
	"run": "lua5.4 sprints/first-variable/test_larry.lua (from repo root)"
}
]]

--[[
# `test_larry`

Tests the Larry (sprint's Engine subclass) end-to-end using the sprint's rewritten `cvm.frame`. Each test:

1. Instantiates a Larry — brings up an in-memory CVM on the sprint schema.
2. Seeds a process + a frame 0 directly (bypassing the handler chain, which still sits on a stub in shipping).
3. Calls `frame:set_local_to_scalar('x', 'n', 1)`.
4. Asserts against the object-graph shape the scopes design specifies.

A separate case simulates the walker's `stmt_idx` advance and verifies the marker gets swept.
]]


-- ------------------------------------------------------------
-- bootstrap
-- ------------------------------------------------------------

local script_dir = 'sprints/first-variable/'
local home = os.getenv('HOME') or ''
package.path = './src/engine/?.lua;./src/engine/?/init.lua;'
	.. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite  = require('lsqlite3')
local Larry   = require('larry')
local cvm_mod = require('cvm')

local SQLITE_ROW = sqlite.ROW


-- ------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end

local function count(db, sql)
	local row = first(db, sql)
	return tonumber(row and (row.n or row.count) or 0)
end

--[[
Seed a fresh process + frame 0 and return the frame wrapper. Uses a CVM data-access instance (`cvm_mod.new(handle)`) to wrap rows, since the frame class expects its `self.engine` to be a data-access CVM (with `add_scalar`, `add_hash`, `add_array`, `add_ref`, `get_ref_child`, `object_by_pk`), not the SQLite handle directly.

Returns `(frame, cvm, process_pk, user_pk)`. Caller uses `cvm.db` for raw SQL when needed.
]]
local function seed_frame_0(larry, ast_json)
	local handle = larry.cvm  -- SQLite handle
	local cvm    = cvm_mod.new(handle)

	-- process row
	handle:exec('insert into processes default values;')
	local process_pk = first(handle, 'select process_pk from processes').process_pk

	-- user role pk (seeded by schema)
	local user_pk = first(handle, "select object_pk from objects where core_role = 'u'").object_pk

	-- frame 0
	local sql = "insert into objects (primitive, ast, stmt_idx, process_pk, owner_role) "
		.. "values ('f', '" .. ast_json .. "', 0, '" .. process_pk .. "', '" .. user_pk .. "') "
		.. "returning object_pk"
	local frame_pk
	for row in handle:nrows(sql) do frame_pk = row.object_pk end

	local frame = cvm:object_by_pk(frame_pk)

	return frame, cvm, process_pk, user_pk
end


-- ------------------------------------------------------------
-- test runner
-- ------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		passed = passed + 1
		print('  PASS  ' .. name)
	else
		failed = failed + 1
		print('  FAIL  ' .. name)
		table.insert(failures, {name = name, err = err})
	end
end


-- ------------------------------------------------------------
-- $x = 1 : shape of the object graph after set_local_to_scalar
-- ------------------------------------------------------------

test('after set_local_to_scalar: bucket exists with a scopes ref', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	frame:set_local_to_scalar('x', 'n', 1)

	-- Frame's bucket_pk is now populated (denormalized from bucket_for).
	local bucket_pk = first(larry.cvm, "select bucket_pk from objects where object_pk = '" .. frame.object_pk .. "'").bucket_pk
	assert(bucket_pk ~= nil, 'frame should have a bucket_pk after set_local_to_scalar')

	-- Bucket exists.
	local bucket_row = first(larry.cvm, "select primitive from objects where object_pk = '" .. bucket_pk .. "'")
	assert(bucket_row.primitive == 'h', 'bucket should be primitive=h')

	-- Bucket has a `scopes` ref pointing at an ArrayPrimitive.
	local scopes_row = first(larry.cvm, "select object_pk, primitive from objects "
		.. "where object_pk = (select child from refs where parent = '" .. bucket_pk .. "' and key = 'scopes')")
	assert(scopes_row ~= nil, 'bucket should have a scopes ref')
	assert(scopes_row.primitive == 'a', 'scopes target should be primitive=a (ArrayPrimitive)')
end)

test('after set_local_to_scalar: scopes[0] is a hash holding the binding', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	frame:set_local_to_scalar('x', 'n', 1)

	local bucket_pk = first(larry.cvm, "select bucket_pk from objects where object_pk = '" .. frame.object_pk .. "'").bucket_pk
	local scopes_pk = first(larry.cvm, "select child from refs where parent = '" .. bucket_pk .. "' and key = 'scopes'").child

	-- scopes[0] — the ref with idx = 0
	local own_scope_row = first(larry.cvm, "select object_pk, primitive from objects "
		.. "where object_pk = (select child from refs where parent = '" .. scopes_pk .. "' and idx = 0)")
	assert(own_scope_row ~= nil, 'scopes[0] should exist')
	assert(own_scope_row.primitive == 'h', 'own scope should be primitive=h (hash)')

	-- own_scope['x'] → scalar 1
	local binding = first(larry.cvm, "select o.scalar_type, o.scalar_value from objects o "
		.. "join refs r on r.child = o.object_pk "
		.. "where r.parent = '" .. own_scope_row.object_pk .. "' and r.key = 'x'")
	assert(binding ~= nil, 'own_scope should have an x binding')
	assert(binding.scalar_type == 'n', 'x should bind to scalar_type=n')
	assert(tonumber(binding.scalar_value) == 1, 'x should bind to value 1')
end)

test('after set_local_to_scalar: a GC marker is present as child of the frame', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	frame:set_local_to_scalar('x', 'n', 1)

	local marker_row = first(larry.cvm, "select object_pk, primitive, gc, ast, stmt_idx "
		.. "from objects where parent_frame = '" .. frame.object_pk .. "'")
	assert(marker_row ~= nil, 'a child should exist under frame')
	assert(marker_row.primitive == 'f', 'child should be a frame row')
	assert(marker_row.gc == 1, 'child should be a GC marker (gc=1)')
	assert(marker_row.ast == nil, 'marker ast should be null')
	assert(marker_row.stmt_idx == nil, 'marker stmt_idx should be null')

	-- exactly one child, per objects_one_child_per_frame
	assert(count(larry.cvm, "select count(*) as n from objects where parent_frame = '" .. frame.object_pk .. "'") == 1,
		'exactly one child under the frame')
end)


-- ------------------------------------------------------------
-- walker advance: stmt_idx = 1 sweeps the marker
-- ------------------------------------------------------------

test('advancing the frame stmt_idx sweeps the marker (atomic in one UPDATE)', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	frame:set_local_to_scalar('x', 'n', 1)

	-- Sanity: marker present
	assert(count(larry.cvm, "select count(*) as n from objects where parent_frame = '" .. frame.object_pk .. "' and gc = 1") == 1)

	-- Walker's advance: stmt_idx = 1 (+1 from 0). Under the sprint schema,
	-- the marker-required trigger passes (marker exists), and the after-
	-- update trigger deletes the marker in the same op.
	larry.cvm:exec("update objects set stmt_idx = 1, dcok = 1 where object_pk = '" .. frame.object_pk .. "';")

	assert(count(larry.cvm, "select count(*) as n from objects where parent_frame = '" .. frame.object_pk .. "'") == 0,
		'marker should be gone after stmt_idx advance')

	-- frame's own state is intact: stmt_idx now 1, bindings still there
	local frame_row = first(larry.cvm, "select stmt_idx from objects where object_pk = '" .. frame.object_pk .. "'")
	assert(tonumber(frame_row.stmt_idx) == 1)

	local bucket_pk = first(larry.cvm, "select bucket_pk from objects where object_pk = '" .. frame.object_pk .. "'").bucket_pk
	local scopes_pk = first(larry.cvm, "select child from refs where parent = '" .. bucket_pk .. "' and key = 'scopes'").child
	local own_pk = first(larry.cvm, "select child from refs where parent = '" .. scopes_pk .. "' and idx = 0").child
	local x_binding = first(larry.cvm, "select scalar_value from objects "
		.. "where object_pk = (select child from refs where parent = '" .. own_pk .. "' and key = 'x')")
	assert(tonumber(x_binding.scalar_value) == 1, 'x binding should survive the advance')
end)


-- ------------------------------------------------------------
-- idempotence of ensure_own_scope
-- ------------------------------------------------------------

test('ensure_own_scope is idempotent — same hash across calls, one scopes entry', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	local first_call  = frame:ensure_own_scope()
	local second_call = frame:ensure_own_scope()

	assert(first_call.object_pk == second_call.object_pk,
		'both calls should return the same own_scope hash')

	local bucket_pk = first(larry.cvm, "select bucket_pk from objects where object_pk = '" .. frame.object_pk .. "'").bucket_pk
	local scopes_pk = first(larry.cvm, "select child from refs where parent = '" .. bucket_pk .. "' and key = 'scopes'").child

	-- Only one entry in the scopes array (no duplicate scopes[0]).
	assert(count(larry.cvm, "select count(*) as n from refs where parent = '" .. scopes_pk .. "'") == 1,
		'scopes array should have exactly one entry')
end)

test('own_scope returns nil on a fresh frame (before ensure)', function()
	local larry = Larry.new()
	local frame = seed_frame_0(larry, '[[{"in":"as"},"x",{"v":1}]]')

	assert(frame:own_scope() == nil,
		'own_scope should return nil before ensure_own_scope has run')
end)


-- ------------------------------------------------------------
-- report
-- ------------------------------------------------------------

print()
print(string.format('TOTAL: %d passed, %d failed', passed, failed))

if failed > 0 then
	print()
	print('Failures:')

	for _, f in ipairs(failures) do
		print('  [' .. f.name .. ']')

		for line in tostring(f.err):gmatch('[^\n]+') do
			print('    ' .. line)
		end
	end

	os.exit(1)
end

os.exit(0)
