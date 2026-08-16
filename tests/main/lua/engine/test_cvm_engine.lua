--[[
{
	"spec": "test_cvm_engine",
	"role": "Tests for `src/engine/cvm/init.lua` (the CVM's data-access layer, required as `require('cvm')`) plus the wrapper classes at `src/engine/cvm/object.lua` and `src/engine/cvm/frame.lua`. Covers `cvm.new`, `object_by_pk`, `frame_by_pk`, the `add_*` family (`add_bucket` / `add_stack` / `add_scalar` / `add_hash` / `add_array` / `add_frame` / `add_ref`), `get_ref_child`, and the accessors on `object` / `frame` wrappers (`bucket`, `stack`, `locals`, `ensure_locals`, `set_local_to_scalar`).",
	"run": "lua5.4 tests/main/lua/engine/run.lua (from repo root)"
}
]]

--[[
# `test_cvm_engine`

End-to-end tests for the CVM data-access layer. Each case loads
`src/engine/cvm/schema.sql` into a fresh in-memory SQLite via the
local `fresh_db` helper, constructs a `cvm` bound to that handle,
exercises the method under test, and asserts on the resulting row or
wrapper.

The runner (`tests/main/lua/engine/run.lua`) sets `package.path` so
that `require('cvm')`, `require('cvm.object')`, and
`require('cvm.frame')` resolve to `src/engine/cvm/*.lua`. Running
this file standalone requires the same `package.path` prefix.
]]

local sqlite = require("lsqlite3")
local engine = require("cvm")

local SCHEMA_PATH = "src/engine/cvm/schema.sql"

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

	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
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

local h = require('helpers')
local test           = h.test
local assert_eq      = h.assert_eq
local assert_nil     = h.assert_nil
local assert_not_nil = h.assert_not_nil

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

	-- Both instances have every statement prepped at construction;
	-- the important property is that the two engines own distinct handles.
	assert_not_nil(e1.stmt_object_by_pk, "e1 has cached statement")
	assert_not_nil(e2.stmt_object_by_pk, "e2 has cached statement")
	assert(e1.stmt_object_by_pk ~= e2.stmt_object_by_pk, "instances have distinct statement handles")

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
	assert_eq(obj.core_role, "u", "user seed's core_role column is 'u'")

	db:close()
end)

