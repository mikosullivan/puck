#!/usr/bin/env lua5.4

--[[
{
	"module": "test_schema",
	"role": "Schema tests for `src/engine/cvm/sqlite/schema.sql`. Exercises the load-bearing invariants: the `frame_gc` column and its four frame_gc-cycle rules (advance-couples-with-frame_gc, frame_gc-set-cascade-deletes-children, child-delete-requires-parent-frame_gc, frame_gc-reset-requires-no-children), the frame_parent / frame_process_cap immutability triggers, the cap-as-frame design (a frame with `frame_process_cap=1` and `frame_ast='[]'` sits atop each call stack), refs-based ownership under the b/p/s object-property shape, the scopes convention (bucket → 'scopes' → array of hashes), the hash-key identifier rule, and the frame_scoped_vars / object_bucket / object_platters / object_shadow views."
}
]]

--[[
# `test_schema`

Runs against the sprint's schema. Each test loads the schema into a fresh in-memory SQLite and exercises the specific invariant under test.

The frame_gc cycle is the load-bearing design:

1. Walker: `UPDATE frame SET frame_stmt_idx = frame_stmt_idx + 1, frame_gc = 1` — one statement, both fields.
2. `AFTER UPDATE OF frame_gc` fires: DELETE FROM objects WHERE frame_parent = frame — child (marker or completed nested call) swept.
3. Each child's `BEFORE-DELETE` checks parent.frame_gc = 1 — passes because step 2's row-update already happened.
4. Engine runs GC (needs_trace sweep, on_close callbacks eventually), adds child frames if needed, waits for them to complete.
5. Engine: `UPDATE frame SET frame_gc = null` — requires no children.

Every state between steps is a legal at-rest state. Bypass paths get rejected.
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

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

--[[
Fresh CVM DB. Pragmas set, schema and preflight applied. A shared
mutable holder table stores the "current process cap" for each db
handle; the UDF is registered once per connection with a closure
that reads through the holder, and tests swap the current process
by calling `set_current_process(db, cap_pk)` which writes to the
holder. Avoids the lsqlite3 create_function replacement quirk where
re-registering the callback doesn't reliably override across
statement boundaries.
]]
local _current_process_pk_holders = setmetatable({}, {__mode = 'k'})

local function fresh_db()
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
Set the current process cap for `db`. The UDF reads through the
shared holder so the value swap is visible to every subsequent SQL
call without re-registering the callback.
]]
local function set_current_process(db, cap_pk)
	local holder = _current_process_pk_holders[db]
	assert(holder, 'set_current_process: db not from fresh_db()')
	holder.pk = cap_pk
end

local function first(db, sql)
	for row in db:nrows(sql) do
		return row
	end
	return nil
end

local function seed_user(db)
	for row in db:nrows("select object_pk from objects where role_core = 'u'") do
		return row.object_pk
	end
	error('user seed not present in schema')
end

--[[
Insert a fresh frame_process_cap cap — a `control='f'` frame with `frame_process_cap=1`,
`frame_ast='[]'`, `frame_stmt_idx=0`, no parent. This IS the frame_process_cap (its
`object_pk` is the frame_process_cap identity). Frame 0 gets seeded under it as
a nested frame.
]]
local function insert_process(db, user_pk)
	local pk
	local sql = "insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', 1, '[null]', 0, '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do
		pk = row.object_pk
	end
	return pk
end

--[[
Insert frame 0 under the cap. Frame 0 is a nested frame (frame_parent
= cap_pk, frame_process_cap = null). Returns frame 0's `object_pk`.
]]
local function insert_frame_0(db, cap_pk, user_pk)
	local pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do
		pk = row.object_pk
	end
	return pk
end

--[[
Signal that `parent_pk` is mid-dispatch. Under the current frame_gc-cycle
design, that signal is `frame_gc = 1` on the frame itself — no marker
child needed. The old name is kept so existing tests that call
push_marker(...) get the equivalent state without rewrites.
]]
local function push_marker(db, parent_pk, _user_pk)
	local sql = "update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "';"
	assert(db:exec(sql) == sqlite.OK, 'push marker (set frame_gc=1) failed: ' .. tostring(db:errmsg()))
end

--[[
Walker's canonical advance. Under the current cycle it's two SQL
statements: SET frame_gc = 1 (the handler's mid-dispatch signal) then
bare SET frame_stmt_idx = ? (the walker's advance). The BEFORE trigger
`frames_advance_requires_gc` and the AFTER trigger
`frames_advance_sets_gc_null` handle the rest.

Wrapped so tests read at the intent level and don't have to know
the two-statement shape.
]]
local function walker_advance(db, parent_pk, new_stmt_idx)
	local sql = "update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "';"
		.. "update objects set frame_stmt_idx = " .. new_stmt_idx
		.. " where object_pk = '" .. parent_pk .. "'"
	return db:exec(sql)
end


-- ------------------------------------------------------------
-- test runner — delegates to the shipping test-runner helpers so
-- results roll up into the aggregated per-file totals.
-- ------------------------------------------------------------

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


-- ============================================================
-- Column presence and defaults
-- ============================================================

test('frame_gc column exists on objects', function()
	local db = fresh_db()
	local found = false
	for row in db:nrows("pragma table_info(objects)") do
		if row.name == 'frame_gc' then found = true; break end
	end
	assert(found, 'objects should have a frame_gc column')
	db:close()
end)

test('dcok column does NOT exist (removed in frame_gc-cycle design)', function()
	local db = fresh_db()
	for row in db:nrows("pragma table_info(objects)") do
		assert(row.name ~= 'dcok', 'dcok should no longer exist')
	end
	db:close()
end)

test('frame_gc defaults to null on a fresh frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)
	local row = first(db, "select frame_gc from objects where object_pk = '" .. frame_pk .. "'")
	assert(row.frame_gc == nil, 'frame_gc should default to null; got ' .. tostring(row.frame_gc))
	db:close()
end)


-- ============================================================
-- frame_gc column shape
-- ============================================================

test('frame_gc = 0 is rejected (only 1 or null)', function()
	-- Two things reject frame_gc = 0 on an inserted frame: (a) the CHECK
	-- constraint `check (frame_gc = 1)` on the column, and (b) the trigger
	-- `frames_gc_starts_null` which requires frames to be born with
	-- frame_gc = null. The BEFORE trigger fires first — either rejection
	-- is correct for this test's intent.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local sql = "insert into objects (base, control, frame_gc, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', 0, '[]', 0, '" .. cap_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'frames_gc_starts_null',
		'frame_gc = 0 should be rejected')
	db:close()
end)

test('frame_gc = 1 on a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, frame_gc, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'frame_gc = 1 on a hash is rejected')
	db:close()
end)


-- ============================================================
-- Frame anchor rules — XOR and uniqueness
-- ============================================================

test('frame with BOTH frame_parent and frame_process_cap=1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, frame_process_cap, owner_role) values ('o', 'f', '[]', 0, '" .. parent_pk .. "', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'both anchors rejected')
	db:close()
end)

test('frame with NEITHER frame_parent nor frame_process_cap=1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', '[]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'anchorless frame rejected')
	db:close()
end)

test('a parent frame can only have one child at a time', function()
	-- Insert a first nested frame under frame_0 (with a non-empty frame_ast so
	-- it doesn't self-delete via frames_auto_delete_at_terminal_on_insert),
	-- then try to insert a second. The `objects_one_child_per_frame`
	-- unique index on frame_parent rejects the second.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	local first_child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(first_child_sql), db, 'first child insert')

	local second_child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"y\",{\"v\":2}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(second_child_sql), db, 'UNIQUE',
		'second child rejected')
	db:close()
end)


-- ============================================================
-- Cap-specific constraints
-- ============================================================

test('cap with non-empty frame_ast is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', 1, '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'non-empty frame_ast on cap rejected')
	db:close()
end)

test('frame_process_cap = 1 on a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, frame_process_cap, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'frame_process_cap=1 on hash rejected')
	db:close()
end)

test('frame_process_cap = 0 is rejected (only 1 or null)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', 0, '[]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'frame_process_cap=0 rejected')
	db:close()
end)


-- ============================================================
-- Self-parent rejection
-- ============================================================

