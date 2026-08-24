#!/usr/bin/env lua5.4
--[[
Demo: verify the frames_child_delete_propagates_rv trigger works
end-to-end.

Approach: use Larry to get an initialized CVM (schema + core roles).
Then manually construct a parent+child frame scenario:

- Parent frame with a bucket.
- Child frame with a bucket containing an rv ref → Number(42).
- DELETE the child frame.
- Verify parent's bucket now has an rv ref → Number(42).

The manual construction bypasses the walker; we're testing the
trigger in isolation, not a whole run through the engine.

Also demonstrates the "child had no rv" case:

- Parent frame with a bucket that already has rv → Number(1).
- Child frame with a bucket but no rv ref.
- DELETE the child frame.
- Verify parent's rv ref is now GONE (implicitly null).

Invoke:

	lua5.4 sprints/expressions/src/propagate-rv-demo.lua
]]

local script_dir = arg[0]:match('^(.*)/') or '.'
local repo_root  = script_dir .. '/../../..'
local home       = os.getenv('HOME') or ''

package.path = repo_root .. '/production/src/engine/?.lua;'
	.. repo_root .. '/production/src/engine/?/init.lua;'
	.. repo_root .. '/production/tests/main/lua/engine/?.lua;'
	.. repo_root .. '/sprints/expressions/src/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local Larry = require('larry')

-- Bootstrap: Larry with the sprint's schema (which includes
-- frames_child_delete_propagates_rv). Grab a user role for
-- owner_role FK requirements, and set up a cap frame so
-- current_process_pk() returns something (needed by column
-- defaults that reference it).
local SPRINT_SCHEMA = repo_root .. '/sprints/expressions/src/schema.sql'
local larry = Larry.new({cvm = {schema_path = SPRINT_SCHEMA}})

-- Find the user role's pk (seeded by schema).
local user_pk
for row in larry.cvm:nrows("select object_pk from objects where control = 'r' and role_core = 'u'") do
	user_pk = row.object_pk
end

-- Insert a cap frame so needs_trace / debug_log defaults have something to bind to.
local cap_pk
for row in larry.cvm:nrows(
	"insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) "
	.. "values ('o', 'f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"
) do
	cap_pk = row.object_pk
end
larry.cap_pk = cap_pk

-- Helper: insert an objects row with just the required fields for a hash.
local function insert_hash()
	for row in larry.cvm:nrows(
		"insert into objects (base, owner_role) values ('h', '" .. user_pk
		.. "') returning object_pk"
	) do
		return row.object_pk
	end
end

-- Helper: insert an objects row that's a Number(n).
local function insert_number(n)
	for row in larry.cvm:nrows(
		"insert into objects (base, scalar_number, owner_role) values ('o', "
		.. n .. ", '" .. user_pk .. "') returning object_pk"
	) do
		return row.object_pk
	end
end

-- Helper: insert a nested frame under a parent. The frame_ast defaults to
-- '[[{"placeholder":true}]]' — one dummy statement so the frame is NOT at
-- terminal, which matters when we want to insert a child under this
-- frame (rule 9: no child under a terminal parent, cap-exempt).
local function insert_frame(parent_pk, frame_ast)
	frame_ast = frame_ast or '[[{"placeholder":true}]]'
	for row in larry.cvm:nrows(
		"insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) "
		.. "values ('o', 'f', '" .. frame_ast .. "', 0, '" .. parent_pk
		.. "', '" .. user_pk .. "') returning object_pk"
	) do
		return row.object_pk
	end
end

-- Helper: insert a ref from parent's bucket → child, key=key, idx=auto (max+1).
local function add_bucket_ref(bucket_pk, child_pk, key)
	local next_idx = 0
	for row in larry.cvm:nrows(
		"select coalesce(max(idx), -1) + 1 as next_idx from refs where parent = '" .. bucket_pk .. "'"
	) do
		next_idx = row.next_idx
	end
	assert(larry.cvm:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. child_pk .. "', '" .. key .. "', " .. next_idx .. ")"
	) == 0, larry.cvm:errmsg())
