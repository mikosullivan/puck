#!/usr/bin/env lua5.4

--[[
{
	"module": "test_larry",
	"role": "End-to-end tests for the sprint's Larry (Engine subclass) exercising the new scopes-based variable-storage design. Two flavors of test coverage: (1) hand-built tests that seed frame 0 directly and call `frame:set_local_to_scalar` to verify the CVM-level graph shape (`bucket → scopes → scopes[0] → x → scalar`), and (2) full-dispatch-chain tests that run `larry:load('$x = 1'); larry:run()` and verify the resulting state. The larry:run path stops at 'cap reaches terminal state, orphans marked needs_trace' — GC isn't written yet, so nothing sweeps the orphaned graph or reaps the cap.",
	"run": "lua5.4 sprints/first-variable/test_larry.lua (from repo root)"
}
]]

--[[
# `test_larry`

Tests the Larry (sprint's Engine subclass) end-to-end using the sprint's rewritten `cvm.frame` and the sprint's `variable-scalar` handler.

Two flavors of tests here:

1. **Graph-shape tests** — seed frame 0 by hand, call `frame:set_local_to_scalar('x', 'n', 1)` directly, assert the object-graph shape the scopes design specifies. Bypasses the handler chain to isolate the write mechanics.

2. **Full-dispatch tests** — run `larry:load('$x = 1'); larry:run()` and verify the resulting state. Exercises the whole path: transpile → normalize → dispatch through the handler chain → variable-scalar handler → set_local_to_scalar → cap advance.

**GC isn't written yet.** The full-dispatch test takes the process only as far as "cap in terminal state, orphaned bucket marked `needs_trace = 1`" — i.e., "the script has run, everything is ready for the first GC pass." Sweeping the orphans and reaping the cap land with GC-substrate integration.
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
Fetch a frame's bucket pk (the frame's hash-child via refs) under the
sprint's refs-based ownership design. Returns nil if the frame has no
bucket yet.
]]
local function frame_bucket_pk(db, frame_pk)
	local row = first(db,
		"select r.child from refs r "
		.. "join objects o on o.object_pk = r.child "
		.. "where r.parent = '" .. frame_pk .. "' and o.primitive = 'h'")
	return row and row.child
end

--[[
Seed a fresh process cap + frame 0 and return the frame wrapper. Uses Larry's own data-access CVM instance (`larry.data`) — that instance carries the sprint's overridden `add_bucket` / `add_stack` methods, which represent ownership as a normal `refs` row from the owner to the collection (the sprint schema has no `bucket_pk` / `stack_pk` columns for the shipping methods to touch).

The process is a `primitive='f'` cap row with `process=1`, `ast='[]'`, no parent. Frame 0 sits under it as a nested frame (`parent_frame=cap_pk`).

Returns `(frame, cvm, cap_pk, user_pk)`. Caller uses `cvm.db` for raw SQL when needed.
]]
local function seed_frame_0(larry, ast_json)
	local handle = larry.cvm  -- SQLite handle
	local cvm    = larry.data  -- Larry's data-access CVM (with sprint overrides)

	-- user role pk (seeded by schema)
	local user_pk = first(handle, "select object_pk from objects where core_role = 'u'").object_pk

	-- process cap: primitive='f', process=1, ast='[]'
	local cap_sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"
	local cap_pk
	for row in handle:nrows(cap_sql) do cap_pk = row.object_pk end

	-- frame 0: nested under the cap
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '" .. ast_json .. "', 0, '" .. cap_pk .. "', '" .. user_pk .. "') "
		.. "returning object_pk"
	local frame_pk
	for row in handle:nrows(sql) do frame_pk = row.object_pk end

	local frame = cvm:object_by_pk(frame_pk)

	return frame, cvm, cap_pk, user_pk
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

	-- Frame's bucket is now attached via a refs row (owner→bucket).
	local bucket_pk = frame_bucket_pk(larry.cvm, frame.object_pk)
	assert(bucket_pk ~= nil, 'frame should have a bucket after set_local_to_scalar')

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

	local bucket_pk = frame_bucket_pk(larry.cvm, frame.object_pk)
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
	assert(marker_row.gc == nil, 'marker gc should be null (terminal shape)')
	assert(marker_row.ast == '[]', 'marker ast should be empty array')
	assert(tonumber(marker_row.stmt_idx) == 0, 'marker stmt_idx should be 0')

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

	-- Sanity: marker present (born gc=null, terminal shape)
	assert(count(larry.cvm, "select count(*) as n from objects where parent_frame = '" .. frame.object_pk .. "'") == 1)

	-- Walker's advance: stmt_idx = 1 (+1 from 0) coupled with gc = 1
	-- in the same UPDATE. The AFTER-UPDATE OF gc trigger cascade-
	-- deletes the marker child; child's BEFORE-DELETE checks parent.gc=1
	-- (which it just became) and passes.
	larry.cvm:exec("update objects set stmt_idx = 1, gc = 1 where object_pk = '" .. frame.object_pk .. "';")

	assert(count(larry.cvm, "select count(*) as n from objects where parent_frame = '" .. frame.object_pk .. "'") == 0,
		'marker should be gone after stmt_idx advance')

	-- frame's own state is intact: stmt_idx now 1, bindings still there
	local frame_row = first(larry.cvm, "select stmt_idx from objects where object_pk = '" .. frame.object_pk .. "'")
	assert(tonumber(frame_row.stmt_idx) == 1)

	local bucket_pk = frame_bucket_pk(larry.cvm, frame.object_pk)
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

	local bucket_pk = frame_bucket_pk(larry.cvm, frame.object_pk)
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
-- Handler behavior: match / decline / raise
-- ------------------------------------------------------------

