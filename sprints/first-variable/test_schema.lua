#!/usr/bin/env lua5.4

--[[
{
	"module": "test_schema",
	"role": "Standalone tests for `sprints/first-variable/schema.sql`. Exercises the sprint-local additions to the shipping schema: the `gc` column on `objects`, the `frames_drop_and_replace` trigger, and the reworked `processes_complete_after_last_frame_drop` trigger. Applies the schema to an in-memory SQLite each test, so failures are isolated per case.",
	"run": "lua5.4 sprints/first-variable/test_schema.lua (from repo root)"
}
]]

--[[
# `test_schema`

Runs a battery of assertions against the sprint's working-copy schema
(`sprints/first-variable/schema.sql`), NOT the shipping schema. Purpose
is to give the drop-and-replace + GC-marker design a place to be
exercised in isolation before any of it lands in shipping.

Test categories:

- **gc column shape.** Column exists; only `1` or null; only frames may
  carry it; markers cannot have `bucket_pk` or `stack_pk` populated.
- **frames_drop_and_replace.** Deleting a real frame plants a marker
  that inherits `parent_frame` / `process_pk` / `owner_role`. Deleting
  a marker does not plant anything.
- **processes_complete_after_last_frame_drop.** Flips `complete = 1`
  only after the LAST frame anchored to the process is gone. Drop-and-
  replace's marker keeps the process live until the marker itself
  drops.
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/first-variable/schema.sql'


-- ------------------------------------------------------------
-- test harness
-- ------------------------------------------------------------

local function slurp(path)
	local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
	local text = f:read('*a')
	f:close()
	return text
end

local function fresh_db()
	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	db:exec('pragma recursive_triggers = on;')
	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, 'schema apply failed: ' .. tostring(db:errmsg()))
	return db
end

local function seed_user(db)
	-- The sprint schema seeds the three core roles inline (engine, cache,
	-- user) at the bottom of the CREATE / INSERT sequence. Just look up
	-- the user pk.
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		return row.object_pk
	end
	error('user seed not present in schema')
end

local function insert_process(db)
	-- Use RETURNING so we get exactly the newly-inserted row's pk. A
	-- plain `select from processes` returns every process and picks
	-- whichever the iteration ends on — which broke when a test seeded
	-- more than one process.
	local pk
	for row in db:nrows("insert into processes default values returning process_pk") do
		pk = row.process_pk
	end
	return pk
end

local function insert_frame_0(db, process_pk, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, process_pk, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. process_pk .. "', '" .. user_pk .. "');"
	local rc = db:exec(sql)
	assert(rc == sqlite.OK, 'insert frame 0 failed: ' .. tostring(db:errmsg()))
	local pk
	for row in db:nrows("select object_pk from objects where primitive = 'f' and process_pk = '" .. process_pk .. "'") do
		pk = row.object_pk
	end
	return pk
end

local function count(db, sql)
	local n = 0
	for row in db:nrows(sql) do
		n = row.count or row.n or 0
	end
	return n
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end


-- ------------------------------------------------------------
-- test runner
-- ------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		passed = passed + 1
		print('  PASS  ' .. name)
	else
		failed = failed + 1
		print('  FAIL  ' .. name)
		table.insert(failures, {name = name, err = err})
	end
end

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


-- ============================================================
-- gc column shape
-- ============================================================

test('gc column exists on objects', function()
	local db = fresh_db()
	local found = false

	for row in db:nrows("pragma table_info(objects)") do
		if row.name == 'gc' then
			found = true
			break
		end
	end

	assert(found, 'objects table has no gc column')
	db:close()
end)

test('gc defaults to null on a real frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	insert_frame_0(db, process_pk, user_pk)

	local row = first(db, "select gc from objects where primitive = 'f'")
	assert(row.gc == nil, 'expected gc null; got ' .. tostring(row.gc))
	db:close()
end)

test('gc = 1 is accepted on a frame (marker: no ast, no stmt_idx)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'marker insert should succeed')
	db:close()
end)

test('gc = 0 is rejected (only 1 is valid)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 0, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'gc = 0 should be rejected')
	db:close()
end)

test('marker with ast set is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local sql = "insert into objects (primitive, gc, ast, process_pk, owner_role) "
		.. "values ('f', 1, '[]', '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'marker with ast=[] should be rejected')
	db:close()
end)

test('marker with stmt_idx set is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local sql = "insert into objects (primitive, gc, stmt_idx, process_pk, owner_role) "
		.. "values ('f', 1, 0, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'marker with stmt_idx=0 should be rejected')
	db:close()
end)

test('marker with bucket_pk set at INSERT is rejected', function()
	-- Direct-INSERT variant; the denormalize path is covered separately.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	-- Some bucket_pk value — any UUID-shaped string will trip the check.
	local sql = "insert into objects (primitive, gc, bucket_pk, process_pk, owner_role) "
		.. "values ('f', 1, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', '"
		.. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'marker with bucket_pk should be rejected')
	db:close()
end)

test('marker with stack_pk set at INSERT is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	local sql = "insert into objects (primitive, gc, stack_pk, process_pk, owner_role) "
		.. "values ('f', 1, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', '"
		.. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'marker with stack_pk should be rejected')
	db:close()
end)