end

-- Helper: give a frame its own bucket (returns bucket pk).
local function give_frame_a_bucket(frame_pk)
	local bucket_pk = insert_hash()
	-- ref frame → bucket (key=null; ownership pattern from the schema).
	local next_idx = 0
	for row in larry.cvm:nrows(
		"select coalesce(max(idx), -1) + 1 as next_idx from refs where parent = '" .. frame_pk .. "'"
	) do
		next_idx = row.next_idx
	end
	assert(larry.cvm:exec(
		"insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', null, " .. next_idx .. ")"
	) == 0, larry.cvm:errmsg())
	return bucket_pk
end

-- Helper: get parent's current rv (or nil).
local function get_rv(frame_pk)
	local value_pk
	for row in larry.cvm:nrows(
		"select r2.child as value_pk "
		.. "from refs r1 "
		.. "join objects h on h.object_pk = r1.child and h.base = 'h' "
		.. "join refs r2 on r2.parent = r1.child and r2.key = 'rv' "
		.. "where r1.parent = '" .. frame_pk .. "'"
	) do
		value_pk = row.value_pk
	end
	return value_pk
end

-- Helper: get a scalar Number's value.
local function get_number(pk)
	for row in larry.cvm:nrows(
		"select scalar_number from objects where object_pk = '" .. pk .. "'"
	) do
		return row.scalar_number
	end
end

-- ------------------------------------------------------------
-- Scenario 1: child has rv → parent gets it.
-- ------------------------------------------------------------
print('==================================================')
print('scenario 1: child has rv → parent gets it')
print('==================================================')

local parent1        = insert_frame(cap_pk)
local parent1_bucket = give_frame_a_bucket(parent1)

local child1         = insert_frame(parent1)
local child1_bucket  = give_frame_a_bucket(child1)
local child1_rv      = insert_number(42)
add_bucket_ref(child1_bucket, child1_rv, 'rv')

print('  before: parent rv = ' .. tostring(get_rv(parent1)))
print('  before: child rv  = ' .. tostring(get_rv(child1)) .. ' (Number ' .. get_number(get_rv(child1)) .. ')')
print('  deleting child ...')

assert(larry.cvm:exec("delete from objects where object_pk = '" .. child1 .. "'") == 0,
	larry.cvm:errmsg())

local parent1_rv_after = get_rv(parent1)

if parent1_rv_after then
	local val = get_number(parent1_rv_after)
	print('  after:  parent rv = ' .. tostring(parent1_rv_after))
	print('          parent rv value = Number(' .. tostring(val) .. ')')
	print('  RESULT: ' .. (val == 42 and 'PASS' or 'FAIL — expected 42') .. ' — trigger propagated rv correctly')
else
	print('  after:  parent rv = nil')
	print('  RESULT: FAIL — expected propagation, got nothing')
end
print()

-- Reap parent1 before scenario 2 — otherwise it's still a child of
-- the cap and blocks parent2's insert via the one-child-per-frame
-- unique index. Parent1 has no children (child1 already reaped) so
-- rule 8 (frames_delete_requires_no_child) permits.
assert(larry.cvm:exec("delete from objects where object_pk = '" .. parent1 .. "'") == 0,
	larry.cvm:errmsg())

-- ------------------------------------------------------------
-- Scenario 2: child has no rv → parent's rv gets cleared.
-- ------------------------------------------------------------
print('==================================================')
print('scenario 2: child has no rv → parent rv → null (absent)')
print('==================================================')

local parent2        = insert_frame(cap_pk)
local parent2_bucket = give_frame_a_bucket(parent2)
local parent2_rv     = insert_number(1)
add_bucket_ref(parent2_bucket, parent2_rv, 'rv')

local child2         = insert_frame(parent2)
local child2_bucket  = give_frame_a_bucket(child2)
-- No rv ref on child2's bucket.

