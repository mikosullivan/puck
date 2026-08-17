--[[
{
	"spec": "test_cvm",
	"role": "Walking-skeleton tests for `src/engine/cvm/open.lua`: open an in-memory DB, install the infrastructure via `schema.sql`, verify the seed row exists and a couple of schema-level guarantees fire. Covers the pragmas (`foreign_keys`, `recursive_triggers`), the fresh-vs-revive install gate, the initial `processes` row, and a set of trigger / constraint behaviors that the schema is expected to enforce.",
	"status": "walking-skeleton — proves the DB opens and the schema loads without error"
}
]]

--[[
# `test_cvm`

Behavioural tests for the CVM open path. Every case starts from a
fresh in-memory SQLite (`cvm.open()` with no `path`), then either
introspects the freshly-installed schema (pragma queries, `objects`
seed lookup, marker-table check) or exercises a schema-level
guarantee (foreign-key rejection, trigger firing, unique-constraint
violation).

Kept at the walking-skeleton level: the point is that
`schema.sql` applies cleanly and its declared invariants are
actually wired up — not to cover every column on every table.
]]

local h = require('helpers')
local cvm = require('cvm.open')

------------------------------------------------------------
-- open + apply schema
------------------------------------------------------------

h.test('open returns a usable db handle', function()
	local db = cvm.open()
	h.assert_true(db ~= nil, 'db handle is nil')
	db:close()
end)

h.test('foreign keys pragma is on after open', function()
	local db = cvm.open()

	local fk_on = nil

	for row in db:nrows('pragma foreign_keys') do
		fk_on = row.foreign_keys
	end

	h.assert_eq(fk_on, 1, 'foreign_keys pragma should be 1 (on)')
	db:close()
end)

h.test('recursive triggers pragma is on after open', function()
	local db = cvm.open()

	local rt_on = nil

	for row in db:nrows('pragma recursive_triggers') do
		rt_on = row.recursive_triggers
	end

	h.assert_eq(rt_on, 1, 'recursive_triggers pragma should be 1 (on)')
	db:close()
end)

h.test('schema seeds the user row', function()
	local db = cvm.open()

	local count = nil

	for row in db:nrows("select count(*) as n from objects where core_role = 'u'") do
		count = row.n
	end

	h.assert_eq(count, 1, 'expected exactly one user row after seed')
	db:close()
end)

