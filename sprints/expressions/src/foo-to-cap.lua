#!/usr/bin/env lua5.4
--[[
Sprint runner: demonstrate that a bare value expression as the only
statement of frame 0 ends up as the process cap's rv.

Source (conceptually):

    'foo'

The transpiler doesn't parse bare string literals as commands, so
we bypass load() and set `engine.caspm` directly to a hand-crafted
tree: one row containing one atom, `{v: "foo"}`.

Registers a BareLiteralHandler that matches a `[{v: <literal>}]`
row, materializes the value, sets the frame's rv to it, and marks
gc=1. Uses the SPRINT schema so `frames_child_delete_propagates_rv`
is baked in — when frame 0 reaps, the trigger copies its rv to the
cap, materializing the cap's bucket on demand.

Invoke:

    lua5.4 sprints/expressions/src/foo-to-cap.lua
]]

local script_dir = arg[0]:match('^(.*)/') or '.'
local repo_root  = script_dir .. '/../../..'
local home       = os.getenv('HOME') or ''

-- Sprint src FIRST so `require('transpiler')` picks up the sprint's
-- transpiler (with the bare-expression fallback), not production's.
package.path = repo_root .. '/sprints/expressions/src/?.lua;'
	.. repo_root .. '/production/src/engine/?.lua;'
	.. repo_root .. '/production/src/engine/?/init.lua;'
	.. repo_root .. '/production/tests/main/lua/engine/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local Larry = require('larry')

local SPRINT_SCHEMA = repo_root .. '/sprints/expressions/src/schema.sql'
local larry         = Larry.new({cvm = {schema_path = SPRINT_SCHEMA}})

-- ------------------------------------------------------------
-- BareLiteralHandler: matches a row of shape `[{v: <literal>}]`.
--
-- Materializes the value into an objects row, ensures the current
-- frame has a bucket, and inserts (or updates) an rv ref from that
-- bucket to the new value with key='rv'. Marks frame_gc=1 so the
-- walker can advance past this statement.
-- ------------------------------------------------------------

-- Grab the user role once for owner_role FK compliance on new inserts.
local user_pk
for row in larry.cvm:nrows("select object_pk from objects where control = 'r' and role_core = 'u'") do
	user_pk = row.object_pk
end

local BareLiteralHandler = {}
BareLiteralHandler.__index = BareLiteralHandler

function BareLiteralHandler.new()
	return setmetatable({}, BareLiteralHandler)
end

function BareLiteralHandler:handle(engine, row)
	if type(row) ~= 'table' or #row ~= 1 then
		return false
	end

	local atom = row[1]

	if type(atom) ~= 'table' or atom.v == nil then
		return false
	end

	local db        = engine.cvm
	local frame_pk  = engine.current_frame.object_pk
	local literal   = atom.v

	-- Step 1: materialize the value.
	local value_pk = engine.data:add_scalar(literal, user_pk)

	-- Step 2: ensure frame has a bucket. Look it up; if missing, create.
	local bucket_pk

	for row in db:nrows(
		"select r.child from refs r "
		.. "join objects h on h.object_pk = r.child and h.base = 'h' "
		.. "where r.parent = '" .. frame_pk .. "'"
	) do
		bucket_pk = row.child
	end

	if bucket_pk == nil then
		-- Create bucket.
		for row in db:nrows(
			"insert into objects (base, owner_role) values ('h', '"
			.. user_pk .. "') returning object_pk"
		) do
			bucket_pk = row.object_pk
		end

		-- Link frame → bucket.
		local next_idx = 0
		for row in db:nrows(
			"select coalesce(max(idx), -1) + 1 as next_idx from refs where parent = '" .. frame_pk .. "'"
		) do
			next_idx = row.next_idx
		end
		assert(db:exec(
			"insert into refs (parent, child, key, idx) values ('"
			.. frame_pk .. "', '" .. bucket_pk .. "', null, " .. next_idx .. ")"
		) == 0, db:errmsg())
	end

	-- Step 3: insert or update the rv ref. Uses the same UPSERT pattern
	-- as the propagate-rv trigger.
	local next_idx = 0

	for row in db:nrows(
		"select coalesce(max(idx), -1) + 1 as next_idx from refs where parent = '" .. bucket_pk .. "'"
	) do
		next_idx = row.next_idx
	end

	assert(db:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. value_pk .. "', 'rv', " .. next_idx .. ") "
		.. "on conflict (parent, key) do update set child = excluded.child"
	) == 0, db:errmsg())

	-- Step 4: mark frame_gc=1 so the walker can advance.
	engine.data:mark_frame_gc(frame_pk)

	return true
end

larry:add_handler(BareLiteralHandler.new())

-- ------------------------------------------------------------
-- Load the source through the (sprint's) transpiler. Previously
-- the demo bypassed load() and hand-crafted the CaspM because bare
-- `'foo'` didn't parse. The sprint's transpiler adds an
-- expression-fallback, so this now works via the normal path.
-- ------------------------------------------------------------

local SOURCE = "'foo'"
larry:load(SOURCE)

print('==================================================')
print('source (via sprint transpiler)')
print('==================================================')
print(SOURCE)
print()

-- ------------------------------------------------------------
-- Run.
-- ------------------------------------------------------------

print('==================================================')
print('running')
print('==================================================')
local result = larry:run()
print('run returned: complete=' .. tostring(result.complete)
	.. '  cap_pk=' .. tostring(result.cap_pk):sub(1, 8))
print()

-- ------------------------------------------------------------
-- Verify: cap's rv should be String("foo").
-- ------------------------------------------------------------

print('==================================================')
print('cap state after run')
print('==================================================')

local cap_pk = result.cap_pk

-- Look up cap's bucket.
local cap_bucket_pk
for row in larry.cvm:nrows(
	"select r.child from refs r "
	.. "join objects h on h.object_pk = r.child and h.base = 'h' "
	.. "where r.parent = '" .. cap_pk .. "'"
) do
	cap_bucket_pk = row.child
end

print('cap bucket exists?  ' .. (cap_bucket_pk and ('YES  pk=' .. cap_bucket_pk:sub(1, 8)) or 'no'))

if not cap_bucket_pk then
	print('RESULT: FAIL — cap has no bucket')
	os.exit(1)
end

-- Look up cap's rv value.
local cap_rv_pk
for row in larry.cvm:nrows(
	"select child from refs where parent = '" .. cap_bucket_pk
	.. "' and key = 'rv'"
) do
	cap_rv_pk = row.child
end

print('cap rv ref exists?  ' .. (cap_rv_pk and ('YES  pk=' .. cap_rv_pk:sub(1, 8)) or 'no'))

if not cap_rv_pk then
	print('RESULT: FAIL — cap has no rv ref')
	os.exit(1)
end

-- Read the rv value's scalar_string.
local rv_string
for row in larry.cvm:nrows(
	"select scalar_string from objects where object_pk = '" .. cap_rv_pk .. "'"
) do
	rv_string = row.scalar_string
end

print("cap rv value        =  " .. tostring(rv_string and ("'" .. rv_string .. "'") or 'nil'))
print()

if rv_string == 'foo' then
	print("RESULT: PASS — cap's rv = 'foo' as expected")
else
	print("RESULT: FAIL — expected 'foo', got " .. tostring(rv_string))
	os.exit(1)
end