test('gc = 1 on a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, gc, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'hash row with gc = 1 should be rejected')
	db:close()
end)

test('gc is immutable — cannot flip a real frame to a marker', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set gc = 1 where object_pk = '" .. frame_pk .. "';"),
		db,
		'objects_gc_immutable',
		'flipping a real frame to a marker should be rejected')
	db:close()
end)

test('gc is immutable — cannot flip a marker to a real frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'marker insert')
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	assert_fails_with(
		db:exec("update objects set gc = null where object_pk = '" .. marker_pk .. "';"),
		db,
		'objects_gc_immutable',
		'flipping a marker to a real frame should be rejected')
	db:close()
end)

test('gc is immutable — no-op update (same value) is silently accepted', function()
	-- Reject-on-actual-change: SET gc = <current value> does nothing.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. frame_pk .. "';"),
		db, 'no-op re-write of gc on a real frame should be accepted')

	local sql = "insert into objects (primitive, gc, parent_frame, owner_role) "
		.. "values ('f', 1, '" .. frame_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'marker insert')
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	assert_ok(db:exec("update objects set gc = 1 where object_pk = '" .. marker_pk .. "';"),
		db, 'no-op re-write of gc on a marker should be accepted')
	db:close()
end)

test('parent_frame is immutable — cannot reparent a frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk_a = insert_process(db)
	local frame_a = insert_frame_0(db, process_pk_a, user_pk)

	-- push a nested frame under frame_a
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. frame_a .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested frame insert')
	local nested_pk = first(db, "select object_pk from objects where parent_frame = '" .. frame_a .. "'").object_pk

	-- create a second process-anchored frame we could try to reparent to
	local process_pk_b = insert_process(db)
	local frame_b = insert_frame_0(db, process_pk_b, user_pk)

	assert_fails_with(
		db:exec("update objects set parent_frame = '" .. frame_b .. "' where object_pk = '" .. nested_pk .. "';"),
		db,
		'objects_parent_frame_immutable',
		'reparenting a frame should be rejected')
	db:close()
end)

test('parent_frame is immutable — no-op update (same value) is silently accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_a = insert_frame_0(db, process_pk, user_pk)

	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. frame_a .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested frame insert')
	local nested_pk = first(db, "select object_pk from objects where parent_frame = '" .. frame_a .. "'").object_pk

	assert_ok(
		db:exec("update objects set parent_frame = '" .. frame_a .. "' where object_pk = '" .. nested_pk .. "';"),
		db, 'no-op re-write of parent_frame should be accepted')
	db:close()
end)

test('process_pk is immutable — cannot move a frame between processes', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk_a = insert_process(db)
	local frame_a = insert_frame_0(db, process_pk_a, user_pk)
	local process_pk_b = insert_process(db)

	assert_fails_with(
		db:exec("update objects set process_pk = '" .. process_pk_b .. "' where object_pk = '" .. frame_a .. "';"),
		db,
		'objects_process_pk_immutable',
		'moving a frame between processes should be rejected')
	db:close()
end)

test('process_pk is immutable — no-op update (same value) is silently accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(
		db:exec("update objects set process_pk = '" .. process_pk .. "' where object_pk = '" .. frame_pk .. "';"),
		db, 'no-op re-write of process_pk should be accepted')
	db:close()