test("object_by_pk's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	-- No call needed — engine.new prepped it upfront.
	assert_not_nil(e.stmt_object_by_pk, "cache populated at construction")

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
-- object_by_pk class dispatch (frame vs plain object)
-- ==============================================================

-- Insert a frame-shaped row (primitive = 'f' with `ast`, owned by
-- user). Uses a detached shape — process / idx / stmt_idx are null,
-- which is legal (a frame that isn't currently on any stack). Tests
-- that need an on-stack frame set those columns explicitly.
local function insert_frame(db, user)
	local pk

	local sql = string.format(
		"insert into objects (primitive, ast, owner_role) values ('f', '[[]]', '%s') returning object_pk",
		user
	)

	for row in db:nrows(sql) do
		pk = row.object_pk
	end

	return pk
end

test("object_by_pk dispatches a primitive='f' row to the frame class", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)

	local obj = e:object_by_pk(frame_pk)

	assert_not_nil(obj, "row returned")
	assert_eq(type(obj.locals), "function", "frame's :locals method is on the wrapper")

	db:close()
end)

test("object_by_pk wraps non-'f' primitive rows as plain objects", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local plain_pk = insert_target(db, user)

	local obj = e:object_by_pk(plain_pk)

	assert_not_nil(obj, "row returned")
	assert_nil(obj.locals, "plain object doesn't have :locals")

	db:close()
end)

test("frame wrapper inherits :bucket from the object class", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)

	local obj = e:object_by_pk(frame_pk)

	assert_eq(type(obj.bucket), "function", "inherited :bucket resolves on the frame wrapper")

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

test("add_bucket's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_bucket, "cache populated at construction")

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
-- engine:add_stack
-- ==============================================================

test("add_stack creates an ArrayPrimitive row with stack_for pointing at the target", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local stack_pk = e:add_stack(target)

	assert_not_nil(stack_pk, "returned pk")

	local primitive, stack_for
	local sql = string.format(
		"select primitive, stack_for from objects where object_pk = '%s'",
		stack_pk
	)

	for row in db:nrows(sql) do
		primitive = row.primitive
		stack_for = row.stack_for
	end

	assert_eq(primitive, "a", "new stack is an ArrayPrimitive")
	assert_eq(stack_for, target, "stack_for points at the target")

	db:close()
end)

test("add_stack derives the new stack's owner_role from the target", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local stack_pk = e:add_stack(target)

	local stack_owner
	local sql = string.format(
		"select owner_role from objects where object_pk = '%s'",
		stack_pk
	)

	for row in db:nrows(sql) do
		stack_owner = row.owner_role
	end

	assert_eq(stack_owner, user, "stack inherits target's owner_role")

	db:close()
end)

test("add_stack triggers denormalization of the target's stack_pk", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)

	local stack_pk = e:add_stack(target)

	local denormalized
	local sql = string.format(
		"select stack_pk from objects where object_pk = '%s'",
		target
	)

	for row in db:nrows(sql) do
		denormalized = row.stack_pk
	end

	assert_eq(denormalized, stack_pk, "target.stack_pk = new stack's object_pk")

	db:close()
end)

test("add_stack's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_stack, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- engine:add_scalar
-- ==============================================================

test("add_scalar writes primitive='o' with the given scalar_type/scalar_value/owner_role", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local pk = e:add_scalar("n", 42, user)

	local row
	local sql = string.format(
		"select primitive, scalar_type, scalar_value, owner_role from objects where object_pk = '%s'",
		pk
	)

	for r in db:nrows(sql) do
		row = r
	end

	assert_not_nil(row, "row exists")
	assert_eq(row.primitive, "o", "primitive is scalar")
	assert_eq(row.scalar_type, "n", "scalar_type set")
	assert_eq(row.scalar_value, 42, "scalar_value set")
	assert_eq(row.owner_role, user, "owner_role set to given role")

	db:close()
end)

test("add_scalar returns the pk of the newly inserted row", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local returned = e:add_scalar("s", "hi", user)

	local via_query
	local sql = string.format(
		"select object_pk from objects where scalar_value = 'hi'"
	)

	for r in db:nrows(sql) do
		via_query = r.object_pk
	end

	assert_eq(returned, via_query, "returned pk matches the row's object_pk")

	db:close()
end)

test("add_scalar's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_scalar, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- engine:add_hash
-- ==============================================================

test("add_hash writes primitive='h' with the given owner_role and no bucket_for", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local pk = e:add_hash(user)

	local row
	local sql = string.format(
		"select primitive, owner_role, bucket_for from objects where object_pk = '%s'",
		pk
	)

	for r in db:nrows(sql) do
		row = r
	end

	assert_not_nil(row, "row exists")
	assert_eq(row.primitive, "h", "primitive is HashPrimitive")
	assert_eq(row.owner_role, user, "owner_role set")
	assert_nil(row.bucket_for, "bucket_for is null — this is a plain hash, not anyone's bucket")

	db:close()
end)

test("add_hash's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_hash, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- engine:add_array
-- ==============================================================

test("add_array writes primitive='a' with the given owner_role and no stack_for", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local pk = e:add_array(user)

	local row
	local sql = string.format(
		"select primitive, owner_role, stack_for, bucket_for from objects where object_pk = '%s'",
		pk
	)

	for r in db:nrows(sql) do
		row = r
	end

	assert_not_nil(row, "row exists")
	assert_eq(row.primitive, "a", "primitive is ArrayPrimitive")
	assert_eq(row.owner_role, user, "owner_role set")
	assert_nil(row.stack_for, "stack_for is null — this is a plain array, not anyone's stack")
	assert_nil(row.bucket_for, "bucket_for is null too — the row is not any kind of container-owner")

	db:close()
end)

test("add_array's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_array, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- engine:add_ref
-- ==============================================================

test("add_ref inserts a row into refs with the given parent, child, and key", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)
	local child = e:add_scalar("n", 7, user)

	local ref_pk = e:add_ref(parent, "x", child)

	assert_not_nil(ref_pk, "returned ref_pk")

	local row
	local sql = string.format(
		"select parent, child, key, idx from refs where ref_pk = %d",
		ref_pk
	)

	for r in db:nrows(sql) do
		row = r
	end

	assert_eq(row.parent, parent, "parent set")
	assert_eq(row.child, child, "child set")
	assert_eq(row.key, "x", "key set")
	assert_eq(row.idx, 0, "first ref for parent gets idx 0")

	db:close()
end)

test("add_ref auto-increments idx per parent", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)
	local c1 = e:add_scalar("n", 1, user)
	local c2 = e:add_scalar("n", 2, user)
	local c3 = e:add_scalar("n", 3, user)

	e:add_ref(parent, "a", c1)
	e:add_ref(parent, "b", c2)
	e:add_ref(parent, "c", c3)

	local idxs = {}
	local sql = string.format(
		"select key, idx from refs where parent = '%s' order by idx",
		parent
	)

	for r in db:nrows(sql) do
		table.insert(idxs, {key = r.key, idx = r.idx})
	end

	assert_eq(idxs[1].key, "a", "first insert stays first")
	assert_eq(idxs[1].idx, 0, "first insert idx=0")
	assert_eq(idxs[2].key, "b", "second insert stays second")
	assert_eq(idxs[2].idx, 1, "second insert idx=1")
	assert_eq(idxs[3].key, "c", "third insert stays third")
	assert_eq(idxs[3].idx, 2, "third insert idx=2")

	db:close()
end)

test("add_ref's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_add_ref, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- engine:get_ref_child
-- ==============================================================

test("get_ref_child returns nil for a missing (parent, key)", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)

	local child_pk = e:get_ref_child(parent, "does_not_exist")

	assert_nil(child_pk, "no ref → nil")

	db:close()
end)

test("get_ref_child returns the child's pk for an existing (parent, key)", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)
	local child = e:add_scalar("n", 99, user)
	e:add_ref(parent, "answer", child)

	local looked_up = e:get_ref_child(parent, "answer")

	assert_eq(looked_up, child, "returned pk matches child")

	db:close()
end)

test("get_ref_child's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)

	assert_not_nil(e.stmt_get_ref_child, "cache populated at construction")

	db:close()
end)

-- ==============================================================
-- frame:ensure_locals
-- ==============================================================

test("frame:ensure_locals materializes the locals hash on first call", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	local locals = frame:ensure_locals()

	assert_not_nil(locals, "returned an object")
	assert_eq(locals.primitive, "h", "locals is a HashPrimitive")
	assert_eq(locals.owner_role, user, "locals owned by the frame's owner_role")
	assert_nil(locals.bucket_for, "locals is a plain hash, not a bucket_for anyone")

	db:close()
end)

test("frame:ensure_locals binds the locals hash under bucket['locals']", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	local locals = frame:ensure_locals()
	local bucket = frame:bucket()
	local via_lookup = e:get_ref_child(bucket.object_pk, "locals")

	assert_eq(via_lookup, locals.object_pk, "bucket['locals'] resolves to the returned hash")

	db:close()
end)

test("frame:ensure_locals is idempotent — same hash returned across calls", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	local first = frame:ensure_locals()
	local second = frame:ensure_locals()

	assert_eq(first.object_pk, second.object_pk, "second call returns the same hash pk")

	-- Only one 'locals' ref should exist in the frame's bucket.
	local count
	local sql = string.format(
		"select count(*) as n from refs where parent = '%s' and key = 'locals'",
		frame:bucket().object_pk
	)

	for r in db:nrows(sql) do
		count = r.n
	end

	assert_eq(count, 1, "exactly one locals ref, no duplicates")

	db:close()
end)

test("frame:locals returns nil on a fresh frame (no locals hash yet)", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	local locals = frame:locals()

	assert_nil(locals, "fresh frame has no locals hash yet")

	db:close()
end)

test("frame:locals returns the hash once it's been materialized", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	local ensured = frame:ensure_locals()
	local read = frame:locals()

	assert_not_nil(read, "read returns something")
	assert_eq(read.object_pk, ensured.object_pk, "read pk matches ensured pk")

	db:close()
end)

-- ==============================================================
-- frame:set_local_to_scalar
-- ==============================================================

test("set_local_to_scalar creates the scalar with correct columns", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	frame:set_local_to_scalar("x", "n", 1)

	-- The scalar exists as an objects row.
	local row
	local sql = "select object_pk, primitive, scalar_type, scalar_value, owner_role " ..
		"from objects where scalar_value = 1 and scalar_type = 'n'"

	for r in db:nrows(sql) do
		row = r
	end

	assert_not_nil(row, "scalar row exists")
	assert_eq(row.primitive, "o", "primitive is scalar")
	assert_eq(row.scalar_type, "n", "scalar_type=n")
	assert_eq(row.scalar_value, 1, "scalar_value=1")
	assert_eq(row.owner_role, user, "owner_role matches frame's owner_role")

	db:close()
end)

test("set_local_to_scalar wires the binding through bucket → locals → key", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	frame:set_local_to_scalar("x", "n", 1)

	local bucket = frame:bucket()
	local locals_pk = e:get_ref_child(bucket.object_pk, "locals")
	assert_not_nil(locals_pk, "bucket['locals'] exists")

	local scalar_pk = e:get_ref_child(locals_pk, "x")
	assert_not_nil(scalar_pk, "locals['x'] exists")

	-- The child under locals['x'] is the scalar we wrote.
	local scalar_value
	local sql = string.format(
		"select scalar_value from objects where object_pk = '%s'",
		scalar_pk
	)

	for r in db:nrows(sql) do
		scalar_value = r.scalar_value
	end

	assert_eq(scalar_value, 1, "locals['x'] holds the scalar with value 1")

	db:close()
end)

test("set_local_to_scalar handles multiple bindings in the same frame", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	frame:set_local_to_scalar("x", "n", 1)
	frame:set_local_to_scalar("y", "n", 2)
	frame:set_local_to_scalar("name", "s", "alice")

	local locals = frame:locals()

	local x_pk = e:get_ref_child(locals.object_pk, "x")
	local y_pk = e:get_ref_child(locals.object_pk, "y")
	local name_pk = e:get_ref_child(locals.object_pk, "name")

	assert_not_nil(x_pk, "locals['x'] bound")
	assert_not_nil(y_pk, "locals['y'] bound")
	assert_not_nil(name_pk, "locals['name'] bound")

	-- Distinct scalars for each.
	assert(x_pk ~= y_pk, "x and y point at different scalars")
	assert(x_pk ~= name_pk, "x and name point at different scalars")

	db:close()
end)

test("set_local_to_scalar reuses the locals hash across bindings (no duplicate 'locals' refs)", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)
	local frame = e:object_by_pk(frame_pk)

	frame:set_local_to_scalar("x", "n", 1)
	frame:set_local_to_scalar("y", "n", 2)

	local count
	local sql = string.format(
		"select count(*) as n from refs where parent = '%s' and key = 'locals'",
		frame:bucket().object_pk
	)

	for r in db:nrows(sql) do
		count = r.n
	end

	assert_eq(count, 1, "exactly one locals ref, reused across bindings")

	db:close()
end)

-- ==============================================================
-- add_frame
-- ==============================================================

test("add_frame inserts a primitive='f' row with ast, process_pk, stmt_idx=0, owner_role", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	-- Need a processes row for the FK.
	db:exec("insert into processes default values;")
	local process_pk

	for row in db:nrows("select process_pk from processes") do
		process_pk = row.process_pk
	end

	local frame_pk = e:add_frame('[[]]', process_pk, user)
	assert_not_nil(frame_pk, "add_frame returned nil")

	local row

	for r in db:nrows("select * from objects where object_pk = '" .. frame_pk .. "'") do
		row = r
	end

	assert_eq(row.primitive, 'f',              "primitive should be 'f'")
	assert_eq(row.ast,       '[[]]',           "ast should be the passed value")
	assert_eq(row.process_pk,   process_pk,       "process should be the passed pk")
	assert_eq(row.stmt_idx,  0,                "stmt_idx should be 0 at push")
	assert_eq(row.owner_role, user,            "owner_role should be the passed pk")

	db:close()
end)

test("add_frame's prepared statement is cached at construction", function()
	local db = fresh_db()
	local e = engine.new(db)
	assert_not_nil(e.stmt_add_frame, "expected engine.new to prep stmt_add_frame")
	db:close()
end)

-- ==============================================================
-- frame_by_pk
-- ==============================================================

test("frame_by_pk returns the wrapper for a frame row", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)

	local frame = e:frame_by_pk(frame_pk)
	assert_not_nil(frame,             "frame_by_pk returned nil")
	assert_eq(frame.primitive, 'f',   "wrapper primitive should be 'f'")
	assert_eq(frame.object_pk, frame_pk, "wrapper pk mismatch")

	db:close()
end)

