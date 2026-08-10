--[[ {
	"vibecode": {
		"role": "walking-skeleton tests for src/drinian.lua: open an in-memory DB, install the infrastructure, verify the seed exists and a couple of schema-level guarantees fire",
		"status": "walking-skeleton — proves the DB opens and the schema loads without error"
	}
} ]]

local h = require('helpers')
local drinian = require('drinian')

------------------------------------------------------------
-- open + apply schema
------------------------------------------------------------

h.test('open returns a usable db handle', function()
	local db = drinian.open()
	h.assert_true(db ~= nil, 'db handle is nil')
	db:close()
end)

h.test('foreign keys pragma is on after open', function()
	local db = drinian.open()

	local fk_on = nil

	for row in db:nrows('pragma foreign_keys') do
		fk_on = row.foreign_keys
	end

	h.assert_eq(fk_on, 1, 'foreign_keys pragma should be 1 (on)')
	db:close()
end)

h.test('schema seeds the user row', function()
	local db = drinian.open()

	local count = nil

	for row in db:nrows('select count(*) as n from objects where user') do
		count = row.n
	end

	h.assert_eq(count, 1, 'expected exactly one user row after seed')
	db:close()
end)

h.test('user row has a UUID-shaped object_pk', function()
	local db = drinian.open()

	local pk = nil

	for row in db:nrows('select object_pk from objects where user') do
		pk = row.object_pk
	end

	h.assert_true(pk ~= nil, 'user row has no object_pk')
	h.assert_eq(#pk, 36, 'object_pk should be 36 characters (UUID4 shape)')
	h.assert_true(pk:match('^[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+$') ~= nil, 'object_pk does not match UUID4 shape: ' .. tostring(pk))
	db:close()
end)

h.test('user row has persistent = 1', function()
	local db = drinian.open()

	local persistent = nil

	for row in db:nrows('select persistent from objects where user') do
		persistent = row.persistent
	end

	h.assert_eq(persistent, 1, 'user row should have persistent = 1')
	db:close()
end)

h.test('user row has role_parent = null (root)', function()
	local db = drinian.open()

	local role_parent = 'not-null-sentinel'

	for row in db:nrows('select role_parent from objects where user') do
		role_parent = row.role_parent
	end

	h.assert_true(role_parent == nil, 'root role should have role_parent = null, got ' .. tostring(role_parent))
	db:close()
end)

------------------------------------------------------------
-- current_process TEMP table
------------------------------------------------------------

h.test('current_process temp table exists after open and accepts caller writes', function()
	local db = drinian.open()

	-- Pick a key drinian.open didn't already populate. current_process_pk
	-- is filled by open (see the process-record test); an arbitrary
	-- caller-owned key exercises the "TEMP table is writable" property
	-- without colliding with the seeded row.
	db:exec("insert into current_process (key, value) values ('test_marker', 42);")

	local msg = db:errmsg()
	h.assert_eq(msg, 'not an error', 'insert into current_process failed: ' .. tostring(msg))

	db:close()
end)

------------------------------------------------------------
-- Schema-level guarantees
------------------------------------------------------------

h.test('cannot delete the user row (root role trigger)', function()
	local db = drinian.open()

	local rc = db:exec('delete from objects where user;')
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'delete should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('root_role_cannot_be_deleted', 1, true) ~= nil, 'expected root_role_cannot_be_deleted, got: ' .. tostring(msg))

	db:close()
end)

h.test('cannot insert a second user = 1 row (unique)', function()
	local db = drinian.open()

	local rc = db:exec("insert into objects (primitive, user) values ('h', 1);")
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'second user insert should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('UNIQUE', 1, true) ~= nil or msg:find('unique', 1, true) ~= nil, 'expected UNIQUE violation, got: ' .. tostring(msg))

	db:close()
end)

h.test('cannot insert a role_parent pointing at a nonexistent row', function()
	local db = drinian.open()

	local rc = db:exec("insert into objects (primitive, role_parent) values ('h', 'no-such-uuid-0000-0000-000000000000');")
	local msg = db:errmsg()

	-- Either error is acceptable: the FK would fire for a nonexistent
	-- target, but the objects_role_parent_must_be_role trigger runs
	-- first (BEFORE INSERT) and its SELECT returns nothing for the
	-- missing row, so `role_parent_must_be_role` gets raised before
	-- SQLite reaches FK enforcement. Both mean "invalid role_parent."
	h.assert_true(rc ~= 0, 'insert with dangling role_parent should have failed but rc = ' .. tostring(rc))
	h.assert_true(
		msg:find('FOREIGN KEY', 1, true) ~= nil
			or msg:find('foreign key', 1, true) ~= nil
			or msg:find('role_parent_must_be_role', 1, true) ~= nil,
		'expected FOREIGN KEY violation or role_parent_must_be_role, got: ' .. tostring(msg)
	)

	db:close()
end)

h.test('cannot insert with role_parent pointing at a non-role row', function()
	local db = drinian.open()

	-- Insert an ordinary HashPrimitive (not a role — no user=1, no role_parent).
	local stmt = db:prepare("insert into objects (primitive) values ('h');")
	stmt:step()
	stmt:finalize()

	local non_role_pk = nil

	for row in db:nrows("select object_pk from objects where user is null and role_parent is null and primitive = 'h' order by rowid desc limit 1") do
		non_role_pk = row.object_pk
	end

	h.assert_true(non_role_pk ~= nil, 'setup failed: no non-role row present')

	-- Try to make it a parent of a new role.
	stmt = db:prepare("insert into objects (primitive, role_parent) values ('h', ?);")
	stmt:bind_values(non_role_pk)
	local rc = stmt:step()
	local msg = db:errmsg()
	stmt:finalize()

	h.assert_true(rc ~= 101, 'insert with non-role role_parent should have failed but succeeded (rc = ' .. tostring(rc) .. ')')
	h.assert_true(msg:find('role_parent_must_be_role', 1, true) ~= nil, 'expected role_parent_must_be_role, got: ' .. tostring(msg))

	db:close()
end)

h.test('can insert with role_parent pointing at a role (root or non-root)', function()
	local db = drinian.open()

	-- Insert child of root — should succeed.
	local user_pk = nil

	for row in db:nrows('select object_pk from objects where user') do
		user_pk = row.object_pk
	end

	local stmt = db:prepare("insert into objects (primitive, role_parent) values ('h', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	local msg = db:errmsg()
	h.assert_eq(msg, 'not an error', 'insert of child role failed: ' .. tostring(msg))

	-- Insert grandchild of root — parent is a non-root role, should also succeed.
	local child_pk = nil

	for row in db:nrows('select object_pk from objects where role_parent is not null order by rowid desc limit 1') do
		child_pk = row.object_pk
	end

	stmt = db:prepare("insert into objects (primitive, role_parent) values ('h', ?);")
	stmt:bind_values(child_pk)
	stmt:step()
	stmt:finalize()

	msg = db:errmsg()
	h.assert_eq(msg, 'not an error', 'insert of grandchild role failed: ' .. tostring(msg))

	db:close()
end)

h.test('cannot update role_parent on an existing row (immutable)', function()
	local db = drinian.open()

	-- Insert a role as a child of user.
	local user_pk = nil

	for row in db:nrows('select object_pk from objects where user') do
		user_pk = row.object_pk
	end

	local stmt = db:prepare("insert into objects (primitive, role_parent) values ('h', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	-- Try to null out role_parent.
	local rc = db:exec('update objects set role_parent = null where role_parent is not null;')
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'update of role_parent should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('role_parent_immutable', 1, true) ~= nil, 'expected role_parent_immutable, got: ' .. tostring(msg))

	db:close()
end)

------------------------------------------------------------
-- Process record + current_process population
------------------------------------------------------------

h.test('processes table has a row after open (process record initialized)', function()
	local db = drinian.open()

	local count

	for row in db:nrows('select count(*) as n from processes') do
		count = row.n
	end

	h.assert_eq(count, 1, 'expected exactly one processes row after open')
	db:close()
end)

h.test("current_process has 'current_process_pk' populated with the processes row's pk", function()
	local db = drinian.open()

	local cp_value

	for row in db:nrows("select value from current_process where key = 'current_process_pk'") do
		cp_value = row.value
	end

	h.assert_true(cp_value ~= nil, 'current_process is missing the current_process_pk row')

	local process_pk

	for row in db:nrows('select process_pk from processes') do
		process_pk = row.process_pk
	end

	h.assert_eq(cp_value, process_pk, 'current_process.value should equal processes.process_pk')
	db:close()
end)

------------------------------------------------------------
-- Install-infrastructure gate (idempotent open)
------------------------------------------------------------

h.test('drinian marker table is present after a fresh install', function()
	local db = drinian.open()

	local present = false

	for _ in db:nrows("select name from sqlite_master where type = 'table' and name = 'drinian'") do
		present = true
	end

	h.assert_true(present, 'drinian marker table should exist after install')
	db:close()
end)

h.test('opening an already-installed DB is idempotent (skips the install)', function()
	-- Temp file so state survives close/reopen. os.tmpname on Linux
	-- creates an empty file; SQLite is happy to treat that as an empty
	-- database (no tables) on first open, so the install runs. Second
	-- open finds the drinian marker table and skips.
	local tmp = os.tmpname()

	-- First open: fresh install.
	local db1 = drinian.open({path = tmp})

	local first_pk

	for row in db1:nrows('select object_pk from objects where user') do
		first_pk = row.object_pk
	end

	h.assert_true(first_pk ~= nil, 'user row missing after first open')
	db1:close()

	-- Second open: install should be skipped. If the gate didn't work,
	-- the install would re-run and raise "table objects already exists"
	-- from drinian.open — the test would fail with an uncaught error.
	local db2 = drinian.open({path = tmp})

	-- Sanity: exactly one user row (not two).
	local count

	for row in db2:nrows('select count(*) as n from objects where user') do
		count = row.n
	end

	h.assert_eq(count, 1, 'still exactly one user row after second open')

	-- Sanity: same user pk as first open (state preserved across reopen).
	local second_pk

	for row in db2:nrows('select object_pk from objects where user') do
		second_pk = row.object_pk
	end

	h.assert_eq(second_pk, first_pk, 'user_pk should survive close+reopen')

	db2:close()
	os.remove(tmp)
end)

------------------------------------------------------------
-- Schema extraction sanity
------------------------------------------------------------

h.test('load_schema returns non-empty SQL', function()
	local sql = drinian.load_schema()
	h.assert_true(type(sql) == 'string', 'schema is not a string')
	h.assert_true(#sql > 100, 'schema suspiciously short: ' .. #sql .. ' chars')
	h.assert_true(sql:find('create table objects', 1, true) ~= nil, 'schema does not contain "create table objects"')
end)
