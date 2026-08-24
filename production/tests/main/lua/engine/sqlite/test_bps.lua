#!/usr/bin/env lua5.4

--[[
{
	"module": "test_bps",
	"role": "Schema tests for the b/p/s object-property shape landed by the object sprint. Loads production schema + preflight into a fresh in-memory SQLite, then walks each invariant with a positive case (accept) and a negative case (raise, expected trigger name in the error string). Ported from sprints/object/src/test_bps.lua at object-sprint integration; adapted to use the shared helpers.test harness.",
	"invariants_covered": [
		"key='b' from 'o'-parent → target must be base='h' (bucket is a hash)",
		"key='p' from 'o'-parent → target must be base='a' (platters is an array)",
		"key='s' from 'o'-parent → target must be base='h' (shadow is a hash)",
		"refs from 'o'-parent — key must be in {b, p, s} (no null, no other value)",
		"unique(parent, key) caps each of b/p/s at one per parent",
		"bucket and shadow can coexist on the same parent (two 'h'-based targets, distinguished by key)",
		"container-parent rules survive: 'h'-parent still requires non-null key; 'a'-parent still forbids key",
		"object_bucket / object_platters / object_shadow views return the right slots"
	]
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. package.path

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')
local h                  = require('helpers')
local test               = h.test

local SCHEMA_PATH    = 'production/src/engine/cvm/sqlite/schema.sql'
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

	assert(db:exec(slurp(SCHEMA_PATH))    == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	assert(db:exec(slurp(PREFLIGHT_PATH)) == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))

	return db
end

local function seed_user_pk(db)
	for row in db:nrows("select object_pk from objects where role_core = 'u'") do
		return row.object_pk
	end
	error('user seed missing')
end

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

local function assert_raises(fn, expect_id, msg)
	local ok, err = fn()
	if ok then
		error((msg or 'expected raise') .. ': got accept', 2)
	elseif not err or not err:find(expect_id, 1, true) then
		error((msg or 'expected raise') .. ': expected `' .. expect_id .. '`, got: ' .. tostring(err), 2)
	end
end


-- ============================================================
-- Type-check triggers per key
-- ============================================================

test("refs_key_b_target_must_be_hash: key='b' → hash target accepted", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	local ok, err = try_insert_ref(db, owner, hash, 'b')
	h.assert_true(ok, "key='b' → hash target should be accepted; got: " .. tostring(err))
	db:close()
end)

test("refs_key_b_target_must_be_hash: key='b' → array target rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, array, 'b') end,
		'refs_key_b_target_must_be_hash',
		"key='b' → array target should be rejected")
	db:close()
end)

test("refs_key_p_target_must_be_array: key='p' → array target accepted", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	local ok, err = try_insert_ref(db, owner, array, 'p')
	h.assert_true(ok, "key='p' → array target should be accepted; got: " .. tostring(err))
	db:close()
end)

test("refs_key_p_target_must_be_array: key='p' → hash target rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, hash, 'p') end,
		'refs_key_p_target_must_be_array',
		"key='p' → hash target should be rejected")
	db:close()
end)

test("refs_key_s_target_must_be_hash: key='s' → hash target accepted", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	local ok, err = try_insert_ref(db, owner, hash, 's')
	h.assert_true(ok, "key='s' → hash target should be accepted; got: " .. tostring(err))
	db:close()
end)

test("refs_key_s_target_must_be_hash: key='s' → array target rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local array   = insert_object(db, 'a', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, array, 's') end,
		'refs_key_s_target_must_be_hash',
		"key='s' → array target should be rejected")
	db:close()
end)


-- ============================================================
-- Key allowlist for 'o'-parent refs
-- ============================================================

test("refs_object_parent_key_must_be_bps: non-bps key from 'o'-parent rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, hash, 'z') end,
		'refs_object_parent_key_must_be_bps',
		"key='z' from 'o'-parent should be rejected")
	db:close()
end)

test("refs_object_parent_key_must_be_bps: null key from 'o'-parent rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, hash, nil) end,
		'refs_object_parent_key_must_be_bps',
		"key=null from 'o'-parent should be rejected")
	db:close()
end)

test("refs_object_parent_key_must_be_bps: empty-string key from 'o'-parent rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash    = insert_object(db, 'h', user_pk)

	assert_raises(
		function() return try_insert_ref(db, owner, hash, '') end,
		'refs_object_parent_key_must_be_bps',
		"key='' from 'o'-parent should be rejected")
	db:close()
end)


-- ============================================================
-- Coexistence + uniqueness
-- ============================================================

test("bucket + shadow coexist on the same 'o'-parent (both hashes, different keys)", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local bucket  = insert_object(db, 'h', user_pk)
	local shadow  = insert_object(db, 'h', user_pk)

	local ok, err = try_insert_ref(db, owner, bucket, 'b', 0)
	h.assert_true(ok, 'first hash under key=b: ' .. tostring(err))
	ok, err = try_insert_ref(db, owner, shadow, 's', 1)
	h.assert_true(ok, "second hash under key='s' should coexist: " .. tostring(err))
	db:close()
end)