end)

test('marker cannot get a bucket attached (denormalize into bucket_pk fails the check)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	-- Insert marker.
	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'marker insert should succeed')
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	-- Try to insert a bucket that points at the marker. The denormalize
	-- trigger will UPDATE the marker's bucket_pk, which trips the marker's
	-- `gc is null or bucket_pk is null` check.
	local bsql = "insert into objects (primitive, bucket_for, owner_role) "
		.. "values ('h', '" .. marker_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(bsql), db, 'CHECK constraint',
		'attaching a bucket to a marker should be rejected')
	db:close()
end)


-- ============================================================
-- frame parentage invariants
--   1. Every frame has exactly one parent — parent_frame XOR process_pk.
--   2. A parent (frame or process) has at most one child frame.
-- ============================================================

test('frame with BOTH parent_frame and process_pk is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	-- Try a nested frame that also carries process_pk — should fail
	-- the exactly-one-parent check.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, process_pk, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'a frame with both parent_frame and process_pk should be rejected')
	db:close()
end)

test('frame with NEITHER parent_frame nor process_pk is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local sql = "insert into objects (primitive, ast, stmt_idx, owner_role) "
		.. "values ('f', '[]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'an anchorless frame should be rejected')
	db:close()
end)

test('two frames anchored to the same process is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	insert_frame_0(db, process_pk, user_pk)

	-- Try a second frame anchored to the same process.
	local sql = "insert into objects (primitive, ast, stmt_idx, process_pk, owner_role) "
		.. "values ('f', '[]', 0, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'UNIQUE',
		'a second process-anchored frame should be rejected')
	db:close()
end)


-- ============================================================
-- frames_drop_and_replace
-- ============================================================

test('deleting a frame plants a marker inheriting process_pk', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"), db)

	local marker = first(db, "select gc, ast, stmt_idx, process_pk, parent_frame, owner_role "
		.. "from objects where gc = 1")

	assert(marker ~= nil, 'no marker was inserted after frame delete')
	assert(marker.gc == 1, 'marker gc should be 1')
	assert(marker.ast == nil, 'marker ast should be null')
	assert(marker.stmt_idx == nil, 'marker stmt_idx should be null')
	assert(marker.process_pk == process_pk, 'marker should inherit process_pk')
	assert(marker.parent_frame == nil, 'frame 0 marker should have null parent_frame')
	assert(marker.owner_role == user_pk, 'marker should inherit owner_role')
	db:close()
end)

test('deleting a nested frame plants a marker inheriting parent_frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	-- Nested frame: no process_pk, parent_frame = parent_pk.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested frame insert')
	local child_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. child_pk .. "';"), db)

	local marker = first(db, "select gc, process_pk, parent_frame from objects where gc = 1")
	assert(marker ~= nil, 'no marker after nested frame delete')
	assert(marker.process_pk == nil, 'nested marker should have null process_pk')
	assert(marker.parent_frame == parent_pk, 'nested marker should inherit parent_frame')
	db:close()
end)

local function push_marker(db, parent_pk, user_pk)
	local sql = "insert into objects (primitive, gc, parent_frame, owner_role) "
		.. "values ('f', 1, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert(db:exec(sql) == sqlite.OK, 'push marker failed: ' .. tostring(db:errmsg()))
end

test('a frame at INSERT must have stmt_idx = 0', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	-- stmt_idx = 5 rejected
	local sql = "insert into objects (primitive, ast, stmt_idx, process_pk, owner_role) "
		.. "values ('f', '[]', 5, '" .. process_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'frames_stmt_idx_must_start_at_zero',
		'frame born at stmt_idx = 5 should be rejected')

	-- stmt_idx = null (omitted) rejected
	sql = "insert into objects (primitive, ast, process_pk, owner_role) "
		.. "values ('f', '[]', '" .. process_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'frames_stmt_idx_must_start_at_zero',
		'frame born with null stmt_idx should be rejected')

	-- stmt_idx = 0 accepted (sanity)
	sql = "insert into objects (primitive, ast, stmt_idx, process_pk, owner_role) "
		.. "values ('f', '[]', 0, '" .. process_pk .. "', '" .. user_pk .. "')"
	assert_ok(db:exec(sql), db, 'frame born at stmt_idx = 0 should be accepted')
	db:close()
