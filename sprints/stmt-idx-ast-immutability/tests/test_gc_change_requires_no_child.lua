#!/usr/bin/env lua5.4

--[[
{
	"module": "test_gc_change_requires_no_child",
	"role": "Sprint-scoped tests for the new-gc-cycle rule 4: gc cannot change while a frame has a child. Bidirectional — both null→1 and 1→null are rejected. Also verifies that gc changes on childless frames still work (positive case).",
	"run": "lua5.4 sprints/stmt-idx-ast-immutability/tests/test_gc_change_requires_no_child.lua (from repo root)"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'sprints/stmt-idx-ast-immutability/src/schema.sql'


-- ------------------------------------------------------------
-- harness
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

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end


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


-- ------------------------------------------------------------
-- fixture: cap frame + a nested frame under it (the "parent"),
-- then a grandchild under the nested frame (the "child").
-- ------------------------------------------------------------

local function seed_user(db)
	return first(db, "select object_pk from objects where core_role = 'u'").object_pk
end

local function insert_cap(db, user_pk)
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do return row.object_pk end
end

local function insert_frame_under(db, parent_pk, user_pk)
	-- Length-2 ast so the frame has room to advance without hitting
	-- the auto-delete-at-terminal trigger.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}],[{\"in\":\"as\"},\"y\",{\"v\":2}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do return row.object_pk end
end


-- ============================================================
-- Reject: gc null→1 while parent has a child
-- ============================================================

test('gc null→1 with a child is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)
	local _child_pk = insert_frame_under(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_gc_change_requires_no_child',
		'gc null→1 with child rejected')
	db:close()
end)


-- ============================================================
-- Reject: gc 1→null while parent has a child
-- ============================================================

test('gc 1→null with a child is rejected', function()
	-- Setup: parent at gc=null with no children yet, set gc=1 (allowed
	-- any time under the new rules), insert a child, then try to reset
	-- gc to null. Insert order matters because rule 4 blocks changing
	-- gc after a child exists — we have to reach gc=1 BEFORE the
	-- child is inserted.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	-- Set parent gc=1 directly (no stmt_idx change needed under new rules).
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'parent gc set to 1')

	-- Now insert a child under the (gc=1) parent.
	local _child_pk = insert_frame_under(db, parent_pk, user_pk)

	-- Rule 4 (gc-change-requires-no-child) fires first, before the
	-- gc-null-requires-advance rule gets a chance.
	assert_fails_with(
		db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_gc_change_requires_no_child',
		'gc 1→null with child rejected')
	db:close()
end)


-- ============================================================
-- Accept: gc changes on a childless frame
-- ============================================================

test('gc null→1 on a childless frame is accepted (unrestricted set)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	-- No stmt_idx change required — Miko's "you can set gc to true any time."
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc null→1 on childless frame accepted')
	db:close()
end)

test('gc 1→null on a childless frame with an advance is accepted (canonical)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	-- Get to gc=1 first (unrestricted set).
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set to 1')
	-- Canonical advance: SET stmt_idx += 1, gc = null in the same UPDATE.
	assert_ok(
		db:exec("update objects set stmt_idx = 1, gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'canonical advance accepted')
	db:close()
end)


-- ============================================================
-- No-op gc write (no actual change) is not blocked even with a child
-- ============================================================

test('no-op gc write (same value) is accepted even with a child', function()
	-- Rule 4's WHEN clause tests `new.gc is not old.gc`, so a same-
	-- value re-write is silently accepted.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)
	local _child_pk = insert_frame_under(db, parent_pk, user_pk)

	-- Parent is at gc=null; setting gc=null again should be a no-op.
	assert_ok(
		db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'no-op gc write accepted')
	db:close()
end)


-- ============================================================
-- Regression: cascade-delete-children was dropped
-- ============================================================

test('setting gc=1 does NOT auto-delete children (cascade dropped)', function()
	-- Under the OLD design, `frames_gc_set_deletes_children` would
	-- sweep child frames when gc transitioned null→1. Under the new
	-- design, that cascade is dropped in favor of strict rule 4
	-- rejection. Attempting the transition with a child in place
	-- should fail (per the first test above), NOT succeed with the
	-- child silently swept.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)
	local child_pk = insert_frame_under(db, parent_pk, user_pk)

	-- Attempt to set gc=1 while a child exists (would have swept the
	-- child under the old cascade).
	local rc = db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'")
	assert(rc ~= sqlite.OK, 'transition should have been rejected under new rule 4')

	-- Child must still exist — no silent sweep.
	local child = first(db, "select object_pk from objects where object_pk = '" .. child_pk .. "'")
	assert(child ~= nil, 'child was swept — cascade must have fired (unexpected)')
	db:close()
end)


-- ============================================================
-- New: gc=null requires an advance in the same UPDATE
-- ============================================================

test('manual set gc = null (without advance) is accepted — redundant but not rejected', function()
	-- Under the auto-set design, the caller doesn't NEED to write
	-- `gc = null` on advance — the trigger does it. But writing
	-- `gc = null` manually is still allowed (subject to rule 4).
	-- It's a no-op effectively — auto-set would set it anyway on
	-- the next advance.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set to 1')

	assert_ok(
		db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'manual reset (no advance) accepted')
	db:close()
end)

test('setting gc to null WITH an advance in the same UPDATE is accepted', function()
	-- The canonical advance — matches rules 5+6. This is the ONLY path
	-- back to gc=null under the new design.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set to 1')

	assert_ok(
		db:exec("update objects set stmt_idx = 1, gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'reset paired with advance accepted')
	db:close()
end)


-- ============================================================
-- New: setting gc=1 is unrestricted (dropped frames_gc_set_requires_advance)
-- ============================================================

test('setting gc=1 without advancing stmt_idx is accepted', function()
	-- Under the OLD design, `frames_gc_set_requires_advance` required
	-- setting gc=1 to happen in the same UPDATE as a stmt_idx advance.
	-- Under the new design, gc can be set to 1 any time (subject to
	-- rules 4 and 7). No stmt_idx change needed.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'bare gc=1 accepted')
	db:close()
end)


-- ============================================================
-- Child inserts are independent of parent's gc state
-- ============================================================

test('a child frame can be inserted when parent.gc is null', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)
	-- parent is at (0, null, no children).
	local child = insert_frame_under(db, parent_pk, user_pk)
	assert(child ~= nil, 'child insert should succeed with parent.gc = null')
	db:close()
end)

test('a child frame can be inserted when parent.gc is 1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	-- Set parent gc=1 first (no children yet, so rule 4 permits).
	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'parent gc set to 1')

	-- Now insert a child under the (gc=1) parent — should be accepted.
	local child = insert_frame_under(db, parent_pk, user_pk)
	assert(child ~= nil, 'child insert should succeed with parent.gc = 1')
	db:close()
end)


-- ============================================================
-- Advance requires gc=1 (negative case)
-- ============================================================

test('advancing stmt_idx while gc is null is rejected', function()
	-- Under rule 5, the walker's advance can only fire from an
	-- (old.gc = 1) starting state. Attempting to advance from
	-- (old.gc = null) must be rejected — this is the negative case
	-- that pairs with the canonical-advance test above.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)
	-- Parent is at (stmt_idx=0, gc=null). Try to advance without first
	-- reaching gc=1.
	assert_fails_with(
		db:exec("update objects set stmt_idx = 1, gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_advance_requires_gc',
		'advance from gc=null rejected')
	db:close()
end)

test('advance with explicit gc=1 is rejected (engine bug loud-catch)', function()
	-- The auto-set would silently rewrite the caller's gc=1 to null,
	-- correcting the state but hiding the bug. Reject it instead.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set to 1')

	assert_fails_with(
		db:exec("update objects set stmt_idx = 1, gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_advance_rejects_non_null_gc',
		'advance with gc=1 rejected')
	db:close()
end)

test('bare advance (stmt_idx alone) is accepted; gc auto-sets to null', function()
	-- Under the auto-set design, the caller can advance without
	-- touching gc. The AFTER UPDATE trigger auto-sets gc = null as
	-- a side effect.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_cap(db, user_pk)
	local parent_pk = insert_frame_under(db, cap_pk, user_pk)

	assert_ok(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'gc set to 1')

	-- Bare advance — no gc column mentioned.
	assert_ok(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'bare advance accepted')

	-- Verify gc was auto-set to null.
	local row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(row.stmt_idx) == 1, 'stmt_idx should be 1; got: ' .. tostring(row.stmt_idx))
	assert(row.gc == nil, 'gc should be auto-set to null; got: ' .. tostring(row.gc))
	db:close()
end)


-- ------------------------------------------------------------
-- report
-- ------------------------------------------------------------

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