test("bucket + platters + shadow all coexist on the same 'o'-parent", function()
	local db       = fresh_db()
	local user_pk  = seed_user_pk(db)
	local owner    = insert_object(db, 'o', user_pk)
	local bucket   = insert_object(db, 'h', user_pk)
	local platters = insert_object(db, 'a', user_pk)
	local shadow   = insert_object(db, 'h', user_pk)

	local ok, err = try_insert_ref(db, owner, bucket,   'b', 0)
	h.assert_true(ok, 'key=b: ' .. tostring(err))
	ok, err = try_insert_ref(db, owner, platters, 'p', 1)
	h.assert_true(ok, 'key=p: ' .. tostring(err))
	ok, err = try_insert_ref(db, owner, shadow,   's', 2)
	h.assert_true(ok, 'key=s: ' .. tostring(err))
	db:close()
end)

test("unique(parent, key): second key='b' from same parent rejected", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)
	local hash_a  = insert_object(db, 'h', user_pk)
	local hash_b  = insert_object(db, 'h', user_pk)

	local ok = try_insert_ref(db, owner, hash_a, 'b', 0)
	h.assert_true(ok, 'first hash-b accepted')

	local ok2, err = try_insert_ref(db, owner, hash_b, 'b', 1)
	h.assert_true(not ok2, "second key='b' should be rejected")
	h.assert_true(err and err:lower():find('unique', 1, true) ~= nil,
		'expected uniqueness error, got: ' .. tostring(err))
	db:close()
end)


-- ============================================================
-- Container-parent rules survive
-- ============================================================

test("container 'h'-parent still requires non-null key", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local hash    = insert_object(db, 'h', user_pk)
	local target  = insert_object(db, 'o', user_pk)

	assert_raises(
		function() return try_insert_ref(db, hash, target, nil) end,
		'refs_hash_key_required',
		"'h'-parent + null key should be rejected")
	db:close()
end)

test("container 'h'-parent accepts arbitrary non-null keys", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local hash    = insert_object(db, 'h', user_pk)
	local target  = insert_object(db, 'o', user_pk)

	local ok, err = try_insert_ref(db, hash, target, 'anything')
	h.assert_true(ok, "'h'-parent + arbitrary key: " .. tostring(err))
	db:close()
end)

test("container 'a'-parent still forbids non-null key", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local array   = insert_object(db, 'a', user_pk)
	local target  = insert_object(db, 'o', user_pk)

	assert_raises(
		function() return try_insert_ref(db, array, target, 'nope') end,
		'refs_array_key_forbidden',
		"'a'-parent + non-null key should be rejected")
	db:close()
end)

test("container 'a'-parent accepts null key with idx", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local array   = insert_object(db, 'a', user_pk)
	local target  = insert_object(db, 'o', user_pk)

	local ok, err = try_insert_ref(db, array, target, nil, 0)
	h.assert_true(ok, "'a'-parent + null key + idx: " .. tostring(err))
	db:close()
end)


-- ============================================================
-- Views return the right slots
-- ============================================================

test("object_bucket view returns null before ref exists", function()
	local db      = fresh_db()
	local user_pk = seed_user_pk(db)
	local owner   = insert_object(db, 'o', user_pk)

	for row in db:nrows("select bucket_pk from object_bucket where object_pk = '" .. owner .. "'") do
		h.assert_eq(row.bucket_pk, nil, 'no bucket ref yet')
	end
	db:close()
end)

test("object_bucket / object_platters / object_shadow return the wired slots", function()
	local db       = fresh_db()
	local user_pk  = seed_user_pk(db)
	local owner    = insert_object(db, 'o', user_pk)
	local bucket   = insert_object(db, 'h', user_pk)
	local platters = insert_object(db, 'a', user_pk)
	local shadow   = insert_object(db, 'h', user_pk)

	local function slot(view_name, col)
		for row in db:nrows(
			"select " .. col .. " from " .. view_name
			.. " where object_pk = '" .. owner .. "'"
		) do
			return row[col]
		end
		return nil
	end

	h.assert_true(try_insert_ref(db, owner, bucket,   'b', 0))
	h.assert_true(try_insert_ref(db, owner, platters, 'p', 1))
	h.assert_true(try_insert_ref(db, owner, shadow,   's', 2))

	h.assert_eq(slot('object_bucket',   'bucket_pk'),   bucket,   'object_bucket returns bucket')
	h.assert_eq(slot('object_platters', 'platters_pk'), platters, 'object_platters returns platters')
	h.assert_eq(slot('object_shadow',   'shadow_pk'),   shadow,   'object_shadow returns shadow')
	db:close()
end)