test('a frame cannot be its own parent', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Try to insert a frame whose frame_parent equals its own object_pk.
	-- Need to supply the pk explicitly so we know the target value.
	-- Two triggers apply: frames_parent_frame_not_self and
	-- objects_parent_frame_must_be_frame (the target row doesn't exist
	-- yet, so `select primitive from objects where object_pk = <self>`
	-- returns null, and `null is not 'f'` fires the must-be-frame guard).
	-- Either rejection is correct — both mean the insert is invalid.
	local self_pk = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
	local sql = string.format(
		"insert into objects (object_pk, base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('%s', 'o', 'f', '[]', 0, '%s', '%s')",
		self_pk, self_pk, user_pk)
	local rc = db:exec(sql)
	assert(rc ~= sqlite.OK, 'self-parenting frame should have been rejected')
	local msg = db:errmsg()
	assert(msg:find('frames_parent_frame_not_self', 1, true)
			or msg:find('parent_frame_must_be_frame', 1, true),
		'expected frames_parent_frame_not_self or parent_frame_must_be_frame; got: ' .. tostring(msg))
	db:close()
end)


-- ============================================================
-- Immutability
-- ============================================================

test('frame_parent is immutable', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_a = insert_process(db, user_pk)
	local cap_b = insert_process(db, user_pk)
	local frame_a = insert_frame_0(db, cap_a, user_pk)
	local frame_b = insert_frame_0(db, cap_b, user_pk)

	-- Push a nested frame under a. Non-empty frame_ast so it survives past
	-- INSERT (an empty frame_ast would trip the born-terminal auto-delete
	-- and there'd be nothing to reparent).
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. frame_a .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested insert')
	local nested_pk = first(db, "select object_pk from objects where frame_parent = '" .. frame_a .. "'").object_pk

	assert_fails_with(
		db:exec("update objects set frame_parent = '" .. frame_b .. "' where object_pk = '" .. nested_pk .. "';"),
		db, 'objects_parent_frame_immutable',
		'reparenting rejected')
	db:close()
end)

test('frame_process_cap is immutable', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	-- try to un-cap the cap by clearing its frame_process_cap flag
	assert_fails_with(
		db:exec("update objects set frame_process_cap = null where object_pk = '" .. cap_pk .. "';"),
		db, 'objects_process_cap_immutable',
		'clearing frame_process_cap rejected')
	db:close()
end)

test('frame_gc is NOT immutable (bidirectional under the new cycle)', function()
	-- Just a smoke test that setting frame_gc to 1 (as part of a proper
	-- advance) and back to null works. Full cycle tests below cover
	-- the semantics.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, frame_pk, user_pk)

	assert_ok(walker_advance(db, frame_pk, 1), db, 'advance succeeded')

	-- After advance and child sweep, no children — safe to reset frame_gc.
	assert_ok(db:exec("update objects set frame_gc = null where object_pk = '" .. frame_pk .. "';"),
		db, 'frame_gc reset succeeded')
	db:close()
end)


-- ============================================================
-- frame_stmt_idx transitions
-- ============================================================

test('a frame at INSERT must have frame_stmt_idx = 0', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 5, '" .. cap_pk .. "', '" .. user_pk .. "');"
	-- Two triggers apply: frames_stmt_idx_must_start_at_zero and
	-- frames_stmt_idx_within_ast_bounds (5 > max(json_array_length('[]'),
	-- 1) = 1). Either rejection is correct.
	local rc = db:exec(sql)
	assert(rc ~= sqlite.OK, 'frame_stmt_idx = 5 at insert should have been rejected')
	local msg = db:errmsg()
	assert(msg:find('frames_stmt_idx_must_start_at_zero', 1, true)
			or msg:find('frames_stmt_idx_out_of_bounds', 1, true),
		'expected frames_stmt_idx_must_start_at_zero or frames_stmt_idx_out_of_bounds; got: ' .. tostring(msg))
	db:close()
end)

test('frame_stmt_idx skip (0 → 5) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		walker_advance(db, parent_pk, 5),
		db, 'frames_stmt_idx_',
		'skip rejected')
	db:close()
end)

test('frame_stmt_idx rewind is rejected', function()
	-- Use a length-3 frame_ast so the frame survives two advances without
	-- hitting terminal (and its auto-delete). After advancing to 1,
	-- try to rewind to 0 → rejected by `frames_stmt_idx_advances_by_one`.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do parent_pk = row.object_pk end

	assert_ok(walker_advance(db, parent_pk, 1), db, 'first advance 0→1')

	push_marker(db, parent_pk, user_pk)
	assert_fails_with(
		db:exec("update objects set frame_stmt_idx = 0 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_stmt_idx_',
		'rewind rejected')
	db:close()
end)


-- ============================================================
-- The frame_gc cycle — current invariants
-- ============================================================
--
-- Under the current cycle:
--   * `mark_frame_gc` sets frame_gc=1 as a standalone UPDATE (rule that
--     old `frames_gc_set_requires_advance` enforced against is gone).
--   * The walker does a BARE `SET frame_stmt_idx = ?` UPDATE. The BEFORE
--     trigger `frames_advance_requires_gc` requires old.frame_gc=1; the
--     AFTER trigger `frames_advance_sets_gc_null` auto-resets frame_gc.
--   * Mentioning frame_gc in the advance UPDATE with any non-null value
--     is rejected by `frames_advance_rejects_non_null_gc`.
--   * Setting frame_gc=1 while the frame has a child is rejected by
--     `frames_gc_change_requires_no_child` (bidirectional).
--   * Child-delete cascades set parent.frame_gc=1 via
--     `frames_child_delete_sets_parent_gc` (cap-exempt).
-- ============================================================

test('advance without frame_gc=1 is rejected', function()
	-- Bare `SET frame_stmt_idx = ?` on a frame whose frame_gc is still null
	-- (never marked mid-dispatch) is rejected by
	-- `frames_advance_requires_gc`. Fresh frame, no push_marker.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set frame_stmt_idx = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_requires_gc',
		'advance without frame_gc=1 rejected')
	db:close()
end)

test('advance mentioning frame_gc = 1 in the SET clause is rejected', function()
	-- The advance UPDATE must be bare — `SET frame_stmt_idx = ?` only.
	-- Any mention of `frame_gc = 1` (or any non-null frame_gc) in the same
	-- UPDATE is rejected by `frames_advance_rejects_non_null_gc`,
	-- because the AFTER auto-set would silently overwrite it with
	-- null anyway. Loud rejection surfaces the engine bug.
	--
	-- Uses a length-3 frame_ast so the advance target (frame_stmt_idx=1) is not
	-- terminal — otherwise `frames_gc_set_rejects_at_terminal`
	-- would fire first for a different reason.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do parent_pk = row.object_pk end

	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set frame_stmt_idx = 1, frame_gc = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_rejects_non_null_gc',
		'advance mentioning frame_gc=1 rejected')
	db:close()
end)

test('setting frame_gc=1 while the frame has a child is rejected', function()
	-- `frames_gc_change_requires_no_child` — bidirectional. Parent
	-- has a live nested child; try to set frame_gc=1 → rejected.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Insert a live (non-empty frame_ast) child so it doesn't auto-delete.
	local child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(child_sql), db, 'child insert')

	assert_fails_with(
		db:exec("update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_gc_change_requires_no_child',
		'frame_gc=1 with child rejected')
	db:close()
end)

test('resetting frame_gc to null while a child still exists is rejected', function()
	-- The same bidirectional trigger: frame_gc cannot change while a child
	-- exists — including the 1 → null direction. Parent must be at
	-- frame_gc=1 first (to have something to reset from); we mark it before
	-- adding the child so both preconditions are met.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	assert_ok(db:exec("update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'mark frame_gc=1 before adding child')

	-- Add a live child (with non-empty frame_ast so it doesn't auto-delete).
	local child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(child_sql), db, 'child insert')

	assert_fails_with(
		db:exec("update objects set frame_gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'frames_gc_change_requires_no_child',
		'frame_gc reset with a child rejected')
	db:close()
end)

test('deleting a child frame cascade-sets parent.frame_gc = 1 (non-cap parent)', function()
	-- `frames_child_delete_sets_parent_gc` — direct delete of a child
	-- frame triggers the parent's frame_gc → 1 (unless the parent is a cap,
	-- which is exempt). Verifies the mechanism that ends every
	-- non-cap frame's lifecycle. Under the current design terminal is
	-- an at-rest state — auto-delete is gone — so this test explicitly
	-- deletes the child rather than relying on advance-triggers-delete.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	local child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(child_sql), db, 'child insert')
	local child_pk = first(db, "select object_pk from objects where frame_parent = '" .. parent_pk .. "'").object_pk

	-- Explicit delete of the child — simulates the engine's reap step
	-- at the end of run_frame. The cascade flips parent.frame_gc to 1.
	assert_ok(db:exec("delete from objects where object_pk = '" .. child_pk .. "'"),
		db, 'child delete')

	local parent_row = first(db, "select frame_gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(parent_row.frame_gc) == 1,
		'parent frame_gc should be 1 after child delete cascade; got: ' .. tostring(parent_row.frame_gc))
	db:close()
end)

test('resetting frame_gc to null with no children is allowed', function()
	-- Mark frame_gc=1, then reset. No children involved. The bidirectional
	-- frame_gc-change trigger's WHEN clause has an existence check for
	-- children; with none, frame_gc = 1 → null succeeds.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	assert_ok(db:exec("update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'mark frame_gc=1')
	assert_ok(db:exec("update objects set frame_gc = null where object_pk = '" .. parent_pk .. "'"),
		db, 'frame_gc reset succeeded')
	db:close()
end)


-- ============================================================
-- Full cycle
-- ============================================================

test('two full advance cycles in sequence', function()
	-- Use a length-3 frame_ast so cycle 2 doesn't hit terminal (which
	-- would auto-delete the frame). Each cycle: mark frame_gc=1, bare
	-- advance, verify frame_gc auto-nulled.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	local parent_pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do parent_pk = row.object_pk end

	-- Cycle 1: 0 → 1.
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db, 'cycle 1 advance')

	-- Cycle 2: 1 → 2.
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 2), db, 'cycle 2 advance')

	local row = first(db, "select frame_stmt_idx, frame_gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(row.frame_stmt_idx) == 2, 'frame_stmt_idx should be 2 after two cycles')
	assert(row.frame_gc == nil, 'frame_gc should be null after both cycles (auto-reset by frames_advance_sets_gc_null)')

	local n = first(db, "select count(*) as n from objects where frame_parent = '" .. parent_pk .. "'")
	assert(tonumber(n.n) == 0, 'no children remain')
	db:close()
end)