end)

--[[
Walker's canonical advance shape — coupled stmt_idx increment + dcok = 1.
Wrapped so tests read at the intent level, not the mechanism.
]]
local function walker_advance(db, parent_pk, new_stmt_idx)
	local sql = "update objects set stmt_idx = " .. new_stmt_idx
		.. ", dcok = 1 where object_pk = '" .. parent_pk .. "'"
	return db:exec(sql)
end

test('stmt_idx can advance by +1 (with a marker child to sweep)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_ok(walker_advance(db, parent_pk, 1), db)
	db:close()
end)

test('stmt_idx skip (0 → 5) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		walker_advance(db, parent_pk, 5),
		db,
		'frames_stmt_idx_',
		'skipping stmt_idx should be rejected')
	db:close()
end)

test('stmt_idx rewind is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	-- advance to 1 legitimately (sweeps the marker), then try to rewind
	assert_ok(walker_advance(db, parent_pk, 1), db)
	push_marker(db, parent_pk, user_pk)  -- push a new marker so the rewind attempt gets to the +1 rule, not marker-required
	assert_fails_with(
		walker_advance(db, parent_pk, 0),
		db,
		'frames_stmt_idx_',
		'rewinding stmt_idx should be rejected')
	db:close()
end)

test('stmt_idx no-op update (same value) is silently accepted', function()
	-- No advance semantics fire: no marker required, no marker deleted.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	-- Push a marker so we can verify it survives the no-op.
	push_marker(db, parent_pk, user_pk)
	local marker_pk_before = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "' and gc = 1").object_pk

	assert_ok(
		db:exec("update objects set stmt_idx = 0 where object_pk = '" .. parent_pk .. "';"),
		db, 'no-op stmt_idx update should be accepted')

	-- Marker should still be there — no advance side effect fired.
	local marker_pk_after = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "' and gc = 1")
	assert(marker_pk_after ~= nil, 'marker should survive a no-op stmt_idx update')
	assert(marker_pk_after.object_pk == marker_pk_before, 'exact same marker row')
	db:close()
end)

test('stmt_idx no-op update on a frame with no marker is also accepted', function()
	-- The marker-required check must ALSO be gated on actual change,
	-- otherwise a no-op UPDATE would demand a marker that isn't there.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(
		db:exec("update objects set stmt_idx = 0 where object_pk = '" .. parent_pk .. "';"),
		db, 'no-op stmt_idx update should be accepted even without a marker child')
	db:close()
end)

test('advancing stmt_idx deletes the marker child in the same op', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	push_marker(db, parent_pk, user_pk)
	local marker_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(walker_advance(db, parent_pk, 1), db)

	-- Marker should be gone; no replacement (marker drops are terminal).
	local count_row = first(db, "select count(*) as n from objects where object_pk = '" .. marker_pk .. "'")
	assert(tonumber(count_row.n) == 0, 'marker should be deleted; still present')

	local child_row = first(db, "select count(*) as n from objects where parent_frame = '" .. parent_pk .. "'")
	assert(tonumber(child_row.n) == 0, 'no child should remain; got ' .. tostring(child_row.n))

	-- dcok reset to null by the AFTER-DELETE trigger.
	local parent_row = first(db, "select dcok from objects where object_pk = '" .. parent_pk .. "'")
	assert(parent_row.dcok == nil, 'parent.dcok should be reset to null after the sweep')
	db:close()
end)

test('advancing stmt_idx with a real (non-marker) child is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db)
	local child_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_fails_with(
		walker_advance(db, parent_pk, 1),
		db,
		'frames_stmt_idx_requires_marker_child',
		'advancing over a real child should be rejected')

	local still_there = first(db, "select gc from objects where object_pk = '" .. child_pk .. "'")
	assert(still_there ~= nil, 'real child should still be present')
	assert(still_there.gc == nil, 'child should still be a real frame')
	db:close()
end)

test('advancing stmt_idx with no child at all is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	assert_fails_with(
		walker_advance(db, parent_pk, 1),
		db,
		'frames_stmt_idx_requires_marker_child',
		'advancing without a child should be rejected')
	db:close()