print('  before: parent rv = ' .. tostring(get_rv(parent2)) .. ' (Number ' .. get_number(get_rv(parent2)) .. ')')
print('  before: child rv  = ' .. tostring(get_rv(child2)))
print('  deleting child ...')

assert(larry.cvm:exec("delete from objects where object_pk = '" .. child2 .. "'") == 0,
	larry.cvm:errmsg())

local parent2_rv_after = get_rv(parent2)

if parent2_rv_after == nil then
	print('  after:  parent rv = nil')
	print('  RESULT: PASS — parent rv cleared (implicitly null) as expected')
else
	print('  after:  parent rv = ' .. parent2_rv_after)
	print('  RESULT: FAIL — expected parent rv to be cleared')
end
print()

-- Reap parent2 before scenario 3.
assert(larry.cvm:exec("delete from objects where object_pk = '" .. parent2 .. "'") == 0,
	larry.cvm:errmsg())

-- ------------------------------------------------------------
-- Scenario 3: child has NO bucket at all → parent's rv gets cleared.
--
-- Distinct from scenario 2 (where child had a bucket but no rv ref).
-- Here the child frame was never touched by any handler that would
-- have materialized its bucket — it's a bare frame with just a
-- frame_ast, nothing else.
-- ------------------------------------------------------------
print('==================================================')
print('scenario 3: child has NO bucket → parent rv → null')
print('==================================================')

local parent3        = insert_frame(cap_pk)
local parent3_bucket = give_frame_a_bucket(parent3)
local parent3_rv     = insert_number(7)
add_bucket_ref(parent3_bucket, parent3_rv, 'rv')

local child3 = insert_frame(parent3)
-- No bucket at all on child3.

print('  before: parent rv = ' .. tostring(get_rv(parent3)) .. ' (Number ' .. get_number(get_rv(parent3)) .. ')')
print('  before: child has no bucket at all')
print('  deleting child ...')

assert(larry.cvm:exec("delete from objects where object_pk = '" .. child3 .. "'") == 0,
	larry.cvm:errmsg())

local parent3_rv_after = get_rv(parent3)

if parent3_rv_after == nil then
	print('  after:  parent rv = nil')
	print('  RESULT: PASS — parent rv cleared even with bucket-less child')
else
	print('  after:  parent rv = ' .. parent3_rv_after)
	print('  RESULT: FAIL — expected parent rv to be cleared')
end
print()

-- Reap parent3 before scenario 4.
assert(larry.cvm:exec("delete from objects where object_pk = '" .. parent3 .. "'") == 0,
	larry.cvm:errmsg())

-- ------------------------------------------------------------
-- Scenario 4: UPDATE hot path — parent already had rv X; child
-- has rv Y; parent's rv REF should get its child updated in place
-- (not delete-then-insert). This exercises the ON CONFLICT DO
-- UPDATE branch of the optimized trigger.
-- ------------------------------------------------------------
print('==================================================')
print('scenario 4: UPDATE hot path — parent had A, child has B')
print('==================================================')

local parent4        = insert_frame(cap_pk)
local parent4_bucket = give_frame_a_bucket(parent4)
local parent4_rv_old = insert_number(100)
add_bucket_ref(parent4_bucket, parent4_rv_old, 'rv')

-- Grab parent's rv ref_pk BEFORE the delete — if the trigger
-- correctly UPDATES in place, this ref_pk stays valid. If it
-- DELETE+INSERTs, we'd see a new ref_pk.
local ref_pk_before
for row in larry.cvm:nrows(
	"select ref_pk from refs where parent = '" .. parent4_bucket
	.. "' and key = 'rv'"
) do
	ref_pk_before = row.ref_pk
end

local child4         = insert_frame(parent4)
local child4_bucket  = give_frame_a_bucket(child4)
local child4_rv      = insert_number(200)
add_bucket_ref(child4_bucket, child4_rv, 'rv')