-- ============================================================
-- refs — hash keys accept any non-null string
--
-- The schema places no grammar rule on hash-key content — any
-- non-null string works. `refs_hash_key_required` still enforces
-- the hash-vs-array distinction (hash entries carry a key; array
-- entries leave it null). Identifier-shape rules for particular
-- uses of hashes (variable names, method dispatch) live in the
-- language layer, not the schema.
-- ============================================================

--[[
Insert a bare hash owned by the user seed. Returns its pk.
]]
local function insert_hash(db, user_pk)
	local sql = "insert into objects (base, owner_role) values ('h', '"
		.. user_pk .. "') returning object_pk"
	local pk
	for row in db:nrows(sql) do pk = row.object_pk end
	return pk
end

test('hash key: plain lowercase identifier is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"),
		db, 'plain identifier accepted')
	db:close()
end)

test('hash key: leading underscore is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', '_start', 0)"),
		db, 'leading underscore accepted')
	db:close()
end)

test('hash key: alphanumerics after first char accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'my_var_123', 0)"),
		db, 'letters + digits + underscores accepted')
	db:close()
end)

test('hash key: leading digit is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', '1x', 0)"),
		db, 'leading digit accepted')
	db:close()
end)

test('hash key: dash character is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'my-var', 0)"),
		db, 'dash accepted')
	db:close()
end)

test('hash key: space is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'foo bar', 0)"),
		db, 'space accepted')
	db:close()
end)

test('hash key: empty string is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', '', 0)"),
		db, 'empty string accepted (any non-null string is a valid key)')
	db:close()
end)

test('hash key: unicode content is accepted', function()
	-- The dropped grammar rule was ASCII-only. Confirm unicode works.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'πρι', 0)"),
		db, 'unicode accepted')
	db:close()
end)

test('array entry with null key is not affected by the identifier rule', function()
	-- Sanity: the rule only fires on hash keys (key not null with hash parent).
	-- Array entries have key=null and should be unaffected.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, owner_role) values ('a', '"
		.. user_pk .. "') returning object_pk"
	local array_pk
	for row in db:nrows(sql) do array_pk = row.object_pk end
	local child_pk = insert_hash(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. array_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'null-key array entry unaffected')
	db:close()
end)


-- ============================================================
-- refs — self-reference allowed
-- ============================================================

test('a container object can hold a ref pointing at itself', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (base, owner_role) values ('h', '"
		.. user_pk .. "') returning object_pk"
	local hash_pk
	for row in db:nrows(sql) do hash_pk = row.object_pk end

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. hash_pk .. "', 'self', 0)"),
		db, 'self-reference should be accepted')
	db:close()
end)


-- ============================================================
-- Scopes convention (schema-enforced)
-- ============================================================

--[[
Small helpers for these tests — insert a bare object of a given
primitive, owned by the user seed, and return its pk.
]]
local function insert_object(db, user_pk, primitive)
	local sql = "insert into objects (base, owner_role) values ('"
		.. primitive .. "', '" .. user_pk .. "') returning object_pk"
	local pk
	for row in db:nrows(sql) do pk = row.object_pk end
	return pk
end

test('scopes-keyed ref pointing at an ArrayPrimitive is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	local array_pk = insert_object(db, user_pk, 'a')

	local sql = "insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. array_pk .. "', 'scopes', 0)"
	assert_ok(db:exec(sql), db, 'scopes ref to array should be accepted')
	db:close()
end)

test('scopes-keyed ref pointing at a hash is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	local target_pk = insert_object(db, user_pk, 'h')  -- hash, not array

	local sql = "insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. target_pk .. "', 'scopes', 0)"
	assert_fails_with(db:exec(sql), db, 'refs_scopes_key_requires_array',
		'scopes ref to hash should be rejected')
	db:close()
end)

test('scopes-keyed ref pointing at a scalar object is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	-- Scalar object
	local sql = "insert into objects (base, scalar_number, owner_role) values ('o', 1, '" .. user_pk .. "') returning object_pk"
	local scalar_pk
	for row in db:nrows(sql) do scalar_pk = row.object_pk end

	sql = "insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. scalar_pk .. "', 'scopes', 0)"
	assert_fails_with(db:exec(sql), db, 'refs_scopes_key_requires_array',
		'scopes ref to scalar should be rejected')
	db:close()
end)

test('inserting a hash into an established scopes array is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	local array_pk = insert_object(db, user_pk, 'a')

	-- Establish as a scopes array
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. array_pk .. "', 'scopes', 0)"), db)

	-- Insert a hash entry into the scopes array
	local hash_pk = insert_object(db, user_pk, 'h')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. array_pk .. "', '" .. hash_pk .. "', null, 0)"), db, 'hash entry accepted')
	db:close()
end)

test('inserting a non-hash into an established scopes array is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	local array_pk = insert_object(db, user_pk, 'a')

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. array_pk .. "', 'scopes', 0)"), db)

	-- Try inserting an ArrayPrimitive into the scopes array
	local inner_array = insert_object(db, user_pk, 'a')
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. array_pk .. "', '" .. inner_array .. "', null, 0)"),
		db, 'refs_scopes_array_entries_must_be_hashes',
		'non-hash entry rejected')
	db:close()
end)

test('scopes ref rejected if target array already has non-hash entries', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local bucket_pk = insert_object(db, user_pk, 'h')
	local array_pk = insert_object(db, user_pk, 'a')

	-- Populate array first with a non-hash entry (no scopes ref yet, so
	-- refs_scopes_array_entries_must_be_hashes doesn't fire).
	local inner_array = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. array_pk .. "', '" .. inner_array .. "', null, 0)"), db)

	-- Now try to attach it as a scopes array. Should reject due to
	-- existing non-hash contents.
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. bucket_pk .. "', '" .. array_pk .. "', 'scopes', 0)"),
		db, 'refs_scopes_key_existing_entries_must_be_hashes',
		'array with non-hash entries can\'t be attached as scopes')
	db:close()
end)


-- ============================================================
-- frame_scoped_vars view
-- ============================================================