h.test('user row has a UUID-shaped object_pk', function()
	local db = cvm.open()

	local pk = nil

	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		pk = row.object_pk
	end

	h.assert_true(pk ~= nil, 'user row has no object_pk')
	h.assert_eq(#pk, 36, 'object_pk should be 36 characters (UUID4 shape)')
	h.assert_true(pk:match('^[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+%-[0-9a-f]+$') ~= nil, 'object_pk does not match UUID4 shape: ' .. tostring(pk))
	db:close()
end)

h.test('user row has persistent = 1', function()
	local db = cvm.open()

	local persistent = nil

	for row in db:nrows("select persistent from objects where core_role = 'u'") do
		persistent = row.persistent
	end

	h.assert_eq(persistent, 1, 'user row should have persistent = 1')
	db:close()
end)

h.test('engine row has parent_role = null (root of the core-role tree)', function()
	local db = cvm.open()

	local parent_role = 'not-null-sentinel'

	for row in db:nrows("select parent_role from objects where core_role = 'e'") do
		parent_role = row.parent_role
	end

	h.assert_true(parent_role == nil, 'engine (root of the tree) should have parent_role = null, got ' .. tostring(parent_role))
	db:close()
end)

h.test('cache and user rows have parent_role set to engine', function()
	local db = cvm.open()

	local engine_pk
	for row in db:nrows("select object_pk from objects where core_role = 'e'") do
		engine_pk = row.object_pk
	end

	for _, role in ipairs({'c', 'u'}) do
		local parent_role
		for row in db:nrows(string.format("select parent_role from objects where core_role = '%s'", role)) do
			parent_role = row.parent_role
		end
		h.assert_eq(parent_role, engine_pk, "core role '" .. role .. "' should have parent_role = engine's pk")
	end

	db:close()
end)

------------------------------------------------------------
-- Schema-level guarantees
------------------------------------------------------------

h.test('cannot delete the user row (root role trigger)', function()
	local db = cvm.open()

	local rc = db:exec("delete from objects where core_role = 'u';")
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'delete should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('root_role_cannot_be_deleted', 1, true) ~= nil, 'expected root_role_cannot_be_deleted, got: ' .. tostring(msg))

	db:close()
end)

h.test("cannot insert a second row with core_role = 'u' (unique)", function()
	local db = cvm.open()

	-- Second user-role insert must satisfy other invariants first
	-- (owner_role required on non-roles; parent_role must exist; core
	-- roles must be pinned with persistent=1). Set them all, then let
	-- the UNIQUE fire on core_role.
	local rc = db:exec([[
		insert into objects (primitive, core_role, parent_role, owner_role, persistent)
		values ('r', 'u',
			(select object_pk from objects where core_role = 'e'),
			(select object_pk from objects where core_role = 'e'),
			1);
	]])
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'second core_role=u insert should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('UNIQUE', 1, true) ~= nil or msg:find('unique', 1, true) ~= nil, 'expected UNIQUE violation, got: ' .. tostring(msg))

	db:close()
end)

h.test('cannot insert a parent_role pointing at a nonexistent row', function()
	local db = cvm.open()

	local rc = db:exec("insert into objects (primitive, parent_role) values ('r', '00000000-0000-4000-8000-000000000000');")
	local msg = db:errmsg()

	-- Either error is acceptable: the FK would fire for a nonexistent
	-- target, but the objects_parent_role_must_be_role trigger runs
	-- first (BEFORE INSERT) and its SELECT returns nothing for the
	-- missing row, so `parent_role_must_be_role` gets raised before
	-- SQLite reaches FK enforcement. Both mean "invalid parent_role."
	h.assert_true(rc ~= 0, 'insert with dangling parent_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(
		msg:find('FOREIGN KEY', 1, true) ~= nil
			or msg:find('foreign key', 1, true) ~= nil
			or msg:find('parent_role_must_be_role', 1, true) ~= nil,
		'expected FOREIGN KEY violation or parent_role_must_be_role, got: ' .. tostring(msg)
	)

	db:close()
end)

h.test('cannot insert with parent_role pointing at a non-role row', function()
	local db = cvm.open()

	-- Insert an ordinary HashPrimitive (not a role — no user=1, no parent_role).
	-- Under the ownership rule, non-role objects must have owner_role set;
	-- point it at the user row (the only role that exists at test start).
	local user_pk = nil
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	local stmt = db:prepare("insert into objects (primitive, owner_role) values ('h', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	local non_role_pk = nil

	for row in db:nrows("select object_pk from objects where core_role = 'u' is null and parent_role is null and primitive = 'h' order by rowid desc limit 1") do
		non_role_pk = row.object_pk
	end

	h.assert_true(non_role_pk ~= nil, 'setup failed: no non-role row present')

	-- Try to make it a parent of a new role.
	stmt = db:prepare("insert into objects (primitive, parent_role) values ('r', ?);")
	stmt:bind_values(non_role_pk)
	local rc = stmt:step()
	local msg = db:errmsg()
	stmt:finalize()

	h.assert_true(rc ~= 101, 'insert with non-role parent_role should have failed but succeeded (rc = ' .. tostring(rc) .. ')')
	h.assert_true(msg:find('parent_role_must_be_role', 1, true) ~= nil, 'expected parent_role_must_be_role, got: ' .. tostring(msg))

	db:close()
end)

h.test('can insert with parent_role pointing at a role (root or non-root)', function()
	local db = cvm.open()

	-- Insert child of root — should succeed.
	local user_pk = nil

	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	local stmt = db:prepare("insert into objects (primitive, parent_role) values ('r', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	local msg = db:errmsg()
	h.assert_eq(msg, 'not an error', 'insert of child role failed: ' .. tostring(msg))

	-- Insert grandchild of root — parent is a non-root role, should also succeed.
	local child_pk = nil

	for row in db:nrows('select object_pk from objects where parent_role is not null order by rowid desc limit 1') do
		child_pk = row.object_pk
	end

	stmt = db:prepare("insert into objects (primitive, parent_role) values ('r', ?);")
	stmt:bind_values(child_pk)
	stmt:step()
	stmt:finalize()

	msg = db:errmsg()
	h.assert_eq(msg, 'not an error', 'insert of grandchild role failed: ' .. tostring(msg))

	db:close()
end)

h.test('cannot update parent_role on an existing row (immutable)', function()
	local db = cvm.open()

	-- Insert a role as a child of user.
	local user_pk = nil

	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	local stmt = db:prepare("insert into objects (primitive, parent_role) values ('r', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	-- Try to null out parent_role on the just-inserted non-core-role
	-- child (predicate excludes the seeded core-role rows so the
	-- core-role guard doesn't fire first).
	local rc = db:exec('update objects set parent_role = null where parent_role is not null and core_role is null;')
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'update of parent_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('parent_role_immutable', 1, true) ~= nil, 'expected parent_role_immutable, got: ' .. tostring(msg))

	db:close()
end)

------------------------------------------------------------
-- Ownership rule: non-role rows must have owner_role set.
-- (The old XOR rule "roles cannot have owner_role" was dropped
-- under the cache design — cache and user are both roles AND
-- owned by engine.)
------------------------------------------------------------

h.test('non-role insert without owner_role raises objects_owner_role_required', function()
	local db = cvm.open()

	local rc = db:exec("insert into objects (primitive) values ('h');")
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'insert without owner_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('objects_owner_role_required', 1, true) ~= nil,
		'expected objects_owner_role_required, got: ' .. tostring(msg))

	db:close()
end)

h.test('role insert with owner_role is allowed (XOR rule dropped)', function()
	local db = cvm.open()

	local user_pk
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	-- Insert a role (parent_role set) that also has owner_role set —
	-- allowed under the new design (cache and user are seeded exactly
	-- like this).
	local stmt = db:prepare(
		"insert into objects (primitive, parent_role, owner_role) values ('r', ?, ?);"
	)
	stmt:bind_values(user_pk, user_pk)
	local rc = stmt:step()
	local msg = db:errmsg()
	stmt:finalize()

	h.assert_true(rc == 101, 'insert with both parent_role + owner_role should have succeeded, got rc = ' .. tostring(rc) .. ', msg: ' .. tostring(msg))

	db:close()
end)

h.test('owner_role pointing at a non-role raises owner_role_must_be_role', function()
	local db = cvm.open()

	local user_pk
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	-- Insert a non-role first (owned by user).
	local stmt = db:prepare(
		"insert into objects (primitive, owner_role) values ('h', ?);"
	)
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	local non_role_pk
	for row in db:nrows(
			"select object_pk from objects where core_role = 'u' is null and parent_role is null "
			.. "and primitive = 'h' order by rowid desc limit 1") do
		non_role_pk = row.object_pk
	end

	-- Now try to insert a non-role owned by that non-role.
	stmt = db:prepare("insert into objects (primitive, owner_role) values ('h', ?);")
	stmt:bind_values(non_role_pk)
	local rc = stmt:step()
	local msg = db:errmsg()
	stmt:finalize()

	h.assert_true(rc ~= 101, 'insert with non-role owner_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('owner_role_must_be_role', 1, true) ~= nil,
		'expected owner_role_must_be_role, got: ' .. tostring(msg))

	db:close()
end)

h.test('owner_role is immutable — update raises objects_owner_role_immutable', function()
	local db = cvm.open()

	local user_pk
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	-- Insert a role and a non-role owned by user.
	local stmt = db:prepare(
		"insert into objects (primitive, parent_role) values ('r', ?);"
	)
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	local role_pk
	for row in db:nrows("select object_pk from objects where parent_role is not null order by rowid desc limit 1") do
		role_pk = row.object_pk
	end

	stmt = db:prepare("insert into objects (primitive, owner_role) values ('h', ?);")
	stmt:bind_values(user_pk)
	stmt:step()
	stmt:finalize()

	-- Try to reparent the non-role we just inserted. Predicate excludes
	-- the seeded core-role rows (which also have owner_role set) so the
	-- core-role guard doesn't fire first.
	local rc = db:exec("update objects set owner_role = '" .. role_pk .. "' where owner_role is not null and core_role is null;")
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'update of owner_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(msg:find('objects_owner_role_immutable', 1, true) ~= nil,
		'expected objects_owner_role_immutable, got: ' .. tostring(msg))

	db:close()
end)

h.test('parent_role = object_pk raises objects_parent_role_not_self', function()
	local db = cvm.open()

	-- Try to insert a role whose parent_role equals its own object_pk.
	-- Both the explicit not-self trigger and the "must be role" trigger
	-- would catch it; the not-self trigger has WHEN new.parent_role =
	-- new.object_pk so it fires first when both apply.
	local self_pk = '11111111-1111-4111-8111-111111111111'
	local rc = db:exec(
		"insert into objects (object_pk, primitive, parent_role) values ('"
		.. self_pk .. "', 'r', '" .. self_pk .. "');"
	)
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'insert with self parent_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(
		msg:find('objects_parent_role_not_self', 1, true) ~= nil
			or msg:find('parent_role_must_be_role', 1, true) ~= nil,
		'expected objects_parent_role_not_self or parent_role_must_be_role, got: ' .. tostring(msg))

	db:close()
end)

h.test('owner_role = object_pk raises objects_owner_role_not_self', function()
	local db = cvm.open()

	-- Same shape as above but for owner_role. Both the explicit not-self
	-- trigger and owner_role_must_be_role would catch it; the not-self
	-- trigger's WHEN clause pins it to the exact self-link case.
	local self_pk = '22222222-2222-4222-8222-222222222222'
	local rc = db:exec(
		"insert into objects (object_pk, primitive, owner_role) values ('"
		.. self_pk .. "', 'r', '" .. self_pk .. "');"
	)
	local msg = db:errmsg()

	h.assert_true(rc ~= 0, 'insert with self owner_role should have failed but rc = ' .. tostring(rc))
	h.assert_true(
		msg:find('objects_owner_role_not_self', 1, true) ~= nil
			or msg:find('owner_role_must_be_role', 1, true) ~= nil,
		'expected objects_owner_role_not_self or owner_role_must_be_role, got: ' .. tostring(msg))

	db:close()
end)

h.test("engine seed has parent_role and owner_role both null (root of the core-role tree)", function()
	local db = cvm.open()

	local rp, ow
	for row in db:nrows("select parent_role, owner_role from objects where core_role = 'e'") do
		rp = row.parent_role
		ow = row.owner_role
	end

	h.assert_true(rp == nil, 'engine seed parent_role should be null, got: ' .. tostring(rp))
	h.assert_true(ow == nil, 'engine seed owner_role should be null, got: ' .. tostring(ow))

	db:close()
end)

h.test('cvm.open returns only the db handle (no second return value)', function()
	local db, second = cvm.open()

	h.assert_true(second == nil, 'expected cvm.open to return nil as its second value; got: ' .. tostring(second))
	db:close()
end)

------------------------------------------------------------
-- Install-infrastructure gate (idempotent open)
------------------------------------------------------------

h.test('cvm marker table is present after a fresh install', function()
	local db = cvm.open()

	local present = false

	for _ in db:nrows("select name from sqlite_master where type = 'table' and name = 'cvm'") do
		present = true
	end

	h.assert_true(present, 'cvm marker table should exist after install')
	db:close()
end)

h.test('opening an already-installed DB is idempotent (skips the install)', function()
	-- Temp file so state survives close/reopen. os.tmpname on Linux
	-- creates an empty file; SQLite is happy to treat that as an empty
	-- database (no tables) on first open, so the install runs. Second
	-- open finds the cvm marker table and skips.
	local tmp = os.tmpname()

	-- First open: fresh install.
	local db1 = cvm.open({path = tmp})

	local first_pk

	for row in db1:nrows("select object_pk from objects where core_role = 'u'") do
		first_pk = row.object_pk
	end

	h.assert_true(first_pk ~= nil, 'user row missing after first open')
	db1:close()

	-- Second open: install should be skipped. If the gate didn't work,
	-- the install would re-run and raise "table objects already exists"
	-- from cvm.open — the test would fail with an uncaught error.
	local db2 = cvm.open({path = tmp})

	-- Sanity: exactly one user row (not two).
	local count

	for row in db2:nrows("select count(*) as n from objects where core_role = 'u'") do
		count = row.n
	end

	h.assert_eq(count, 1, 'still exactly one user row after second open')

	-- Sanity: same user pk as first open (state preserved across reopen).
	local second_pk

	for row in db2:nrows("select object_pk from objects where core_role = 'u'") do
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
	local sql = cvm.load_schema()
	h.assert_true(type(sql) == 'string', 'schema is not a string')
	h.assert_true(#sql > 100, 'schema suspiciously short: ' .. #sql .. ' chars')
	h.assert_true(sql:find('create table objects', 1, true) ~= nil, 'schema does not contain "create table objects"')
end)