print('  before: parent rv = Number(100), rv ref_pk=' .. tostring(ref_pk_before))
print('  before: child  rv = Number(200)')
print('  deleting child ...')

assert(larry.cvm:exec("delete from objects where object_pk = '" .. child4 .. "'") == 0,
	larry.cvm:errmsg())

local parent4_rv_after = get_rv(parent4)
local ref_pk_after
for row in larry.cvm:nrows(
	"select ref_pk from refs where parent = '" .. parent4_bucket
	.. "' and key = 'rv'"
) do
	ref_pk_after = row.ref_pk
end

local val_after = parent4_rv_after and get_number(parent4_rv_after) or nil
print('  after:  parent rv = Number(' .. tostring(val_after) .. '), rv ref_pk=' .. tostring(ref_pk_after))

local value_ok  = val_after == 200
local ref_ok    = ref_pk_before == ref_pk_after
local result    = value_ok and ref_ok
print('  RESULT: ' .. (result and 'PASS' or 'FAIL')
	.. ' — value updated to 200: ' .. tostring(value_ok)
	.. '; ref_pk preserved (UPDATE not DELETE+INSERT): ' .. tostring(ref_ok))
print()

-- Reap parent4 before scenario 5.
assert(larry.cvm:exec("delete from objects where object_pk = '" .. parent4 .. "'") == 0,
	larry.cvm:errmsg())

-- ------------------------------------------------------------
-- Scenario 5: multi-hop chain — rv propagates all the way to the
-- process cap.
--
-- Chain: cap → frame_A → frame_B, with rv on frame_B.
--
-- - Reap frame_B  → frame_A's rv gets Number(999).
-- - Reap frame_A  → cap's rv gets Number(999).
--
-- The cap is NOT given a bucket manually — statements 1a/1b of the
-- trigger materialize it on demand at hop 2.
-- ------------------------------------------------------------
print('==================================================')
print('scenario 5: multi-hop — rv propagates up to the cap')
print('==================================================')

local frame_A         = insert_frame(cap_pk)
local frame_A_bucket  = give_frame_a_bucket(frame_A)

local frame_B         = insert_frame(frame_A)
local frame_B_bucket  = give_frame_a_bucket(frame_B)
local frame_B_rv      = insert_number(999)
add_bucket_ref(frame_B_bucket, frame_B_rv, 'rv')

print('  before: cap rv     = ' .. tostring(get_rv(cap_pk)))
print('  before: frame_A rv = ' .. tostring(get_rv(frame_A)))
print('  before: frame_B rv = Number(' .. get_number(frame_B_rv) .. ')')

-- Hop 1: reap frame_B; frame_A should receive rv.
print('  hop 1: reaping frame_B ...')
assert(larry.cvm:exec("delete from objects where object_pk = '" .. frame_B .. "'") == 0,
	larry.cvm:errmsg())

local a_rv_after_hop1 = get_rv(frame_A)
local a_val_after_hop1 = a_rv_after_hop1 and get_number(a_rv_after_hop1) or nil
print('         frame_A rv = Number(' .. tostring(a_val_after_hop1) .. ')')

-- Hop 2: reap frame_A; cap should receive rv.
print('  hop 2: reaping frame_A ...')
assert(larry.cvm:exec("delete from objects where object_pk = '" .. frame_A .. "'") == 0,
	larry.cvm:errmsg())

local cap_rv_after_hop2 = get_rv(cap_pk)
local cap_val_after_hop2 = cap_rv_after_hop2 and get_number(cap_rv_after_hop2) or nil
print('         cap rv     = Number(' .. tostring(cap_val_after_hop2) .. ')')

local hop1_ok = a_val_after_hop1 == 999
local hop2_ok = cap_val_after_hop2 == 999
local both    = hop1_ok and hop2_ok

print('  RESULT: ' .. (both and 'PASS' or 'FAIL')
	.. ' — hop1 (B → A): ' .. tostring(hop1_ok)
	.. '; hop2 (A → cap): ' .. tostring(hop2_ok))