--[[
Build a frame with a scope chain: frame's bucket → scopes array →
two hashes. scope[0] (own) holds x=1; scope[1] (captured) holds
x=99 and y=2. Then query the view.
]]
test('frame_scoped_vars: dumps all visible variables with scope depth', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Frame's bucket. Under the sprint design, ownership is a refs row
	-- from the owner to the collection (no dedicated column).
	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	-- Scopes array under the bucket.
	local scopes_pk = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. scopes_pk .. "', 'scopes', 0)"), db)

	-- Two scope hashes at scopes[0] and scopes[1].
	local scope0 = insert_hash(db, user_pk)
	local scope1 = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scopes_pk .. "', '" .. scope0 .. "', null, 0)"), db)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scopes_pk .. "', '" .. scope1 .. "', null, 1)"), db)

	-- Values for the bindings.
	local val_1 = insert_object(db, user_pk, 'o')  -- pretend scalars for the pk
	local val_99 = insert_object(db, user_pk, 'o')
	local val_2 = insert_object(db, user_pk, 'o')

	-- scope0: x = val_1
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scope0 .. "', '" .. val_1 .. "', 'x', 0)"), db)
	-- scope1: x = val_99 (shadowed by scope0's x)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scope1 .. "', '" .. val_99 .. "', 'x', 0)"), db)
	-- scope1: y = val_2
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scope1 .. "', '" .. val_2 .. "', 'y', 1)"), db)

	-- Full dump.
	local rows = {}
	for row in db:nrows("select scope_idx, var_name, value_pk from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "' order by scope_idx, var_name") do
		table.insert(rows, {tonumber(row.scope_idx), row.var_name, row.value_pk})
	end
	assert(#rows == 3, 'expected 3 rows in the dump; got ' .. #rows)
	assert(rows[1][1] == 0 and rows[1][2] == 'x' and rows[1][3] == val_1,
		'row 1 should be scope 0, x, val_1')
	assert(rows[2][1] == 1 and rows[2][2] == 'x' and rows[2][3] == val_99,
		'row 2 should be scope 1, x, val_99')
	assert(rows[3][1] == 1 and rows[3][2] == 'y' and rows[3][3] == val_2,
		'row 3 should be scope 1, y, val_2')
	db:close()
end)

test('frame_scoped_vars: effective binding via ORDER BY scope_idx LIMIT 1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Build a bucket + scopes with x in both scopes; scope 0 shadows.
	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	local scopes_pk = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. scopes_pk .. "', 'scopes', 0)"), db)

	local scope0 = insert_hash(db, user_pk)
	local scope1 = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scopes_pk .. "', '" .. scope0 .. "', null, 0)"), db)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scopes_pk .. "', '" .. scope1 .. "', null, 1)"), db)

	local inner = insert_object(db, user_pk, 'o')
	local outer = insert_object(db, user_pk, 'o')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scope0 .. "', '" .. inner .. "', 'x', 0)"), db)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scope1 .. "', '" .. outer .. "', 'x', 0)"), db)

	local row = first(db, "select value_pk from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "' and var_name = 'x' "
		.. "order by scope_idx limit 1")
	assert(row.value_pk == inner, 'nearest-scope (inner) wins')
	db:close()
end)

test('frame_scoped_vars: empty result on a fresh frame with no scopes chain', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local row = first(db, "select scope_idx from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "'")
	assert(row == nil, 'fresh frame yields no rows')
	db:close()
end)

test('frame_scoped_vars: empty result when frame has a bucket but no scopes ref', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Attach a bucket but don't hang a scopes ref off it.
	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	local row = first(db, "select scope_idx from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "'")
	assert(row == nil, 'bucket-without-scopes yields no rows (not an error)')
	db:close()
end)

test('frame_scoped_vars: empty result when scopes array exists but has no entries', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	-- Attach an empty scopes array.
	local scopes_pk = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. scopes_pk .. "', 'scopes', 0)"), db)

	local row = first(db, "select scope_idx from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "'")
	assert(row == nil, 'empty scopes array yields no rows (not an error)')
	db:close()
end)

test('frame_scoped_vars: empty result when scope hash exists but has no bindings', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	local scopes_pk = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. bucket_pk .. "', '" .. scopes_pk .. "', 'scopes', 0)"), db)

	-- Attach an empty scope hash at scopes[0].
	local scope0 = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scopes_pk .. "', '" .. scope0 .. "', null, 0)"), db)

	local row = first(db, "select scope_idx from frame_scoped_vars "
		.. "where frame_pk = '" .. frame_pk .. "'")
	assert(row == nil, 'empty scope hash yields no rows (not an error)')
	db:close()
end)

test('frame_scoped_vars: no error when queried on a frame_pk that doesn\'t exist', function()
	local db = fresh_db()

	-- Non-existent frame_pk. Should return zero rows, not raise.
	local row = first(db, "select scope_idx from frame_scoped_vars "
		.. "where frame_pk = 'no-such-frame'")
	assert(row == nil, 'nonexistent frame yields no rows (not an error)')
	db:close()
end)


-- ============================================================
-- frame_scoped_vars view — query plan
-- ============================================================

local function plan(db, sql)
	local rows = {}
	for row in db:nrows("explain query plan " .. sql) do
		table.insert(rows, row.detail)
	end
	return table.concat(rows, "\n")
end

local function assert_plan_contains(actual, expected, note)
	if actual:find(expected, 1, true) then return end
	error(
		(note or "plan mismatch") .. "\n"
			.. "expected substring: " .. expected .. "\n"
			.. "actual plan:\n" .. actual,
		2)
end

local function assert_plan_lacks(actual, forbidden, note)
	if not actual:find(forbidden, 1, true) then return end
	error(
		(note or "plan should not contain") .. "\n"
			.. "forbidden substring: " .. forbidden .. "\n"
			.. "actual plan:\n" .. actual,
		2)
end

test('frame_scoped_vars: full-dump query is fully indexed (no scans)', function()
	local db = fresh_db()
	local p = plan(db, "select * from frame_scoped_vars where frame_pk = 'x'")

	-- PK lookup on the starting frame.
	assert_plan_contains(p, 'SEARCH f USING INDEX sqlite_autoindex_objects_1 (object_pk=?)',
		'f should use the objects PK index')
	-- bucket_ref (owner → key='b' bucket) via the refs unique(parent, key)
	-- index. Under the b/p/s shape, the bucket join is one indexed lookup
	-- rather than a base-filtered objects join.
	assert_plan_contains(p, 'SEARCH bucket_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'bucket_ref should use the refs unique(parent, key) index (key=b)')
	-- scopes ref filters by (parent, key) — the refs unique(parent, key) index.
	assert_plan_contains(p, 'scopes_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'scopes_ref should use the refs unique(parent, key) index')
	-- Scope and var iterations use refs_parent.
	assert_plan_contains(p, 'scope_ref USING INDEX refs_parent (parent=?)',
		'scope_ref should use the refs_parent index')
	assert_plan_contains(p, 'var_ref USING INDEX refs_parent (parent=?)',
		'var_ref should use the refs_parent index')
	-- Nothing scans.
	assert_plan_lacks(p, 'SCAN', 'full-dump plan should have no full scans')
	db:close()
end)

test('frame_scoped_vars: effective-binding query is fully indexed (no scans)', function()
	local db = fresh_db()
	local p = plan(db,
		"select value_pk from frame_scoped_vars "
		.. "where frame_pk = 'x' and var_name = 'y' order by scope_idx limit 1")

	-- All joins hit indexes; the extra `var_name = ?` predicate lets
	-- var_ref use the (parent, key) unique index for a direct hit.
	assert_plan_contains(p, 'SEARCH f USING INDEX sqlite_autoindex_objects_1 (object_pk=?)',
		'f should use the PK index')
	assert_plan_contains(p, 'SEARCH bucket_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'bucket_ref uses (parent, key) unique index (key=b)')
	assert_plan_contains(p, 'scopes_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'scopes_ref uses (parent, key) unique index')
	assert_plan_contains(p, 'var_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'var_ref uses (parent, key) unique index for direct var lookup')
	assert_plan_lacks(p, 'SCAN', 'effective-binding plan should have no full scans')
	db:close()
end)


-- ============================================================
-- object_bucket / object_platters / object_shadow views
-- ============================================================

test('object_bucket: returns null for an object with no bucket', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')

	local row = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. obj .. "'")
	assert(row ~= nil, 'object should appear in the view')
	assert(row.bucket_pk == nil, 'bucket_pk should be null (no bucket)')
	db:close()
end)

test('object_bucket: returns the bucket_pk when the object has a hash-child', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')
	local bucket = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. bucket .. "', 'b', 0)"), db)

	local row = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.bucket_pk == bucket, 'bucket_pk should match the linked hash')
	db:close()
end)

test('object_bucket: array-child does not count as bucket', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')
	local stack = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. stack .. "', 'p', 0)"), db)

	local row = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.bucket_pk == nil, 'bucket_pk should be null when only an array-child exists')
	db:close()
end)

test('object_platters: returns null for an object with no stack', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')

	local row = first(db, "select platters_pk from object_platters "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.platters_pk == nil, 'platters_pk should be null (no stack)')
	db:close()
end)

test('object_platters: returns the platters_pk when the object has an array-child', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')
	local stack = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. stack .. "', 'p', 0)"), db)

	local row = first(db, "select platters_pk from object_platters "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.platters_pk == stack, 'platters_pk should match the linked array')
	db:close()
end)