end)

test('a parent frame can only have one child at a time', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	-- First child.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'first child insert')

	-- Second child under the same parent.
	assert_fails_with(db:exec(sql), db, 'UNIQUE',
		'second child under the same parent should be rejected')
	db:close()
end)

test('drop-and-replace lands cleanly under the unique-child index', function()
	-- Deleting the current child frees the parent_frame slot; the AFTER
	-- DELETE trigger then inserts the marker into that slot without
	-- tripping the unique index.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db)
	local child_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. child_pk .. "';"), db)

	local child_count = first(db, "select count(*) as n from objects where parent_frame = '" .. parent_pk .. "'")
	assert(tonumber(child_count.n) == 1, 'expected exactly one child (the marker); got ' .. tostring(child_count.n))

	local marker = first(db, "select gc from objects where parent_frame = '" .. parent_pk .. "'")
	assert(marker.gc == 1, 'the remaining child should be the GC marker')
	db:close()
end)

test('deleting a marker does NOT plant another marker', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	-- Insert marker directly (process-anchored).
	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'marker insert')
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. marker_pk .. "';"), db)

	local remaining = first(db, "select count(*) as n from objects where gc = 1")
	assert(tonumber(remaining.n) == 0, 'expected 0 markers after marker delete; got ' .. tostring(remaining.n))
	db:close()
end)


-- ============================================================
-- processes_complete_after_last_frame_drop
-- ============================================================

test('deleting frame 0 keeps complete = 0 (marker replaces it)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"), db)

	local proc = first(db, "select complete from processes where process_pk = '" .. process_pk .. "'")
	assert(tonumber(proc.complete) == 0,
		'expected complete = 0 (marker keeps process live); got ' .. tostring(proc.complete))
	db:close()
end)

test('deleting the replacement marker flips complete = 1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	assert_ok(db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"), db)
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. marker_pk .. "';"), db)

	local proc = first(db, "select complete from processes where process_pk = '" .. process_pk .. "'")
	assert(tonumber(proc.complete) == 1,
		'expected complete = 1 after marker drop; got ' .. tostring(proc.complete))
	db:close()
end)

test('deleting a nested frame does NOT flip complete (parent still live)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested frame')
	local child_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. child_pk .. "';"), db)

	local proc = first(db, "select complete from processes where process_pk = '" .. process_pk .. "'")
	assert(tonumber(proc.complete) == 0,
		'expected complete = 0 (frame 0 still live); got ' .. tostring(proc.complete))
	db:close()
end)


-- ============================================================
-- dcok — nested-marker-delete authorization
-- ============================================================

test('dcok column exists on objects', function()
	local db = fresh_db()
	local found = false
	for row in db:nrows("pragma table_info(objects)") do
		if row.name == 'dcok' then found = true; break end
	end
	assert(found, 'objects should have a dcok column')
	db:close()
end)

test('dcok defaults to null on a fresh frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local frame_pk = insert_frame_0(db, process_pk, user_pk)

	local row = first(db, "select dcok from objects where object_pk = '" .. frame_pk .. "'")
	assert(row.dcok == nil, 'expected dcok null; got ' .. tostring(row.dcok))
	db:close()
end)

test('dcok = 0 is rejected (only 1 or null)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	local sql = "insert into objects (primitive, ast, stmt_idx, dcok, process_pk, owner_role) "
		.. "values ('f', '[]', 0, 0, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'dcok = 0 should be rejected')
	db:close()
end)

test('dcok on a non-frame is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local sql = "insert into objects (primitive, dcok, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'dcok on a hash row should be rejected')
	db:close()
end)

test('dcok on a marker is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	local sql = "insert into objects (primitive, gc, dcok, process_pk, owner_role) "
		.. "values ('f', 1, 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'dcok on a marker should be rejected')
	db:close()
end)


-- ============================================================
-- dcok coupling with stmt_idx advance
-- ============================================================

test('advance without dcok is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_requires_dcok',
		'advance without dcok=1 should be rejected')
	db:close()
end)

test('advance with dcok explicitly null is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = 1, dcok = null where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_requires_dcok',
		'advance with explicit dcok=null should be rejected')
	db:close()