test("frame_by_pk raises frame_by_pk_not_found when the pk doesn't exist", function()
	local db = fresh_db()
	local e = engine.new(db)

	local ok, err = pcall(function() e:frame_by_pk("00000000-0000-4000-8000-000000000000") end)
	assert_eq(ok, false, "expected pcall to fail")

	if not string.find(err, "frame_by_pk_not_found:", 1, true) then
		error("expected frame_by_pk_not_found error, got: " .. tostring(err))
	end

	db:close()
end)

test("frame_by_pk raises frame_by_pk_not_a_frame when the pk points at a non-frame row", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local non_frame = insert_target(db, user)   -- primitive = 'o'

	local ok, err = pcall(function() e:frame_by_pk(non_frame) end)
	assert_eq(ok, false, "expected pcall to fail")

	if not string.find(err, "frame_by_pk_not_a_frame:", 1, true) then
		error("expected frame_by_pk_not_a_frame error, got: " .. tostring(err))
	end

	if not string.find(err, "primitive 'o'", 1, true) then
		error("expected the error to name the actual primitive, got: " .. tostring(err))
	end

	db:close()
end)

test("frame.new raises frame_new_not_a_frame_row when handed a non-frame row directly", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local non_frame = insert_target(db, user)

	-- Simulate a direct caller that skips object.new's dispatch: fetch
	-- a non-frame row and hand it to frame.new.
	local frame_mod = require("cvm.frame")
	local row

	for r in db:nrows("select * from objects where object_pk = '" .. non_frame .. "'") do
		row = r
	end

	local ok, err = pcall(function() frame_mod.new(e, row) end)
	assert_eq(ok, false, "expected pcall to fail")

	if not string.find(err, "frame_new_not_a_frame_row:", 1, true) then
		error("expected frame_new_not_a_frame_row error, got: " .. tostring(err))
	end

	db:close()
end)