test('object_bucket / object_platters: frames are included (non-container)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket = insert_hash(db, user_pk)
	local stack  = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket .. "', 'b', 0)"), db)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. stack .. "', 'p', 1)"), db)

	local b = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. frame_pk .. "'")
	assert(b.bucket_pk == bucket, 'frame bucket found')

	local s = first(db, "select platters_pk from object_platters "
		.. "where object_pk = '" .. frame_pk .. "'")
	assert(s.platters_pk == stack, 'frame platters found')
	db:close()
end)

test('object_bucket / object_platters: containers do not appear (out of scope)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash = insert_hash(db, user_pk)

	local row = first(db, "select object_pk from object_bucket "
		.. "where object_pk = '" .. hash .. "'")
	assert(row == nil, 'hash should not appear in object_bucket')

	row = first(db, "select object_pk from object_platters "
		.. "where object_pk = '" .. hash .. "'")
	assert(row == nil, 'hash should not appear in object_platters')
	db:close()
end)


-- ============================================================
-- Process completion
-- ============================================================

test('cap reaches its at-rest state (frame_stmt_idx=1, frame_gc=null, no children) after frame 0 completes and cap advances', function()
	-- Under the current design, caps participate in the frame_gc cycle
	-- like any other frame. Frame 0 reaps → cap.gc=1 (via
	-- `frames_child_delete_sets_parent_gc`, no cap-exempt); cap's own
	-- walker step advances stmt_idx 0→1 and the advance auto-nulls gc.
	-- Cap ends at terminal (stmt_idx=1, gc=null) as the process anchor.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Frame 0 (length-1 frame_ast): mark frame_gc=1, bare advance to 1 (terminal).
	-- Auto-nulls frame_gc via frames_advance_sets_gc_null. Frame stays alive
	-- at terminal until we reap it.
	assert_ok(walker_advance(db, frame_pk, 1), db, 'frame 0 advance to terminal')

	-- Simulate the engine's reap step.
	assert_ok(db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"),
		db, 'frame 0 reap')

	-- Cap.gc = 1 now (sets_parent_gc fired).
	local mid = first(db, "select frame_stmt_idx, frame_gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(tonumber(mid.frame_stmt_idx) == 0, 'cap frame_stmt_idx still 0 (advance not run yet)')
	assert(tonumber(mid.frame_gc) == 1, 'cap frame_gc = 1 (set by frames_child_delete_sets_parent_gc)')

	-- Cap's own advance (what Engine.run does after run_frame returns):
	-- advance stmt_idx 0 → 1, auto-nulls gc.
	assert_ok(walker_advance(db, cap_pk, 1), db, 'cap advance to terminal')

	local cap_row = first(db, "select frame_stmt_idx, frame_gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(tonumber(cap_row.frame_stmt_idx) == 1, 'cap frame_stmt_idx = 1 (advanced through its cycle)')
	assert(cap_row.frame_gc == nil, 'cap frame_gc = null (auto-nulled by advance)')

	-- Frame 0 is gone; cap has no children.
	local children = first(db, "select count(*) as n from objects where frame_parent = '" .. cap_pk .. "'")
	assert(tonumber(children.n) == 0, 'cap should have no children (frame 0 reaped)')
	db:close()
end)

test('deleting a frame with frame_gc=null is accepted regardless of frame_stmt_idx', function()
	-- The delete rule permits deletion at any frame_stmt_idx as long as frame_gc
	-- is null. Uses a cap (no parent, so no cascade check) with no
	-- children (no FK to satisfy) to exercise the rule directly.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	-- Cap: frame_stmt_idx=0, frame_gc=null, no children, no parent.
	assert_ok(db:exec("delete from objects where object_pk = '" .. cap_pk .. "';"),
		db, 'delete at frame_gc=null succeeded')
	db:close()
end)

test('a frame with a child cannot be deleted', function()
	-- The current schema replaces the old `frames_delete_requires_gc_null`
	-- with `frames_delete_requires_no_child` — the invariant is
	-- "no live child" rather than "frame_gc is null." Reaches for the same
	-- protection: you can't destroy a parent while a child is
	-- executing under it.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local child_sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. frame_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(child_sql), db, 'child insert')

	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"),
		db, 'frames_delete_requires_no_child',
		'parent-with-child delete rejected')
	db:close()
end)

test('frame delete cascades its refs and marks each child needs_trace=1', function()
	-- Frame 0 exhausts its frame_ast, reaps explicitly (simulating the
	-- engine's reap step). Its outgoing refs cascade via
	-- `refs.parent ON DELETE CASCADE`; each ref-delete fires
	-- `refs_mark_needs_trace_after_delete` on the child, which
	-- inserts the child into the needs_trace table (scoped to the
	-- current process via the DEFAULT-driven upsert).
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	set_current_process(db, cap_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', 'b', 0)"), db)

	assert_ok(walker_advance(db, frame_pk, 1), db, 'frame 0 advance to terminal')
	assert_ok(db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"),
		db, 'frame 0 reap')

	local bucket = first(db, "select object_pk from objects where object_pk = '" .. bucket_pk .. "'")
	assert(bucket ~= nil, 'bucket should survive frame delete')
	local mark = first(db, "select object_pk from needs_trace where object_pk = '" .. bucket_pk .. "'")
	assert(mark ~= nil, 'bucket should be in the needs_trace table')
	db:close()
end)

test('swapping the owner→bucket ref for a different target marks the old target', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	set_current_process(db, cap_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Attach bucket A to frame 0.
	local bucket_a = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_a .. "', 'b', 0)"), db)

	-- Swap for bucket B: delete the old ref, insert a new one.
	assert_ok(db:exec("delete from refs where parent = '" .. frame_pk
		.. "' and child = '" .. bucket_a .. "'"), db, 'drop old ref')

	local bucket_b = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_b .. "', 'b', 0)"), db, 'add new ref')

	-- Old bucket (A) landed in needs_trace via the ref-delete; new (B) didn't.
	local a = first(db, "select object_pk from needs_trace where object_pk = '" .. bucket_a .. "'")
	assert(a ~= nil, 'old bucket should be in needs_trace')

	local b = first(db, "select object_pk from needs_trace where object_pk = '" .. bucket_b .. "'")
	assert(b == nil, 'new bucket should NOT be in needs_trace')
	db:close()
end)

test('role_parent pointing at a non-role row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local engine_pk = first(db, "select object_pk from objects where role_core = 'e'").object_pk
	local hash_pk = first(db, "insert into objects (base, owner_role) values ('h', '"
		.. user_pk .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("insert into objects (base, control, role_parent, owner_role) values ('o', 'r', '" .. hash_pk .. "', '" .. engine_pk .. "')"),
		db, 'parent_role_must_be_role',
		'role_parent → non-role hash rejected')
	db:close()
end)

test('only the engine role can be a role-tree root (role_parent = null)', function()
	local db = fresh_db()
	local engine_pk = first(db, "select object_pk from objects where role_core = 'e'").object_pk

	assert_fails_with(
		db:exec("insert into objects (base, control, owner_role) values ('o', 'r', '" .. engine_pk .. "')"),
		db, 'objects_only_engine_can_be_role_root',
		'root-shaped runtime role rejected')
	db:close()
end)

test('roles view returns exactly the primitive = r rows', function()
	local db = fresh_db()
	local view_count = first(db, "select count(*) as n from roles").n
	local r_count = first(db, "select count(*) as n from objects where control = 'r'").n
	assert(tonumber(view_count) == tonumber(r_count),
		'roles view count (' .. tostring(view_count) .. ') should equal count of primitive=r rows ('
		.. tostring(r_count) .. ')')
	assert(tonumber(view_count) == 3, 'roles view should have 3 rows at init; got: ' .. tostring(view_count))
	db:close()
end)

test('deleting a role with descendants is rejected (role_parent FK RESTRICT)', function()
	local db = fresh_db()
	local engine_pk = first(db, "select object_pk from objects where role_core = 'e'").object_pk

	-- Create a runtime role under engine, then a grandchild under it.
	local parent_pk = first(db, "insert into objects (base, control, role_parent, owner_role) values ('o', 'r', '" .. engine_pk .. "', '" .. engine_pk .. "') returning object_pk").object_pk
	assert_ok(db:exec("insert into objects (base, control, role_parent, owner_role) values ('o', 'r', '" .. parent_pk .. "', '" .. engine_pk .. "')"),
		db, 'grandchild role insert')

	-- Deleting the intermediate role should hit FK RESTRICT because
	-- the grandchild still references it via role_parent.
	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. parent_pk .. "'"),
		db, 'FOREIGN KEY constraint',
		'delete of role with descendants rejected')
	db:close()
end)

