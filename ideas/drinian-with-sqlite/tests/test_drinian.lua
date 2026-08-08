--[[ {
	"vibecode": {
		"role": "walking-skeleton tests for src/drinian.lua: open an in-memory DB, apply the schema, verify the seed exists and a couple of schema-level guarantees fire",
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

h.test('current_process temp table exists after open', function()
	local db = drinian.open()

	db:exec("insert into current_process (key, value) values ('current_process_pk', 1);")

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

h.test('cannot insert a role_parent pointing at a nonexistent row (FK)', function()
	local db = drinian.open()

	local rc = db:exec("insert into objects (primitive, role_parent) values ('h', 'no-such-uuid-0000-0000-000000000000');")
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'insert with dangling role_parent should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('FOREIGN KEY', 1, true) ~= nil or msg:find('foreign key', 1, true) ~= nil, 'expected FOREIGN KEY violation, got: ' .. tostring(msg))

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
-- Schema extraction sanity
------------------------------------------------------------

h.test('load_schema_from_md returns non-empty SQL', function()
	local sql = drinian.load_schema_from_md()
	h.assert_true(type(sql) == 'string', 'schema is not a string')
	h.assert_true(#sql > 100, 'schema suspiciously short: ' .. #sql .. ' chars')
	h.assert_true(sql:find('create table objects', 1, true) ~= nil, 'schema does not contain "create table objects"')
end)