-- ==============================================================
-- Schema-level constraints on the new frame columns
-- ==============================================================

test("primitive = 'f' requires ast to be non-null (biconditional CHECK)", function()
	local db = fresh_db()
	local user = user_pk(db)

	local sql = string.format(
		"insert into objects (primitive, owner_role) values ('f', '%s')",
		user
	)
	local rc = db:exec(sql)

	assert_eq(rc == sqlite.OK, false, "expected CHECK to reject 'f' without ast")
	db:close()
end)

test("non-frame rows may not carry ast (biconditional CHECK)", function()
	local db = fresh_db()
	local user = user_pk(db)

	local sql = string.format(
		"insert into objects (primitive, ast, owner_role) values ('o', '[[]]', '%s')",
		user
	)
	local rc = db:exec(sql)

	assert_eq(rc == sqlite.OK, false, "expected CHECK to reject 'o' with ast")
	db:close()
end)

test("stmt_idx / idx / process rejected on non-frame rows", function()
	local db = fresh_db()
	local user = user_pk(db)
	db:exec("insert into processes default values;")

	-- stmt_idx on 'o'
	local rc = db:exec(string.format(
		"insert into objects (primitive, stmt_idx, owner_role) values ('o', 0, '%s')", user
	))
	assert_eq(rc == sqlite.OK, false, "expected CHECK to reject stmt_idx on 'o'")

	-- process on 'o' — use a text UUID-shape value; would fail FK anyway
	-- but the CHECK should fire on primitive != 'f'.
	rc = db:exec(string.format(
		"insert into objects (primitive, process_pk, owner_role) values ('o', '00000000-0000-4000-8000-000000000000', '%s')", user
	))
	assert_eq(rc == sqlite.OK, false, "expected CHECK to reject process on 'o'")

	-- parent_frame on 'o'
	rc = db:exec(string.format(
		"insert into objects (primitive, parent_frame, owner_role) values ('o', '00000000-0000-4000-8000-000000000000', '%s')", user
	))
	assert_eq(rc == sqlite.OK, false, "expected CHECK to reject parent_frame on 'o'")

	db:close()
end)

-- ==============================================================
-- uspace view — frame anchor branch
-- ==============================================================

test("uspace includes frames currently on a stack", function()
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	db:exec("insert into processes default values;")

	local process_pk

	for row in db:nrows("select process_pk from processes") do
		process_pk = row.process_pk
	end

	local frame_pk = e:add_frame('[[]]', process_pk, user)

	local found = false

	for row in db:nrows("select object_pk from uspace where object_pk = '" .. frame_pk .. "'") do
		found = true
	end

	assert_eq(found, true, "expected the on-stack frame to be in uspace")
	db:close()
end)

test("uspace excludes frames with null stack coordinates (popped-but-captured shape)", function()
	local db = fresh_db()
	local user = user_pk(db)
	local frame_pk = insert_frame(db, user)   -- 'f' with null process/idx/stmt_idx

	local found = false

	for row in db:nrows("select object_pk from uspace where object_pk = '" .. frame_pk .. "'") do
		found = true
	end

	assert_eq(found, false, "expected a frame with null process to NOT be in uspace")
	db:close()
end)