test('deleting a childless runtime role is accepted', function()
	local db = fresh_db()
	local engine_pk = first(db, "select object_pk from objects where role_core = 'e'").object_pk

	local role_pk = first(db, "insert into objects (base, control, role_parent, owner_role) values ('o', 'r', '" .. engine_pk .. "', '" .. engine_pk .. "') returning object_pk").object_pk

	assert_ok(db:exec("delete from objects where object_pk = '" .. role_pk .. "'"),
		db, 'leaf role deletable')
	db:close()
end)

test('seeded engine/cache/user rows all have persistent = 1 (mandatory for core roles)', function()
	local db = fresh_db()
	for _, code in ipairs({'e', 'c', 'u'}) do
		local row = first(db, "select persistent from objects where role_core = '" .. code .. "'")
		assert(tonumber(row.persistent) == 1,
			"role_core='" .. code .. "' should have persistent=1; got: " .. tostring(row.persistent))
	end
	db:close()
end)

test('inserting a core role without persistent is rejected (cross-column CHECK)', function()
	-- Uses a scratch schema with seed inserts commented out so the
	-- role_core unique index doesn't intercept before the CHECK fires.
	local schema = slurp(SCHEMA_PATH):gsub("insert into objects", "-- insert into objects")

	local db = sqlite.open_memory()
	db:exec('pragma foreign_keys = on;')
	local rc = db:exec(schema)
	assert(rc == sqlite.OK, 'schema-def apply failed: ' .. tostring(db:errmsg()))

	assert_fails_with(
		db:exec("insert into objects (base, control, role_core) values ('o', 'r', 'e')"),
		db, 'CHECK constraint',
		'core role with implicit-null persistent rejected')
	assert_fails_with(
		db:exec("insert into objects (base, control, role_core, persistent) values ('o', 'r', 'e', null)"),
		db, 'CHECK constraint',
		'core role with explicit-null persistent rejected')
	assert_ok(
		db:exec("insert into objects (base, control, role_core, persistent) values ('o', 'r', 'e', 1)"),
		db, 'core role with persistent=1 accepted')
	db:close()
end)

test('a non-core row inserted without persistent gets null (default = unpinned)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local row = first(db, "insert into objects (base, owner_role) values ('h', '"
		.. user_pk .. "') returning object_pk, persistent")
	assert(row.persistent == nil,
		'non-core hash without persistent should be null; got: ' .. tostring(row.persistent))
	db:close()
end)

test('a non-core row can opt into pinning by setting persistent = 1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (base, owner_role, persistent) values ('h', '"
			.. user_pk .. "', 1)"),
		db, 'non-core row with persistent=1 accepted')
	db:close()
end)

test('persistent = 0 is rejected (only 1 or null allowed)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, owner_role, persistent) values ('h', '"
			.. user_pk .. "', 0)"),
		db, 'CHECK constraint',
		'persistent=0 rejected by the persistent CHECK')
	db:close()
end)


-- ============================================================
-- Object pk shape and DEFAULT
-- `object_pk` is a lowercase-hex UUID (8-4-4-4-12). The DEFAULT
-- generates a proper v4 UUID (version bit at position 15, variant
-- bit at position 20). The CHECK is looser about version/variant
-- (accepts v1/v3/v7/etc.) but strict about case (lowercase only)
-- so the same conceptual UUID can't sit under two distinct PKs.
-- ============================================================

test('seeded core-role rows have compliant object_pks', function()
	local db = fresh_db()

	for _, code in ipairs({'e', 'c', 'u'}) do
		local row = first(db, "select object_pk from objects where role_core = '" .. code .. "'")
		local pk = row.object_pk

		-- length 36
		assert(#pk == 36, "role_core='" .. code .. "' object_pk should be length 36; got: " .. #pk .. " (" .. pk .. ")")
		-- hyphens at 9, 14, 19, 24 (1-indexed)
		assert(pk:sub(9, 9) == '-', "hyphen expected at position 9 in " .. pk)
		assert(pk:sub(14, 14) == '-', "hyphen expected at position 14 in " .. pk)
		assert(pk:sub(19, 19) == '-', "hyphen expected at position 19 in " .. pk)
		assert(pk:sub(24, 24) == '-', "hyphen expected at position 24 in " .. pk)
		-- v4: position 15 (start of third block) must be '4'
		assert(pk:sub(15, 15) == '4', "position 15 should be '4' (v4 version bit) in " .. pk)
		-- variant: position 20 (start of fourth block) must be 8/9/a/b
		local v = pk:sub(20, 20)
		assert(v == '8' or v == '9' or v == 'a' or v == 'b',
			"position 20 should be one of 8/9/a/b (variant bit) in " .. pk .. " (got '" .. v .. "')")
	end
	db:close()
end)

test('DEFAULT generates v4-shaped pks across 100 inserts', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	for i = 1, 100 do
		local sql = "insert into objects (base, owner_role) values ('h', '"
			.. user_pk .. "') returning object_pk"
		local row = first(db, sql)
		local pk = row.object_pk

		assert(#pk == 36, "iteration " .. i .. ": pk length should be 36; got: " .. #pk .. " (" .. pk .. ")")
		assert(pk:sub(15, 15) == '4', "iteration " .. i .. ": position 15 should be '4'; got: " .. pk)

		local v = pk:sub(20, 20)
		assert(v == '8' or v == '9' or v == 'a' or v == 'b',
			"iteration " .. i .. ": position 20 should be 8/9/a/b; got: '" .. v .. "' in " .. pk)
	end
	db:close()
end)

test('CHECK accepts a caller-supplied lowercase v4 UUID', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdef01-2345-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'compliant lowercase v4 UUID accepted')
	db:close()
end)

test('CHECK rejects a caller-supplied uppercase UUID (lowercase enforced)', function()
	-- Same conceptual UUID as the lowercase-accept test above but in
	-- uppercase. Rejected because SQLite's default TEXT collation is
	-- binary — accepting both cases would let the same UUID sit under
	-- two distinct PKs.
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('ABCDEF01-2345-4678-9ABC-DEF012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'uppercase UUID rejected')
	db:close()
end)

test('CHECK rejects a caller-supplied mixed-case UUID (lowercase enforced)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('AbCdEf01-2345-4678-9aBc-dEf012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'mixed-case UUID rejected')
	db:close()
end)

test('CHECK accepts a non-v4 UUID (loose shape — no version-bit check)', function()
	-- Version-3 (position 15 = '3') and non-v4 variants should pass —
	-- the CHECK only enforces the general 8-4-4-4-12 hex shape.
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdef01-2345-3678-c000-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'v3-shaped UUID accepted (no version-bit check)')
	db:close()
end)

test("CHECK rejects 'banana' (not UUID-shaped at all)", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('banana', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'banana rejected')
	db:close()
end)

test("CHECK rejects a UUID-length-but-wrong-hyphen-position string", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Same length (36) but hyphens in wrong places.
	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdef0123-45-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'wrong hyphen positions rejected')
	db:close()
end)

test("CHECK rejects a UUID-shape with a non-hex character in place", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Same layout, but position 5 is 'g' (not hex).
	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdgf01-2345-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'non-hex character rejected')
	db:close()
end)

test("CHECK rejects the historical 'no-such-uuid-...' sentinel", function()
	-- The word 'no-such-uuid' has non-hex letters (n, o, s, u).
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('no-such-uuid-0000-0000-000000000000', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		"'no-such-uuid-...' rejected")
	db:close()
end)

test("CHECK rejects a too-short string", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdef01-2345', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'too-short string rejected')
	db:close()
end)

test("CHECK rejects a too-long string", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcdef01-2345-4678-9abc-def012345678-extra', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'too-long string rejected')
	db:close()
end)

test("CHECK rejects 36 hyphens (per-segment hex-only)", function()
	-- The earlier CHECK accepted this because LIKE's `_` matches any
	-- character and the global character class included `-`. Per-segment
	-- substr checks now require actual hex inside each segment.
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('------------------------------------', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'36 hyphens rejected')
	db:close()
end)

test("CHECK rejects a hyphen inside a hex segment", function()
	-- Length 36, hyphens at positions 9/14/19/24 (correct), but position 5
	-- is a hyphen instead of hex. Fails the per-segment hex-only check on
	-- the first segment.
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (object_pk, base, owner_role) values ('abcd-f01-2345-4678-9abc-def012345678', 'h', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		'hyphen inside a segment rejected')
	db:close()
end)


-- ============================================================
-- refs.debug is mutable
-- `debug` is an informational label with no query path reading it,
-- so freezing it at INSERT-time offers no invariant value. Carved
-- out of `refs_no_update`'s WHEN clause (matches the same carve-out
-- for objects.debug).
-- ============================================================