test('variable-scalar handler declines rows without {in="as"} head', function()
	local larry = Larry.new()

	-- Find the VariableScalar handler in the chain.
	local handler
	for _, h in ipairs(larry.row_handlers) do
		if h.handle and getmetatable(h).__index ~= require('handler') then
			handler = h
		end
	end
	assert(handler ~= nil, 'variable-scalar handler should be registered')

	-- Row with a different head atom.
	local claimed = handler:handle(larry, {{["in"] = "somethingelse"}, "x", {v = 1}})
	assert(claimed == false, 'handler should decline non-`as` heads (return false)')
end)

test('variable-scalar handler raises on an unsupported value atom', function()
	local larry = Larry.new()

	local handler
	for _, h in ipairs(larry.row_handlers) do
		if h.handle and getmetatable(h).__index ~= require('handler') then
			handler = h
		end
	end

	larry.current_frame = {}  -- doesn't matter — we should raise before reaching it

	local ok, err = pcall(handler.handle, handler, larry, {{["in"] = "as"}, "x", {some_other_kind = 42}})
	assert(ok == false, 'handler should raise on unsupported value atom')
	assert(tostring(err):find('variable_scalar_unsupported_value_atom'),
		'raise should carry variable_scalar_unsupported_value_atom id: ' .. tostring(err))
end)


-- ------------------------------------------------------------
-- $x = 1 : end-to-end via larry:load + larry:run
--
-- **This is NOT a full-process test.** GC hasn't been written yet.
-- The test takes the process up to the point where the cap reaches
-- terminal state (stmt_idx=1, gc=null, no children) and the orphaned
-- bucket is marked `needs_trace = 1` — i.e., "the script has run and
-- everything is ready for the first GC pass." It does NOT run GC,
-- does NOT sweep the bucket / scopes chain / scalar, and does NOT
-- reap the cap. Those steps land with GC-substrate integration.
-- ------------------------------------------------------------

test('larry:run runs `$x = 1` end-to-end through the dispatch chain', function()
	local larry = Larry.new()

	larry:load('$x = 1')
	local result = larry:run()

	-- Completion signal: cap in terminal shape (stmt_idx=1, gc=null,
	-- no children).
	assert(result.complete == 1, 'result should report complete=1')

	local cap = first(larry.cvm,
		"select stmt_idx, gc from objects where object_pk = '" .. result.cap_pk .. "'")
	assert(cap ~= nil, 'cap should still exist post-run (needs_trace + GC not wired)')
	assert(tonumber(cap.stmt_idx) == 1, 'cap stmt_idx should be 1')
	assert(cap.gc == nil, 'cap gc should be null')

	local cap_kids = count(larry.cvm,
		"select count(*) as n from objects where parent_frame = '" .. result.cap_pk .. "'")
	assert(cap_kids == 0, 'cap should have no children (frame 0 was cascade-swept)')

	-- The x binding survived orphaned. Bucket survives, marked
	-- needs_trace=1 (the next-GC-pass signal — set by the standard
	-- refs_mark_needs_trace_after_delete trigger when the owner→bucket
	-- ref was cascade-deleted with frame 0). The scopes chain hangs
	-- off it via the still-live refs.
	local binding = first(larry.cvm,
		"select o.scalar_type, o.scalar_value from objects o "
		.. "join refs r on r.child = o.object_pk where r.key = 'x'")
	assert(binding ~= nil, 'x binding should still be walkable via ref chain')
	assert(binding.scalar_type == 'n', 'x should bind to scalar_type=n')
	assert(tonumber(binding.scalar_value) == 1, 'x should bind to value 1')

	-- The orphaned bucket should be marked needs_trace=1.
	local bucket = first(larry.cvm,
		"select object_pk, needs_trace from objects "
		.. "where primitive = 'h' and needs_trace = 1")
	assert(bucket ~= nil, 'bucket should be marked needs_trace=1')
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
