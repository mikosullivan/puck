#!/usr/bin/env lua5.4

--[[
{
	"module": "test_debug_log",
	"role": "Tests for the debug_log table: shape (entry_pk PK / object_pk FK / note NOT NULL), valid insert, autoincrement, NOT NULL rejection, missing FK rejection, non-cap object_pk rejection via debug_log_object_pk_must_be_cap, ON DELETE CASCADE from the process cap, and DEFAULT (current_process_pk()) auto-populating object_pk when the caller omits it.",
	"run": "lua5.4 production/tests/main/lua/engine/run.lua (from repo root)"
}
]]

local sqlite             = require('lsqlite3')
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')

local SCHEMA_PATH    = 'production/src/engine/cvm/sqlite/schema.sql'
local PREFLIGHT_PATH = 'production/src/engine/cvm/sqlite/preflight.sql'


-- ------------------------------------------------------------
-- harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

-- Per-connection holder for the current-process pk. The UDF reads
-- through this table so tests can swap the returned pk mid-connection
-- without re-registering the callback.
local _current_process_pk_holders = setmetatable({}, {__mode = 'k'})

local function schema_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')

	local holder = {pk = nil}
	_current_process_pk_holders[db] = holder
	current_process_pk.register(db, function() return holder.pk end)

	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))

	rcvr = db:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, 'preflight apply failed: ' .. tostring(db:errmsg()))
	return db
end

--[[
Point the current-process pk at `cap_pk` for `db`. The UDF reads
through the shared holder, so the swap is visible to every subsequent
SQL call without re-registering the callback.
]]
local function set_current_process(db, cap_pk)
	local holder = _current_process_pk_holders[db]
	assert(holder, 'set_current_process: db not from schema_db()')
	holder.pk = cap_pk
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end

local function scalar(db, sql)
	for row in db:rows(sql) do
		return row[1]
	end
	return nil
end


local h = require('helpers')
local test = h.test

local function assert_ok(rc, db, note)
	if rc ~= sqlite.OK then
		error((note or 'expected OK') .. ': ' .. tostring(db:errmsg()), 2)
	end
end

local function assert_fails_with(rc, db, expected_substr, note)
	if rc == sqlite.OK then
		error((note or 'expected failure') .. ' — but the operation succeeded', 2)
	end

	local msg = db:errmsg()

	if not msg:find(expected_substr, 1, true) then
		error(
			(note or 'wrong error') .. '\n'
			.. '  expected substring: ' .. expected_substr .. '\n'
			.. '  actual: ' .. msg,
			2
		)
	end
end


-- ------------------------------------------------------------
-- fixtures
-- ------------------------------------------------------------

local function seed_user(db)
	return first(db, "select object_pk from objects where role_core = 'u'").object_pk
end

--[[
Insert a fresh cap frame. Matches what engine.run seeds — primitive
'f', frame_process_cap 1, empty-array frame_ast, frame_stmt_idx 0, owned by the user
core role.
]]
local function seed_cap(db, user_pk)
	return first(db,
		"insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', 1, '[null]', 0, '" .. user_pk .. "') returning object_pk").object_pk
end


-- ============================================================
-- shape
-- ============================================================

test('debug_log table exists', function()
	local db = schema_db()

	h.assert_eq(
		tonumber(scalar(db, "select count(*) from sqlite_master where type = 'table' and name = 'debug_log'")),
		1, 'expected debug_log table')

	db:close()
end)

test('debug_log columns: entry_pk PK, object_pk NOT NULL, note NOT NULL', function()
	local db = schema_db()
	local cols = {}

	for row in db:nrows("pragma table_info(debug_log)") do
		cols[row.name] = row
	end

	h.assert_true(cols.entry_pk ~= nil,             'entry_pk column')
	h.assert_true(cols.object_pk ~= nil,            'object_pk column')
	h.assert_true(cols.note ~= nil,                 'note column')
	h.assert_eq(tonumber(cols.entry_pk.pk),  1,     'entry_pk is PK')
	h.assert_eq(tonumber(cols.object_pk.notnull), 1, 'object_pk is NOT NULL')
	h.assert_eq(tonumber(cols.note.notnull), 1,     'note is NOT NULL')

	db:close()
end)