local function insert_scalar(db, owner_role)
	local sql = "insert into objects (base, scalar_number, owner_role) values ('o', 1, '" .. owner_role .. "') returning object_pk"
	for row in db:nrows(sql) do
		return row.object_pk
	end
end

test('setting refs.debug from null to a value is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"), db, 'insert ref')

	assert_ok(db:exec("update refs set debug = 'first label' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'set debug from null')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == 'first label',
		'debug should be "first label"; got: ' .. tostring(row.debug))
	db:close()
end)

test('changing refs.debug to a different value is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx, debug) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0, 'first')"), db, 'insert with debug')

	assert_ok(db:exec("update refs set debug = 'second' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'update debug')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == 'second',
		'debug should be "second"; got: ' .. tostring(row.debug))
	db:close()
end)

test('clearing refs.debug (back to null) is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx, debug) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0, 'label')"), db, 'insert with debug')

	assert_ok(db:exec("update refs set debug = null where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'clear debug')

	local row = first(db, "select debug from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(row.debug == nil, 'debug should be null; got: ' .. tostring(row.debug))
	db:close()
end)

test('changing refs.key is still rejected (regression)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"), db, 'insert ref')

	assert_fails_with(
		db:exec("update refs set key = 'y' where parent = '"
			.. hash_pk .. "' and idx = 0"),
		db, 'refs_immutable',
		'changing key should still be rejected')
	db:close()
end)

test('changing refs.child succeeds and marks the old child in needs_trace', function()
	-- The `child` column is editable so a rebind like `$x = 2` on top
	-- of `$x = 1` can UPSERT rather than delete-then-insert. The
	-- `refs_mark_needs_trace_after_child_update` trigger inserts the
	-- OLD child into `needs_trace` on any actual change, so GC can
	-- reason about the newly-orphaned object.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	set_current_process(db, cap_pk)
	local hash_pk = insert_hash(db, user_pk)
	local child_a = insert_scalar(db, user_pk)
	local child_b = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_a .. "', 'x', 0)"), db, 'insert ref')

	assert_ok(db:exec("update refs set child = '" .. child_b .. "' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'update child should succeed')

	-- The ref now points at child_b.
	local now = first(db, "select child from refs where parent = '"
		.. hash_pk .. "' and key = 'x'")
	assert(now.child == child_b, 'ref.child should now be child_b; got: ' .. tostring(now.child))

	-- The old child (child_a) should be sitting in needs_trace against
	-- the current cap.
	local mark = first(db, "select object_pk from needs_trace where object_pk = '"
		.. child_a .. "'")
	assert(mark ~= nil, 'child_a should be in needs_trace after the rebind')
	db:close()
end)

test('changing refs.child to the same value is a silent no-op (no mark)', function()
	-- The trigger's WHEN clause guards on `new.child is not old.child`
	-- so a bulk touch that writes the same value back doesn't
	-- spuriously enqueue an unnecessary trace.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	set_current_process(db, cap_pk)
	local hash_pk = insert_hash(db, user_pk)
	local child_a = insert_scalar(db, user_pk)

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. hash_pk .. "', '" .. child_a .. "', 'x', 0)"), db, 'insert ref')

	assert_ok(db:exec("update refs set child = '" .. child_a .. "' where parent = '"
		.. hash_pk .. "' and key = 'x'"), db, 'no-op child update should succeed')

	local marks = first(db, 'select count(*) as n from needs_trace')
	assert(tonumber(marks.n) == 0, 'needs_trace should stay empty on a no-op child update')
	db:close()
end)


-- ============================================================
-- refs key-vs-idx: hash parents require a key; array parents forbid one.
-- refs already enforces key + idx shape via CHECKs and unique
-- indexes; these two triggers add "the parent primitive determines
-- whether key or idx applies."
-- ============================================================

local function insert_array(db, owner_role)
	local sql = "insert into objects (base, owner_role) values ('a', '"
		.. owner_role .. "') returning object_pk"
	for row in db:nrows(sql) do
		return row.object_pk
	end
end

test('hash parent with null key is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'refs_hash_key_required',
		'null key under hash parent rejected')
	db:close()
end)

test('hash parent with non-null key is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"),
		db, 'non-null key under hash parent accepted')
	db:close()
end)

test('array parent with non-null key is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local array_pk = insert_array(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. array_pk .. "', '" .. child_pk .. "', 'k', 0)"),
		db, 'refs_array_key_forbidden',
		'non-null key under array parent rejected')
	db:close()
end)

test('array parent with null key is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local array_pk = insert_array(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. array_pk .. "', '" .. child_pk .. "', null, 0)"),
		db, 'null key under array parent accepted')
	db:close()
end)


-- ============================================================
-- frame_parent's target must be a frame.
-- The column-level CHECK covers the ROW HOLDING the pointer (must
-- be a frame); this trigger covers the TARGET (must also be a
-- frame). Together they enforce "frame_parent links a frame to a
-- frame."
-- ============================================================

test('frame_parent pointing at a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	-- A hash owned by user — non-frame target.
	local hash_pk = insert_hash(db, user_pk)

	-- Try to insert a frame whose frame_parent points at the hash.
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 0, '" .. hash_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'parent_frame_must_be_frame',
		'frame_parent → hash rejected')
	db:close()
end)

test('frame_parent pointing at a role row is rejected', function()
	-- Roles ('r' primitive) are the specific case the sprint index
	-- flagged: nothing in the old schema prevented frame_parent from
	-- pointing at a role.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local engine_pk = first(db, "select object_pk from objects where role_core = 'e'").object_pk

	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 0, '" .. engine_pk .. "', '" .. user_pk .. "')"
	assert_fails_with(db:exec(sql), db, 'parent_frame_must_be_frame',
		'frame_parent → role rejected')
	db:close()
end)

test('frame_parent pointing at a frame is accepted', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	-- Insert a nested frame under the cap — normal case.
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 0, '" .. cap_pk .. "', '" .. user_pk .. "')"
	assert_ok(db:exec(sql), db, 'frame_parent → cap frame accepted')
	db:close()
end)


-- ============================================================
-- engine_class column
-- Nullable text; when set, the row must be base='o'. What a
-- specific value MEANS (which Lua class, how it dispatches, how it
-- surfaces as a Caspian class) is deferred to a later sprint.
-- ============================================================

test('engine_class defaults to null on a fresh row', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)

	local row = first(db, "select engine_class from objects where object_pk = '" .. hash_pk .. "'")
	assert(row.engine_class == nil,
		'engine_class should default to null; got: ' .. tostring(row.engine_class))
	db:close()
end)

test("setting engine_class on an object ('o') row is accepted", function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (base, scalar_string, engine_class, owner_role) values ('o', 'blue', 'puck.uno/color', '" .. user_pk .. "')"),
		db, "engine_class on 'o' row accepted")

	local row = first(db, "select engine_class from objects where engine_class = 'puck.uno/color'")
	assert(row and row.engine_class == 'puck.uno/color',
		"engine_class value should round-trip")
	db:close()
end)

test('setting engine_class on a hash row is rejected (cross-column CHECK)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, engine_class, owner_role) "
			.. "values ('h', 'puck.uno/color', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		"engine_class on 'h' row rejected")
	db:close()
end)

test('setting engine_class on an array row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_fails_with(
		db:exec("insert into objects (base, engine_class, owner_role) "
			.. "values ('a', 'puck.uno/color', '" .. user_pk .. "')"),
		db, 'CHECK constraint',
		"engine_class on 'a' row rejected")
	db:close()
end)

test('engine_class is immutable — UPDATE from one value to another is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (object_pk, base, scalar_string, engine_class, owner_role) values ('11111111-1111-4111-8111-111111111111', 'o', 'blue', 'puck.uno/color', '"
			.. user_pk .. "')"),
		db, 'insert with engine_class')

	assert_fails_with(
		db:exec("update objects set engine_class = 'puck.uno/other' "
			.. "where object_pk = '11111111-1111-4111-8111-111111111111'"),
		db, 'objects_engine_class_immutable',
		'changing engine_class rejected')
	db:close()
end)

test('engine_class is immutable — UPDATE from null to a value is also rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Insert with no engine_class.
	local pk = first(db, "insert into objects (base, scalar_string, owner_role) values ('o', 'blue', '" .. user_pk .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set engine_class = 'puck.uno/color' where object_pk = '" .. pk .. "'"),
		db, 'objects_engine_class_immutable',
		'promoting a plain object to a masked one after INSERT is rejected')
	db:close()
end)

