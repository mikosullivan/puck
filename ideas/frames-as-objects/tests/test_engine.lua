-- Tests for ideas/frames-as-objects/src/engine.lua
--
-- Run from the repo root:
--     lua5.4 ideas/frames-as-objects/tests/test_engine.lua
--
-- Each test loads the CVM schema into an in-memory SQLite, constructs
-- an engine bound to that handle, exercises the method under test,
-- and asserts on the result.

package.path  = "/home/miko/.luarocks/share/lua/5.4/?.lua;./ideas/frames-as-objects/src/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite = require("lsqlite3")
local engine = require("engine")

local SCHEMA_PATH = "ideas/frames-as-objects/src/cvm.sql"

local function slurp(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local text = f:read("*a")
	f:close()
	return text
end

local function fresh_db()
	local db = sqlite.open_memory()
	db:exec("pragma foreign_keys = on;")
	db:exec("pragma recursive_triggers = on;")

	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, "schema apply failed: " .. tostring(db:errmsg()))

	return db
end

-- Find and return the user seed's object_pk on the given handle.
local function user_pk(db)
	local pk

	for row in db:nrows("select object_pk from objects where user") do
		pk = row.object_pk
	end

	return pk
end

-- Insert a plain non-role object owned by the user seed. Returns its
-- object_pk. The tests use this as the target for add_bucket, since
-- add_bucket on the user seed itself would produce a bucket with
-- owner_role=null (grandfathered) and get rejected by the XOR trigger.
local function insert_target(db, user)
	local pk

	local sql = string.format(
		"insert into objects (primitive, owner_role) values ('o', '%s') returning object_pk",
		user
	)

	for row in db:nrows(sql) do
		pk = row.object_pk
	end

	return pk
end

local pass_count, fail_count = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = pcall(fn)

	if ok then
		pass_count = pass_count + 1
		print("  PASS " .. name)
	else
		fail_count = fail_count + 1
		table.insert(failures, {name = name, err = err})
		print("  FAIL " .. name)
		print("       " .. tostring(err))
	end
end

local function assert_eq(actual, expected, msg)
	if actual == expected then return end
	error((msg or "not equal") .. "\n  actual:   " .. tostring(actual) .. "\n  expected: " .. tostring(expected), 2)
end

local function assert_nil(actual, msg)
	if actual == nil then return end
	error((msg or "expected nil") .. "\n  actual: " .. tostring(actual), 2)
end

local function assert_not_nil(actual, msg)
	if actual ~= nil then return end
	error((msg or "expected non-nil"), 2)
end

print("test_engine.lua — engine class tests")
print("--------------------------------------------------------")

-- ==============================================================
-- engine.new
-- ==============================================================

test("engine.new returns an engine bound to the given db", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e, "engine returned")
	assert_eq(e.db, db, "engine.db is the passed handle")

	db:close()
end)

test("engine.new produces independent instances", function()
	local db1 = fresh_db()
	local db2 = fresh_db()
	local e1 = engine.new(db1)
	local e2 = engine.new(db2)

	-- Populate e1's cache via a call; e2's cache should be untouched.
	e1:object_by_pk("nope")
	assert_not_nil(e1.stmt_object_by_pk, "e1 has cached statement")
	assert_nil(e2.stmt_object_by_pk, "e2 cache is independent")

	db1:close()
	db2:close()
end)

-- ==============================================================
-- engine:object_by_pk
-- ==============================================================

test("object_by_pk returns nil for a missing pk", function()
	local db = fresh_db()
	local e = engine.new(db)

	local obj = e:object_by_pk("00000000-0000-0000-0000-000000000000")

	assert_nil(obj, "no row → nil return")

	db:close()
end)

