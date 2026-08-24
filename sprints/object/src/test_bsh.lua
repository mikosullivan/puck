#!/usr/bin/env lua5.4

--[[
{
	"module": "test_bsh",
	"role": "Schema tests for the sprint's b/s/h object-property shape. Loads the sprint schema (and production preflight) into a fresh in-memory SQLite, then walks through each invariant with a positive case (accept) and a negative case (raise, with the expected trigger name in the error string).",
	"invariants_covered": [
		"key='b' from 'o'-parent → target must be base='h' (bucket is a hash)",
		"key='s' from 'o'-parent → target must be base='a' (stack is an array)",
		"key='h' from 'o'-parent → target must be base='h' (shadow is a hash)",
		"refs from 'o'-parent — key must be in {b, s, h} (no null, no other value)",
		"unique(parent, key) caps each of b/s/h at one per parent",
		"bucket and shadow can coexist on the same parent (two 'h'-based targets, distinguished by key)",
		"container-parent rules survive: 'h'-parent still requires non-null key; 'a'-parent still forbids key",
		"object_bucket / object_stack / object_shadow views return the right slots"
	],
	"invoke": "lua5.4 sprints/object/src/test_bsh.lua",
	"status": "sprint tests"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. package.path

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')

local SCHEMA_PATH    = 'sprints/object/src/schema.sql'
local PREFLIGHT_PATH = 'production/src/engine/cvm/sqlite/preflight.sql'


-- ------------------------------------------------------------
-- Test harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local _process_holders = setmetatable({}, {__mode = 'k'})

local function fresh_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')

	local holder = {pk = nil}
	_process_holders[db] = holder
	current_process_pk.register(db, function() return holder.pk end)

	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	rc = db:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))

	return db
end

local function seed_user_pk(db)
	for row in db:nrows("select object_pk from objects where role_core = 'u'") do
		return row.object_pk
	end
	error('user seed missing')
end

--[[
Insert a fresh row into `objects` and return its pk. All rows go
through here so the tests don't have to hand-write the SQL every
time. Extra columns pass through as (colname, value) pairs.
]]
local function insert_object(db, base, user_pk, extra)
	local cols = {'base', 'owner_role'}
	local vals = {"'" .. base .. "'", "'" .. user_pk .. "'"}

	if extra then
		for k, v in pairs(extra) do
			cols[#cols + 1] = k
			if type(v) == 'string' then
				vals[#vals + 1] = "'" .. v .. "'"
			else
				vals[#vals + 1] = tostring(v)
			end
		end
	end

	local sql = "insert into objects ("
		.. table.concat(cols, ', ')
		.. ") values ("
		.. table.concat(vals, ', ')
		.. ") returning object_pk"

	for row in db:nrows(sql) do
		return row.object_pk
	end

	error('insert_object failed: ' .. tostring(db:errmsg()))
end

--[[
Try an INSERT INTO refs and return (ok, err_string). Uses idx=0 by
default (the tests only care about the key/base pairing).
]]
local function try_insert_ref(db, parent, child, key, idx)
	idx = idx or 0

	local key_sql
	if key == nil then
		key_sql = 'null'
	else
		key_sql = "'" .. key .. "'"
	end

	local sql = "insert into refs (parent, child, key, idx) values ('"
		.. parent .. "', '" .. child .. "', " .. key_sql .. ", " .. idx .. ")"

	local rc = db:exec(sql)
	if rc == sqlite.OK then
		return true, nil
	end

	return false, db:errmsg()
end


-- ------------------------------------------------------------
-- Assertion helpers
-- ------------------------------------------------------------

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(string.format("  \27[32mok\27[0m   %s", label))
end

local function fail(label, why)
	failed = failed + 1
	print(string.format("  \27[31mFAIL\27[0m %s", label))
	print(string.format("       %s", why))
end

local function assert_insert_ok(db, parent, child, key, label)
	local ok, err = try_insert_ref(db, parent, child, key)
	if ok then
		pass(label)
	else
		fail(label, 'expected accept, got error: ' .. tostring(err))
	end
end

local function assert_insert_raises(db, parent, child, key, expect_id, label)
	local ok, err = try_insert_ref(db, parent, child, key)
	if ok then
		fail(label, 'expected error `' .. expect_id .. '`, got accept')
	elseif not err or not err:find(expect_id, 1, true) then
		fail(label, 'expected error containing `' .. expect_id .. '`, got: ' .. tostring(err))
	else
		pass(label)
	end
end


-- ------------------------------------------------------------
-- Test cases
-- ------------------------------------------------------------

print('== b/s/h object-property invariants ==')

do  -- key='b' → target must be base='h'
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	assert_insert_ok(db, owner, hash, 'b', "key='b' → hash target accepted")

	-- Fresh owner for the negative case (unique(parent, key) prevents a second 'b').
	local owner2 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, owner2, array, 'b',
		'refs_key_b_target_must_be_hash', "key='b' → array target rejected")
end

do  -- key='s' → target must be base='a'
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	assert_insert_ok(db, owner, array, 's', "key='s' → array target accepted")

	local owner2 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, owner2, hash, 's',
		'refs_key_s_target_must_be_array', "key='s' → hash target rejected")
end

do  -- key='h' → target must be base='h'
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	assert_insert_ok(db, owner, hash, 'h', "key='h' → hash target accepted")

	local owner2 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, owner2, array, 'h',
		'refs_key_h_target_must_be_hash', "key='h' → array target rejected")
end

do  -- 'o'-parent refs must use key in {b, s, h}
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	assert_insert_raises(db, owner, hash, 'z',
		'refs_object_parent_key_must_be_bsh', "key='z' from 'o'-parent rejected")

	local owner2 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, owner2, hash, nil,
		'refs_object_parent_key_must_be_bsh', "key=null from 'o'-parent rejected")

	local owner3 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, owner3, hash, '',
		'refs_object_parent_key_must_be_bsh', "key='' from 'o'-parent rejected")