test('engine_class is immutable — UPDATE from a value to null is also rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local pk = first(db, "insert into objects (base, scalar_string, engine_class, owner_role) values ('o', 'blue', 'puck.uno/color', '" .. user_pk .. "') returning object_pk").object_pk

	assert_fails_with(
		db:exec("update objects set engine_class = null where object_pk = '" .. pk .. "'"),
		db, 'objects_engine_class_immutable',
		'clearing engine_class after INSERT is rejected')
	db:close()
end)

test('engine_class is NOT unique — many rows may share the same value', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	assert_ok(
		db:exec("insert into objects (base, scalar_string, engine_class, owner_role) values ('o', 'red',   'puck.uno/color', '" .. user_pk .. "')"),
		db, 'first color row accepted')
	assert_ok(
		db:exec("insert into objects (base, scalar_string, engine_class, owner_role) values ('o', 'green', 'puck.uno/color', '" .. user_pk .. "')"),
		db, 'second color row accepted')
	assert_ok(
		db:exec("insert into objects (base, scalar_string, engine_class, owner_role) values ('o', 'blue',  'puck.uno/color', '" .. user_pk .. "')"),
		db, 'third color row accepted')

	local n = first(db, "select count(*) as n from objects where engine_class = 'puck.uno/color'").n
	assert(tonumber(n) == 3, 'three color rows expected; got: ' .. tostring(n))
	db:close()
end)


-- ============================================================
-- frame_stmt_idx upper bound relative to frame_ast.
-- A frame's frame_stmt_idx may not exceed `json_array_length(frame_ast)`.
-- Length-N frame_ast → {0..N} valid; empty frame_ast → {0} valid (born terminal).
-- Enforced by the column-level CHECK constraint
-- `check (frame_stmt_idx is null or frame_stmt_idx <= json_array_length(frame_ast))`.
-- ============================================================

test('empty frame_ast: INSERT with frame_stmt_idx > 0 is rejected', function()
	-- Empty frame_ast → json_array_length(frame_ast) = 0 → only frame_stmt_idx = 0 is
	-- valid. frame_stmt_idx = 1 fails BOTH the column CHECK constraint
	-- (`frame_stmt_idx <= json_array_length(frame_ast)`) and the trigger
	-- `frames_stmt_idx_must_start_at_zero` (must be 0 at INSERT).
	-- The trigger fires first — either rejection is correct.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', '[]', 1, '" .. cap_pk .. "', '" .. user_pk .. "')"
	local rc = db:exec(sql)
	assert(rc ~= sqlite.OK, 'frame_stmt_idx=1 on empty frame_ast should have been rejected')
	local msg = db:errmsg()
	assert(msg:find('frames_stmt_idx_must_start_at_zero', 1, true)
			or msg:find('CHECK constraint', 1, true),
		'expected start-at-zero or CHECK constraint; got: ' .. tostring(msg))
	db:close()
end)

test('length-3 frame_ast: INSERT with frame_stmt_idx = 4 is rejected', function()
	-- Length-3 frame_ast → valid frame_stmt_idx ∈ {0..3}. frame_stmt_idx=4 fails the
	-- column CHECK. Two rules fire: the CHECK constraint AND
	-- `frames_stmt_idx_starts_at_zero` (must be 0 at INSERT).
	-- The trigger fires first — either rejection is correct for the
	-- test's intent (frame_stmt_idx=4 is not a valid birth state).
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "4, '" .. cap_pk .. "', '" .. user_pk .. "')"
	local rc = db:exec(sql)
	assert(rc ~= sqlite.OK, 'frame_stmt_idx=4 on insert should have been rejected')
	local msg = db:errmsg()
	assert(msg:find('frames_stmt_idx_must_start_at_zero', 1, true)
			or msg:find('CHECK constraint', 1, true),
		'expected start-at-zero or CHECK-constraint rejection; got: ' .. tostring(msg))
	db:close()
end)

test('length-3 frame_ast: UPDATE frame_stmt_idx to 4 is rejected', function()
	-- The CHECK constraint fires on UPDATE too. Advance the frame
	-- to a legal position, then try to jump to 4.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	local parent_pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do parent_pk = row.object_pk end

	-- Mark frame_gc=1 so an advance is allowed, then try a legal +1 first
	-- (fine), then push_marker again and try to jump to 4 — that
	-- fires the "+1 at a time" trigger before the CHECK; but if we
	-- go straight from any legal frame_stmt_idx directly to 4 (as an
	-- illegal update), we hit the CHECK. Simpler: set frame_gc=1, jump 0→4.
	assert_ok(db:exec("update objects set frame_gc = 1 where object_pk = '" .. parent_pk .. "'"),
		db, 'mark frame_gc=1')
	local rc = db:exec("update objects set frame_stmt_idx = 4 where object_pk = '" .. parent_pk .. "'")
	assert(rc ~= sqlite.OK, 'frame_stmt_idx=4 update should have been rejected')
	local msg = db:errmsg()
	assert(msg:find('CHECK constraint', 1, true)
			or msg:find('frames_stmt_idx_must_advance_by_one', 1, true),
		'expected CHECK or advance-by-one rejection; got: ' .. tostring(msg))
	db:close()
end)


-- ============================================================
-- (The in_trace column CHECK tests moved out with the column
-- itself when the trace-tables sprint integrated. in_trace is now
-- a temp table with a composite PK, not a column on objects.)
-- ============================================================


-- ============================================================
-- frame_stmt_idx: typeof-integer guard on the range-check column.
--
-- The bounds check (`frame_stmt_idx >= 0 and frame_stmt_idx <= json_array_length(frame_ast)`)
-- is a range compare, so a real like 1.5 passes numerically. The
-- `check (typeof(frame_stmt_idx) = 'integer' ...)` clause on the column
-- rejects it at write time.
--
-- Not applied to the flag columns (`frame_gc`, `frame_process_cap`, `persistent`,
-- `needs_trace`) because their `check (X = 1)` is a value check, not
-- a range check: SQLite's INTEGER affinity converts `1.0` and `'1'`
-- to integer 1 before the CHECK runs, so they land as integer; any
-- other value fails `= 1` on its own. No affinity hole to close.
-- ============================================================

test('frame_stmt_idx CHECK rejects a real (1.5) — defense-in-depth', function()
	-- Under normal operations the +1-at-a-time and starts-at-zero
	-- triggers catch non-integer frame_stmt_idx values before the column
	-- CHECK gets a chance. This test drops those triggers so the
	-- CHECK is the only rule left, then confirms it rejects a real.
	--
	-- Rationale: the CHECK is defense-in-depth. If the triggers
	-- ever evolve (e.g., allowing skips), the CHECK still guarantees
	-- the column holds only integers.
	local db = fresh_db()
	db:exec("drop trigger frames_stmt_idx_starts_at_zero;")
	db:exec("drop trigger frames_stmt_idx_advances_by_one;")

	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	-- Length-3 frame_ast so 1.5 would pass the bounds check numerically.
	local frame_pk
	local sql = "insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', "
		.. "'[[{\"in\":\"as\"},\"a\",{\"v\":1}],[{\"in\":\"as\"},\"b\",{\"v\":2}],[{\"in\":\"as\"},\"c\",{\"v\":3}]]', "
		.. "0, '" .. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do frame_pk = row.object_pk end

	assert_ok(db:exec("update objects set frame_gc = 1 where object_pk = '" .. frame_pk .. "'"),
		db, 'frame_gc=1 precondition')
	assert_fails_with(
		db:exec("update objects set frame_stmt_idx = 1.5 where object_pk = '" .. frame_pk .. "'"),
		db, 'CHECK constraint',
		'frame_stmt_idx=1.5 rejected by CHECK once the surrounding triggers are out of the way')
	db:close()
end)


-- ============================================================
-- refs.idx CHECK: typeof + non-negative
-- Same SQLite affinity fix as in_trace — `integer` alone accepts
-- 1.5 (real) and 'abc' (text) if the value satisfies `>= 0`. The
-- typeof clause closes the hole; the `>= 0` regression stays.
-- ============================================================

test('refs.idx accepts a non-negative integer', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_ok(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', 0)"),
		db, 'idx=0 accepted')
	db:close()
end)

test('refs.idx = 1.5 (real) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', 1.5)"),
		db, 'CHECK constraint',
		'idx=1.5 rejected')
	db:close()
end)

test("refs.idx = 'abc' (text) is rejected", function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', 'abc')"),
		db, 'CHECK constraint',
		"idx='abc' rejected")
	db:close()
end)

test('refs.idx = -1 is rejected (regression of the >= 0 rule)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_scalar(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'x', -1)"),
		db, 'CHECK constraint',
		'idx=-1 rejected')
	db:close()
end)


-- Runner (tests/main/lua/engine/run.lua) aggregates results across
-- files; no per-file report or os.exit here.