test("object_by_pk returns an object with the row's columns for an existing pk", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local obj = e:object_by_pk(user)

	assert_not_nil(obj, "object returned")
	assert_eq(obj.object_pk, user, "object_pk column lifted onto self")
	assert_eq(obj.primitive, "h", "user seed primitive is 'h'")
	assert_eq(obj.user, 1, "user seed's user column is 1")

	db:close()
end)

test("object_by_pk lazily caches its prepared statement", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_nil(e.stmt_object_by_pk, "no cache before first call")

	e:object_by_pk("nope")

	assert_not_nil(e.stmt_object_by_pk, "cache populated after first call")

	db:close()
end)

test("object_by_pk reuses the same prepared statement across calls", function()
	local db = fresh_db()
	local e = engine.new(db)

	e:object_by_pk("first")
	local stmt_ref = e.stmt_object_by_pk

	e:object_by_pk("second")

	assert_eq(e.stmt_object_by_pk, stmt_ref, "handle identity preserved")

	db:close()
end)

test("object_by_pk carries a reference to its engine on the returned object", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local obj = e:object_by_pk(user)

	assert_eq(obj.engine, e, "obj.engine points at the engine that loaded it")

	db:close()
end)

-- ==============================================================
-- engine:add_bucket
-- ==============================================================

test("add_bucket creates a HashPrimitive row with bucket_for pointing at the target", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local bucket_pk = e:add_bucket(target)

	assert_not_nil(bucket_pk, "returned pk")

	-- The new bucket exists and has bucket_for = target.
	local primitive, bucket_for
	local sql = string.format(
		"select primitive, bucket_for from objects where object_pk = '%s'",
		bucket_pk
	)

	for row in db:nrows(sql) do
		primitive = row.primitive
		bucket_for = row.bucket_for
	end

	assert_eq(primitive, "h", "new bucket is a HashPrimitive")
	assert_eq(bucket_for, target, "bucket_for points at the target")

	db:close()
end)

test("add_bucket derives the new bucket's owner_role from the target", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local bucket_pk = e:add_bucket(target)

	local bucket_owner
	local sql = string.format(
		"select owner_role from objects where object_pk = '%s'",
		bucket_pk
	)

	for row in db:nrows(sql) do
		bucket_owner = row.owner_role
	end

	assert_eq(bucket_owner, user, "bucket inherits target's owner_role")

	db:close()
end)

test("add_bucket triggers denormalization of the target's bucket_pk", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local bucket_pk = e:add_bucket(target)

	local denormalized
	local sql = string.format(
		"select bucket_pk from objects where object_pk = '%s'",
		target
	)

	for row in db:nrows(sql) do
		denormalized = row.bucket_pk
	end

	assert_eq(denormalized, bucket_pk, "target.bucket_pk = new bucket's object_pk")

	db:close()
end)

test("add_bucket returns the new bucket's own object_pk", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local returned = e:add_bucket(target)

	-- Cross-check: the row with bucket_for=target has object_pk equal to what was returned.
	local via_query
	local sql = string.format(
		"select object_pk from objects where bucket_for = '%s'",
		target
	)

	for row in db:nrows(sql) do
		via_query = row.object_pk
	end

	assert_eq(returned, via_query, "returned pk matches the row's object_pk")

	db:close()
end)

test("add_bucket lazily caches its prepared statement", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	assert_nil(e.stmt_add_bucket, "no cache before first call")

	e:add_bucket(target)

	assert_not_nil(e.stmt_add_bucket, "cache populated after first call")

	db:close()
end)

test("add_bucket reuses the same prepared statement across calls", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local t1 = insert_target(db, user)
	local t2 = insert_target(db, user)

	e:add_bucket(t1)
	local stmt_ref = e.stmt_add_bucket

	e:add_bucket(t2)

	assert_eq(e.stmt_add_bucket, stmt_ref, "handle identity preserved across bucket creations")

	db:close()
end)

-- ==============================================================
-- Summary
-- ==============================================================

print("--------------------------------------------------------")
print(string.format("%d passed, %d failed", pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
end