end

do  -- b and h coexist on the same parent (both hashes, different keys)
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local bucket  = insert_object(db, 'h', user_pk)
	local shadow  = insert_object(db, 'h', user_pk)

	-- Distinct idx values because unique(parent, idx) applies too.
	local function ok_at(child, key, idx, label)
		local ok, err = try_insert_ref(db, owner, child, key, idx)
		if ok then pass(label) else fail(label, 'got: ' .. tostring(err)) end
	end

	ok_at(bucket, 'b', 0, "bucket (key='b') accepted first")
	ok_at(shadow, 'h', 1, "shadow (key='h') accepted alongside bucket")

	-- Full house: add a stack too
	local stack = insert_object(db, 'a', user_pk)
	ok_at(stack, 's', 2, "stack (key='s') accepted alongside b + h")
end

do  -- unique(parent, key) caps each slot at one
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash_a  = insert_object(db, 'h', user_pk)
	local hash_b  = insert_object(db, 'h', user_pk)

	assert_insert_ok(db, owner, hash_a, 'b', "first key='b' accepted")

	-- Second key='b' from the same parent → uniqueness violation (well-formed target)
	local ok, err = try_insert_ref(db, owner, hash_b, 'b', 1)
	if ok then
		fail("second key='b' from same parent rejected",
			'expected uniqueness error, got accept')
	elseif not err or not err:lower():find('unique', 1, true) then
		fail("second key='b' from same parent rejected",
			'expected uniqueness error, got: ' .. tostring(err))
	else
		pass("second key='b' from same parent rejected (unique(parent, key))")
	end
end

do  -- Container-parent rules survive
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local hash    = insert_object(db, 'h', user_pk)
	local array   = insert_object(db, 'a', user_pk)
	local target  = insert_object(db, 'o', user_pk)

	-- Hash parent: null key rejected by refs_hash_key_required
	assert_insert_raises(db, hash, target, nil,
		'refs_hash_key_required', "hash-parent still requires non-null key")

	-- Hash parent: non-null key accepted (any key, not just b/s/h)
	assert_insert_ok(db, hash, target, 'anything', "hash-parent accepts any non-null key")

	-- Array parent: non-null key rejected by refs_array_key_forbidden
	local target2 = insert_object(db, 'o', user_pk)
	assert_insert_raises(db, array, target2, 'nope',
		'refs_array_key_forbidden', "array-parent still forbids non-null key")

	-- Array parent: null key accepted (idx-only)
	local target3 = insert_object(db, 'o', user_pk)
	local ok, err = try_insert_ref(db, array, target3, nil, 0)
	if ok then
		pass("array-parent accepts null key with idx")
	else
		fail("array-parent accepts null key with idx", 'got: ' .. tostring(err))
	end
end

do  -- Views return the right slots
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local bucket  = insert_object(db, 'h', user_pk)
	local stack   = insert_object(db, 'a', user_pk)
	local shadow  = insert_object(db, 'h', user_pk)

	local function slot(view_name, col)
		for row in db:nrows(
			"select " .. col .. " from " .. view_name
			.. " where object_pk = '" .. owner .. "'"
		) do
			return row[col]
		end
		return nil
	end

	-- Before any refs are added, each view returns null for this owner.
	if slot('object_bucket', 'bucket_pk') == nil then
		pass("object_bucket returns null before ref exists")
	else
		fail("object_bucket returns null before ref exists",
			'got: ' .. tostring(slot('object_bucket', 'bucket_pk')))
	end

	-- Wire up all three refs
	assert(try_insert_ref(db, owner, bucket, 'b', 0))
	assert(try_insert_ref(db, owner, stack,  's', 1))
	assert(try_insert_ref(db, owner, shadow, 'h', 2))

	if slot('object_bucket', 'bucket_pk') == bucket then
		pass("object_bucket returns bucket after ref added")
	else
		fail("object_bucket returns bucket after ref added",
			'got: ' .. tostring(slot('object_bucket', 'bucket_pk')))
	end

	if slot('object_stack', 'stack_pk') == stack then
		pass("object_stack returns stack after ref added")
	else
		fail("object_stack returns stack after ref added",
			'got: ' .. tostring(slot('object_stack', 'stack_pk')))
	end

	if slot('object_shadow', 'shadow_pk') == shadow then
		pass("object_shadow returns shadow after ref added")
	else
		fail("object_shadow returns shadow after ref added",
			'got: ' .. tostring(slot('object_shadow', 'shadow_pk')))
	end
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format('  %d passed, %d failed', passed, failed))

if failed > 0 then
	os.exit(1)
end