end)

test('setting dcok=1 alone (no stmt_idx change) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set dcok = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_dcok_only_with_advance',
		'setting dcok=1 without stmt_idx change should be rejected')
	db:close()
end)

test('setting dcok=1 with stmt_idx = stmt_idx (no-op mention) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = stmt_idx, dcok = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_dcok_only_with_advance',
		'setting dcok=1 with stmt_idx unchanged should be rejected')
	db:close()
end)


-- ============================================================
-- dcok gate on nested marker deletion
-- ============================================================

test('direct DELETE of a nested marker is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	local marker_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. marker_pk .. "';"),
		db, 'markers_no_direct_delete',
		'direct nested-marker DELETE should be rejected')

	-- Marker still there.
	local still = first(db, "select object_pk from objects where object_pk = '" .. marker_pk .. "'")
	assert(still ~= nil, 'nested marker should still exist after rejected delete')
	db:close()
end)

test('direct DELETE of a ROOT marker is still allowed (process-completion path)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)

	-- Insert a root marker directly.
	local sql = "insert into objects (primitive, gc, process_pk, owner_role) "
		.. "values ('f', 1, '" .. process_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'root marker insert')
	local marker_pk = first(db, "select object_pk from objects where gc = 1").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. marker_pk .. "';"), db,
		'root marker delete should be allowed')

	-- And the completion trigger flipped complete=1.
	local proc = first(db, "select complete from processes where process_pk = '" .. process_pk .. "'")
	assert(tonumber(proc.complete) == 1, 'root marker delete should complete the process')
	db:close()
end)


-- ============================================================
-- dcok lifecycle
-- ============================================================

test('dcok is null at rest before AND after a legitimate advance', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	local before = first(db, "select dcok from objects where object_pk = '" .. parent_pk .. "'")
	assert(before.dcok == nil, 'dcok should be null before advance')

	assert_ok(walker_advance(db, parent_pk, 1), db)

	local after = first(db, "select dcok from objects where object_pk = '" .. parent_pk .. "'")
	assert(after.dcok == nil, 'dcok should be null after the sweep completes')
	db:close()
end)

test('two full advance cycles work in sequence', function()
	-- Verifies dcok reset doesn't leave the parent stuck for the next cycle.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local process_pk = insert_process(db)
	local parent_pk = insert_frame_0(db, process_pk, user_pk)

	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db)

	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 2), db)

	-- No children, dcok null.
	local n = first(db, "select count(*) as n from objects where parent_frame = '" .. parent_pk .. "'")
	assert(tonumber(n.n) == 0, 'no children after both cycles')
	local p = first(db, "select dcok, stmt_idx from objects where object_pk = '" .. parent_pk .. "'")
	assert(p.dcok == nil, 'dcok should be null')
	assert(tonumber(p.stmt_idx) == 2, 'stmt_idx should be 2 after two advances')
	db:close()
end)


-- ============================================================
-- no-op UPDATE sweep on whole-row-immutable / append-only triggers
--   All should accept a re-write of the same values silently.
-- ============================================================

test('refs: no-op UPDATE (same values) is silently accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local sql = "insert into objects (primitive, owner_role) values ('h', '" .. user_pk .. "') returning object_pk"
	local hash_pk
	for row in db:nrows(sql) do hash_pk = row.object_pk end
	sql = "insert into objects (primitive, scalar_type, scalar_value, owner_role) values ('o', 'n', 1, '" .. user_pk .. "') returning object_pk"
	local scalar_pk
	for row in db:nrows(sql) do scalar_pk = row.object_pk end
	sql = "insert into refs (parent, child, key, idx) values ('" .. hash_pk .. "', '" .. scalar_pk .. "', 'x', 0)"
	assert_ok(db:exec(sql), db, 'refs insert')

	local ref = first(db, "select ref_pk, parent, child, key, idx from refs")
	local upd = string.format(
		"update refs set parent = '%s', child = '%s', key = '%s', idx = %d where ref_pk = %d",
		ref.parent, ref.child, ref.key, ref.idx, ref.ref_pk)
	assert_ok(db:exec(upd), db, 'no-op refs UPDATE should be accepted')

	-- Actual change should still fail.
	assert_fails_with(
		db:exec("update refs set key = 'y' where ref_pk = " .. ref.ref_pk),
		db, 'refs_immutable',
		'actual change to refs should be rejected')
	db:close()
end)