test('debug_log_object_pk index exists', function()
	local db = schema_db()

	h.assert_eq(
		tonumber(scalar(db, "select count(*) from sqlite_master where type = 'index' and name = 'debug_log_object_pk'")),
		1, 'expected debug_log_object_pk index')

	db:close()
end)


-- ============================================================
-- valid insert
-- ============================================================

test('inserting a row with a real cap and a note succeeds', function()
	local db = schema_db()
	local cap_pk = seed_cap(db, seed_user(db))

	assert_ok(
		db:exec("insert into debug_log (object_pk, note) values ('" .. cap_pk .. "', 'hello')"),
		db, 'debug_log insert')

	local row = first(db,
		"select entry_pk, object_pk, note from debug_log where object_pk = '" .. cap_pk .. "'")
	h.assert_true(row ~= nil,             'row readable back')
	h.assert_eq(row.object_pk, cap_pk,    'row.object_pk matches')
	h.assert_eq(row.note, 'hello',        'row.note matches')
	h.assert_true(row.entry_pk ~= nil,    'entry_pk auto-assigned')

	db:close()
end)

test('entry_pk auto-increments across rows', function()
	local db = schema_db()
	local cap_pk = seed_cap(db, seed_user(db))

	db:exec("insert into debug_log (object_pk, note) values ('" .. cap_pk .. "', 'first')")
	db:exec("insert into debug_log (object_pk, note) values ('" .. cap_pk .. "', 'second')")

	local pks = {}
	for row in db:nrows("select entry_pk from debug_log order by entry_pk") do
		table.insert(pks, tonumber(row.entry_pk))
	end

	h.assert_eq(#pks, 2,           'two rows')
	h.assert_true(pks[2] > pks[1], 'second entry_pk greater')

	db:close()
end)


-- ============================================================
-- constraint violations
-- ============================================================

test('null note is rejected', function()
	local db = schema_db()
	local cap_pk = seed_cap(db, seed_user(db))

	assert_fails_with(
		db:exec("insert into debug_log (object_pk, note) values ('" .. cap_pk .. "', null)"),
		db, 'NOT NULL',
		'null note should be rejected')

	db:close()
end)

test('omitting note is rejected (NOT NULL, no default)', function()
	local db = schema_db()
	local cap_pk = seed_cap(db, seed_user(db))

	assert_fails_with(
		db:exec("insert into debug_log (object_pk) values ('" .. cap_pk .. "')"),
		db, 'NOT NULL',
		'omitted note should be rejected')

	db:close()
end)

test('missing object_pk is rejected', function()
	-- The cap-check trigger fires ahead of the FK for a missing target
	-- — its subquery returns nothing, so `is not 1` evaluates true and
	-- the trigger aborts before the FK gets a chance. Same semantic
	-- (the object doesn't qualify as a cap); the trigger's message is
	-- more specific than the generic FOREIGN KEY constraint one.
	local db = schema_db()
	seed_cap(db, seed_user(db))  -- ensure a cap exists elsewhere

	assert_fails_with(
		db:exec("insert into debug_log (object_pk, note) "
			.. "values ('00000000-0000-4000-8000-000000000000', 'hello')"),
		db, 'debug_log_object_pk_must_be_cap',
		'missing object_pk should be rejected')

	db:close()
end)

test('non-cap object_pk is rejected by the cap-check trigger', function()
	local db = schema_db()
	local user_pk = seed_user(db)

	local scalar_pk = first(db,
		"insert into objects (base, scalar_number, owner_role) values ('o', 42, '" .. user_pk .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("insert into debug_log (object_pk, note) values ('" .. scalar_pk .. "', 'hello')"),
		db, 'debug_log_object_pk_must_be_cap',
		'non-cap object_pk should be rejected')

	db:close()
end)

test('nested-frame object_pk (primitive f, no frame_process_cap) is rejected', function()
	local db = schema_db()
	local user_pk = seed_user(db)
	local cap_pk  = seed_cap(db, user_pk)

	local frame_pk = first(db,
		"insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("insert into debug_log (object_pk, note) values ('" .. frame_pk .. "', 'hello')"),
		db, 'debug_log_object_pk_must_be_cap',
		'nested-frame object_pk should be rejected')

	db:close()
end)


-- ============================================================
-- ON DELETE CASCADE
-- ============================================================

test('deleting a process cap cascades to its debug_log rows', function()
	local db = schema_db()
	local user_pk = seed_user(db)
	local cap_a = seed_cap(db, user_pk)
	local cap_b = seed_cap(db, user_pk)

	db:exec("insert into debug_log (object_pk, note) values ('" .. cap_a .. "', 'a1')")
	db:exec("insert into debug_log (object_pk, note) values ('" .. cap_a .. "', 'a2')")
	db:exec("insert into debug_log (object_pk, note) values ('" .. cap_b .. "', 'b1')")

	h.assert_eq(tonumber(scalar(db, 'select count(*) from debug_log')), 3,
		'three rows to start')

	assert_ok(
		db:exec("delete from objects where object_pk = '" .. cap_a .. "'"),
		db, 'cap_a delete')

	h.assert_eq(tonumber(scalar(db, 'select count(*) from debug_log')), 1,
		'cap_a rows cascaded away')
	h.assert_eq(
		first(db, 'select object_pk from debug_log').object_pk, cap_b,
		'cap_b row survives')

	db:close()
end)


-- ============================================================
-- DEFAULT (current_process_pk()) — object_pk auto-populates from
-- the engine's UDF when the caller omits it.
-- ============================================================

test('omitting object_pk populates it from current_process_pk()', function()
	local db = schema_db()
	local user_pk = seed_user(db)
	local cap_pk  = seed_cap(db, user_pk)
	set_current_process(db, cap_pk)

	-- Insert with only `note` — no object_pk. The DEFAULT should fire.
	assert_ok(
		db:exec("insert into debug_log (note) values ('hello')"),
		db, 'default-only insert should succeed')

	local row = first(db, "select object_pk, note from debug_log")
	h.assert_eq(row.object_pk, cap_pk, 'object_pk should equal the current process cap')
	h.assert_eq(row.note, 'hello',     'note should carry the caller value')

	db:close()
end)

test('omitting object_pk when current_process_pk() returns nil is rejected', function()
	-- Holder starts at nil; UDF returns nil; DEFAULT lands nil into
	-- the column. The cap-check trigger's WHEN clause evaluates the
	-- object-lookup subquery to nothing (nothing joins on NULL), and
	-- `is not 1` on null → true, so the trigger aborts before NOT
	-- NULL gets its turn. Same "not a cap" semantic as an
	-- explicit-null insert or a missing-target insert.
	local db = schema_db()
	seed_cap(db, seed_user(db))  -- cap exists, but we don't point the UDF at it

	assert_fails_with(
		db:exec("insert into debug_log (note) values ('hello')"),
		db, 'debug_log_object_pk_must_be_cap',
		'default-only insert with no current process should be rejected')

	db:close()
end)

test('explicit object_pk overrides the default', function()
	local db = schema_db()
	local user_pk = seed_user(db)
	local cap_a   = seed_cap(db, user_pk)
	local cap_b   = seed_cap(db, user_pk)
	set_current_process(db, cap_a)

	-- Explicit cap_b even though the UDF returns cap_a.
	assert_ok(
		db:exec("insert into debug_log (object_pk, note) values ('" .. cap_b .. "', 'explicit')"),
		db, 'explicit-object_pk insert')

	local row = first(db, "select object_pk from debug_log where note = 'explicit'")
	h.assert_eq(row.object_pk, cap_b, 'explicit value should win over the default')

	db:close()
end)