test('cvm: no-op UPDATE (same values) is silently accepted', function()
	local db = fresh_db()
	-- The schema seeds ('schema', '9.0').
	assert_ok(db:exec("update cvm set key = 'schema', value = '9.0' where key = 'schema'"),
		db, 'no-op cvm UPDATE should be accepted')
	assert_fails_with(
		db:exec("update cvm set value = '10.0' where key = 'schema'"),
		db, 'cvm_append_only',
		'actual change to cvm should be rejected')
	db:close()
end)

test('instance_listeners: no-op UPDATE is silently accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, owner_role) values ('h', '" .. user_pk .. "') returning object_pk"
	local a_pk, b_pk
	for row in db:nrows(sql) do a_pk = row.object_pk end
	for row in db:nrows(sql) do b_pk = row.object_pk end

	assert_ok(db:exec(string.format(
		"insert into instance_listeners (broadcaster, listener, event_name, method_name) "
		.. "values ('%s', '%s', 'e', 'm')", a_pk, b_pk)), db, 'listener insert')

	local reg = first(db, "select reg_pk, broadcaster, listener, event_name, method_name from instance_listeners")
	local upd = string.format(
		"update instance_listeners set broadcaster = '%s', listener = '%s', event_name = '%s', method_name = '%s' where reg_pk = %d",
		reg.broadcaster, reg.listener, reg.event_name, reg.method_name, reg.reg_pk)
	assert_ok(db:exec(upd), db, 'no-op instance_listeners UPDATE should be accepted')

	assert_fails_with(
		db:exec("update instance_listeners set event_name = 'e2' where reg_pk = " .. reg.reg_pk),
		db, 'instance_listeners_no_update',
		'actual change to instance_listeners should be rejected')
	db:close()
end)

test('class_listeners: no-op UPDATE is silently accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, owner_role) values ('h', '" .. user_pk .. "') returning object_pk"
	local class_pk, listener_pk
	for row in db:nrows(sql) do class_pk = row.object_pk end
	for row in db:nrows(sql) do listener_pk = row.object_pk end

	assert_ok(db:exec(string.format(
		"insert into class_listeners (class, listener, event_name, method_name) "
		.. "values ('%s', '%s', 'e', 'm')", class_pk, listener_pk)), db, 'class listener insert')

	local reg = first(db, "select reg_pk, class, listener, event_name, method_name from class_listeners")
	local upd = string.format(
		"update class_listeners set class = '%s', listener = '%s', event_name = '%s', method_name = '%s' where reg_pk = %d",
		reg.class, reg.listener, reg.event_name, reg.method_name, reg.reg_pk)
	assert_ok(db:exec(upd), db, 'no-op class_listeners UPDATE should be accepted')

	assert_fails_with(
		db:exec("update class_listeners set event_name = 'e2' where reg_pk = " .. reg.reg_pk),
		db, 'class_listeners_no_update',
		'actual change to class_listeners should be rejected')
	db:close()
end)

test('core-role row: no-op UPDATE is silently accepted', function()
	local db = fresh_db()

	-- Re-write the user role's persistent = 1 (its current value).
	assert_ok(
		db:exec("update objects set persistent = 1 where core_role = 'u'"),
		db, 'no-op UPDATE on a core-role row should be accepted')

	-- Actual change (persistent = null) should be rejected.
	assert_fails_with(
		db:exec("update objects set persistent = null where core_role = 'u'"),
		db, 'root_role_cannot_be_updated',
		'actual change to a core-role row should be rejected')
	db:close()
end)


-- ============================================================
-- report
-- ============================================================

print()
print(string.format('TOTAL: %d passed, %d failed', passed, failed))

if failed > 0 then
	print()
	print('Failures:')

	for _, f in ipairs(failures) do
		print('  [' .. f.name .. ']')

		for line in tostring(f.err):gmatch('[^\n]+') do
			print('    ' .. line)
		end
	end

	os.exit(1)
end

os.exit(0)
