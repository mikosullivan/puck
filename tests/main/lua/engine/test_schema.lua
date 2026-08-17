#!/usr/bin/env lua5.4

--[[
{
	"module": "test_schema",
	"role": "Schema tests for `src/engine/cvm/schema.sql`. Exercises the load-bearing invariants: the `gc` column and its four gc-cycle rules (advance-couples-with-gc, gc-set-cascade-deletes-children, child-delete-requires-parent-gc, gc-reset-requires-no-children), the parent_frame / process immutability triggers, the cap-as-frame design (a frame with `process=1` and `ast='[]'` sits atop each call stack), refs-based ownership + the one-hash-one-array cap, the scopes convention (bucket → 'scopes' → array of hashes), the hash-key identifier rule, and the frame_scoped_vars / object_bucket / object_stack views."
}
]]

--[[
# `test_schema`

Runs against the sprint's schema. Each test loads the schema into a fresh in-memory SQLite and exercises the specific invariant under test.

The gc cycle is the load-bearing design:

1. Walker: `UPDATE frame SET stmt_idx = stmt_idx + 1, gc = 1` — one statement, both fields.
2. `AFTER UPDATE OF gc` fires: DELETE FROM objects WHERE parent_frame = frame — child (marker or completed nested call) swept.
3. Each child's `BEFORE-DELETE` checks parent.gc = 1 — passes because step 2's row-update already happened.
4. Engine runs GC (needs_trace sweep, on_close callbacks eventually), adds child frames if needed, waits for them to complete.
5. Engine: `UPDATE frame SET gc = null` — requires no children.

Every state between steps is a legal at-rest state. Bypass paths get rejected.
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local sqlite = require('lsqlite3')

local SCHEMA_PATH = 'src/engine/cvm/schema.sql'


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

local function seed_user(db)
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		return row.object_pk
	end
	error('user seed not present in schema')
end

--[[
Insert a fresh process cap — a `primitive='f'` frame with `process=1`,
`ast='[]'`, `stmt_idx=0`, no parent. This IS the process (its
`object_pk` is the process identity). Frame 0 gets seeded under it as
a nested frame.
]]
local function insert_process(db, user_pk)
	local pk
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do
		pk = row.object_pk
	end
	return pk
end

--[[
Insert frame 0 under the cap. Frame 0 is a nested frame (parent_frame
= cap_pk, process = null). Returns frame 0's `object_pk`.
]]
local function insert_frame_0(db, cap_pk, user_pk)
	local pk
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '"
		.. cap_pk .. "', '" .. user_pk .. "') returning object_pk"
	for row in db:nrows(sql) do
		pk = row.object_pk
	end
	return pk
end

--[[
Push a mid-dispatch marker child under `parent_pk` — a frame born
in the terminal shape: empty ast, gc=null. Its presence signals
"parent is mid-dispatch"; parent's next advance cascade-deletes it,
and the terminal-state check passes cleanly.
]]
local function push_marker(db, parent_pk, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert(db:exec(sql) == sqlite.OK, 'push marker failed: ' .. tostring(db:errmsg()))
end

--[[
Walker's canonical advance: increment stmt_idx AND set gc=1 in one
UPDATE. Wrapped so tests read at the intent level.
]]
local function walker_advance(db, parent_pk, new_stmt_idx)
	local sql = "update objects set stmt_idx = " .. new_stmt_idx
		.. ", gc = 1 where object_pk = '" .. parent_pk .. "'"
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

test('gc column exists on objects', function()
	local db = fresh_db()
	local found = false
	for row in db:nrows("pragma table_info(objects)") do
		if row.name == 'gc' then found = true; break end
	end
	assert(found, 'objects should have a gc column')
	db:close()
end)

test('dcok column does NOT exist (removed in gc-cycle design)', function()
	local db = fresh_db()
	for row in db:nrows("pragma table_info(objects)") do
		assert(row.name ~= 'dcok', 'dcok should no longer exist')
	end
	db:close()
end)

test('gc defaults to null on a fresh frame', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)
	local row = first(db, "select gc from objects where object_pk = '" .. frame_pk .. "'")
	assert(row.gc == nil, 'gc should default to null; got ' .. tostring(row.gc))
	db:close()
end)


-- ============================================================
-- gc column shape
-- ============================================================

test('gc = 0 is rejected (only 1 or null)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local sql = "insert into objects (primitive, gc, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', 0, '[]', 0, '" .. cap_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'gc = 0 should be rejected')
	db:close()
end)

test('gc = 1 on a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, gc, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'gc = 1 on a hash is rejected')
	db:close()
end)


-- ============================================================
-- Frame anchor rules — XOR and uniqueness
-- ============================================================

test('frame with BOTH parent_frame and process=1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, process, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'both anchors rejected')
	db:close()
end)

test('frame with NEITHER parent_frame nor process=1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, ast, stmt_idx, owner_role) "
		.. "values ('f', '[]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'anchorless frame rejected')
	db:close()
end)

test('a parent frame can only have one child at a time', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	-- Try a second child.
	local sql = "insert into objects (primitive, gc, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'UNIQUE',
		'second child rejected')
	db:close()
end)


-- ============================================================
-- Cap-specific constraints
-- ============================================================

test('cap with non-empty ast is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 1, '[[{\"in\":\"as\"},\"x\",{\"v\":1}]]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'non-empty ast on cap rejected')
	db:close()
end)

test('process = 1 on a non-frame row is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, process, owner_role) "
		.. "values ('h', 1, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'process=1 on hash rejected')
	db:close()
end)

test('process = 0 is rejected (only 1 or null)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, process, ast, stmt_idx, owner_role) "
		.. "values ('f', 0, '[]', 0, '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'CHECK constraint',
		'process=0 rejected')
	db:close()
end)


-- ============================================================
-- Self-parent rejection
-- ============================================================

test('a frame cannot be its own parent', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- Try to insert a frame whose parent_frame equals its own object_pk.
	-- Need to supply the pk explicitly so we know the target value.
	local self_pk = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
	local sql = string.format(
		"insert into objects (object_pk, primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('%s', 'f', '[]', 0, '%s', '%s')",
		self_pk, self_pk, user_pk)
	assert_fails_with(db:exec(sql), db, 'frames_parent_frame_not_self',
		'self-parenting frame rejected')
	db:close()
end)


-- ============================================================
-- Immutability
-- ============================================================

test('parent_frame is immutable', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_a = insert_process(db, user_pk)
	local cap_b = insert_process(db, user_pk)
	local frame_a = insert_frame_0(db, cap_a, user_pk)
	local frame_b = insert_frame_0(db, cap_b, user_pk)

	-- push a nested frame under a
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. frame_a .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'nested insert')
	local nested_pk = first(db, "select object_pk from objects where parent_frame = '" .. frame_a .. "'").object_pk

	assert_fails_with(
		db:exec("update objects set parent_frame = '" .. frame_b .. "' where object_pk = '" .. nested_pk .. "';"),
		db, 'objects_parent_frame_immutable',
		'reparenting rejected')
	db:close()
end)

test('process is immutable', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)

	-- try to un-cap the cap by clearing its process flag
	assert_fails_with(
		db:exec("update objects set process = null where object_pk = '" .. cap_pk .. "';"),
		db, 'objects_process_immutable',
		'clearing process rejected')
	db:close()
end)

test('gc is NOT immutable (bidirectional under the new cycle)', function()
	-- Just a smoke test that setting gc to 1 (as part of a proper
	-- advance) and back to null works. Full cycle tests below cover
	-- the semantics.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, frame_pk, user_pk)

	assert_ok(walker_advance(db, frame_pk, 1), db, 'advance succeeded')

	-- After advance and child sweep, no children — safe to reset gc.
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. frame_pk .. "';"),
		db, 'gc reset succeeded')
	db:close()
end)


-- ============================================================
-- stmt_idx transitions
-- ============================================================

test('a frame at INSERT must have stmt_idx = 0', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 5, '" .. cap_pk .. "', '" .. user_pk .. "');"
	assert_fails_with(db:exec(sql), db, 'frames_stmt_idx_must_start_at_zero',
		'stmt_idx = 5 at insert rejected')
	db:close()
end)

test('stmt_idx skip (0 → 5) is rejected', function()
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

test('stmt_idx rewind is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db, 'first advance')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'reset gc')
	push_marker(db, parent_pk, user_pk)
	assert_fails_with(
		walker_advance(db, parent_pk, 0),
		db, 'frames_stmt_idx_',
		'rewind rejected')
	db:close()
end)


-- ============================================================
-- The gc cycle — four invariants
-- ============================================================

--[[
Invariant 1a: advancing stmt_idx requires gc = 1 in the same UPDATE.
]]
test('advance without gc=1 is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_requires_gc',
		'advance without gc=1 rejected')
	db:close()
end)

test('advance with gc explicitly null is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = 1, gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_advance_requires_gc',
		'advance with explicit gc=null rejected')
	db:close()
end)

--[[
Invariant 1b: setting gc=1 requires stmt_idx to advance in the same UPDATE.
]]
test('setting gc=1 alone (no stmt_idx change) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set gc = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_gc_set_requires_advance',
		'gc=1 without stmt_idx change rejected')
	db:close()
end)

test('setting gc=1 with stmt_idx = stmt_idx (no-op mention) is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	assert_fails_with(
		db:exec("update objects set stmt_idx = stmt_idx, gc = 1 where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_gc_set_requires_advance',
		'gc=1 with no stmt_idx change rejected')
	db:close()
end)

--[[
Setting gc=1 sweeps children unconditionally — including a still-
active (gc=null) child. The schema doesn't distinguish; walker
discipline is expected to only advance when children are ready to
sweep. Test locks in the mechanical rule.
]]
test('advance while an active (gc=null) child exists sweeps the child', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Push an ACTIVE nested frame (gc=null), not a marker.
	local sql = "insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db)
	local active_child_pk = first(db,
		"select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(walker_advance(db, parent_pk, 1), db, 'advance succeeds')

	-- Active child was swept along with everything else under parent.
	local still = first(db, "select object_pk from objects where object_pk = '" .. active_child_pk .. "'")
	assert(still == nil, 'active child should have been swept by the cascade')
	db:close()
end)

--[[
Invariant 2: setting gc=1 cascade-deletes children.
Invariant 3: child-delete requires parent.gc = 1.
Both exercised together in the happy-path cycle.
]]
test('advance sweeps the child in the same op (invariants 2 + 3)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	local marker_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_ok(walker_advance(db, parent_pk, 1), db, 'advance succeeded')

	-- Child is gone; parent is at stmt_idx=1, gc=1.
	local marker_row = first(db, "select object_pk from objects where object_pk = '" .. marker_pk .. "'")
	assert(marker_row == nil, 'marker should be deleted')

	local parent_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(parent_row.stmt_idx) == 1, 'stmt_idx should be 1')
	assert(parent_row.gc == 1, 'gc should be 1')
	db:close()
end)

--[[
Invariant 3 as bypass check: direct DELETE of a child frame with
parent.gc = null must abort.
]]
test('direct DELETE of a child frame under a gc-null parent is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	local child_pk = first(db, "select object_pk from objects where parent_frame = '" .. parent_pk .. "'").object_pk

	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. child_pk .. "';"),
		db, 'frames_child_delete_requires_parent_gc',
		'direct child delete rejected')

	-- Child still present after rejection.
	local still = first(db, "select object_pk from objects where object_pk = '" .. child_pk .. "'")
	assert(still ~= nil, 'child survives the rejected delete')
	db:close()
end)

--[[
Invariant 4: resetting gc=null requires no child frames.
]]
test('resetting gc to null with no children is allowed', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db, 'advance')

	-- After advance, no children. Reset should succeed.
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'gc reset succeeded')
	db:close()
end)

test('resetting gc to null while a child still exists is rejected', function()
	-- Simulating a bug: engine tries to reset gc without cleaning up
	-- callback children. Should abort.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db, 'advance')

	-- Manually insert a child under this parent (simulating an
	-- on_close callback that added work). The parent is gc=1, so the
	-- child insert is legal.
	local sql = "insert into objects (primitive, gc, ast, stmt_idx, parent_frame, owner_role) "
		.. "values ('f', 1, '[]', 0, '" .. parent_pk .. "', '" .. user_pk .. "');"
	assert_ok(db:exec(sql), db, 'callback-style child insert')

	-- Now engine tries to reset gc. Should fail because a child still exists.
	assert_fails_with(
		db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'frames_gc_reset_requires_no_children',
		'gc reset with children rejected')
	db:close()
end)


-- ============================================================
-- Full cycle
-- ============================================================

test('two full advance cycles in sequence', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Cycle 1.
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 1), db, 'cycle 1 advance')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'cycle 1 gc reset')

	-- Cycle 2.
	push_marker(db, parent_pk, user_pk)
	assert_ok(walker_advance(db, parent_pk, 2), db, 'cycle 2 advance')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. parent_pk .. "';"),
		db, 'cycle 2 gc reset')

	local row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. parent_pk .. "'")
	assert(tonumber(row.stmt_idx) == 2, 'stmt_idx should be 2 after two cycles')
	assert(row.gc == nil, 'gc should be null after both cycles complete')

	local n = first(db, "select count(*) as n from objects where parent_frame = '" .. parent_pk .. "'")
	assert(tonumber(n.n) == 0, 'no children remain')
	db:close()
end)


-- ============================================================
-- refs — hash keys must be identifier-compliant
-- ============================================================

--[[
Insert a bare hash owned by the user seed. Returns its pk.
]]
local function insert_hash(db, user_pk)
	local sql = "insert into objects (primitive, owner_role) values ('h', '"
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

test('hash key: leading digit is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', '1x', 0)"),
		db, 'refs_hash_key_must_be_identifier',
		'leading digit rejected')
	db:close()
end)

test('hash key: dash character is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'my-var', 0)"),
		db, 'refs_hash_key_must_be_identifier',
		'dash rejected')
	db:close()
end)

test('hash key: space is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', 'foo bar', 0)"),
		db, 'refs_hash_key_must_be_identifier',
		'space rejected')
	db:close()
end)

test('hash key: empty string is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash_pk = insert_hash(db, user_pk)
	local child_pk = insert_hash(db, user_pk)

	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. hash_pk .. "', '" .. child_pk .. "', '', 0)"),
		db, 'refs_hash_key_must_be_identifier',
		'empty key rejected')
	db:close()
end)

test('array entry with null key is not affected by the identifier rule', function()
	-- Sanity: the rule only fires on hash keys (key not null with hash parent).
	-- Array entries have key=null and should be unaffected.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local sql = "insert into objects (primitive, owner_role) values ('a', '"
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
	local sql = "insert into objects (primitive, owner_role) values ('h', '"
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
	local sql = "insert into objects (primitive, owner_role) values ('"
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
	local sql = "insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 1, '" .. user_pk .. "') returning object_pk"
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
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

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
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

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
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

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
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

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
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

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
	-- bucket_ref (owner→bucket) via refs_parent.
	assert_plan_contains(p, 'SEARCH bucket_ref USING INDEX refs_parent (parent=?)',
		'bucket_ref should use the refs_parent index')
	-- bucket row via objects PK.
	assert_plan_contains(p, 'SEARCH bucket USING INDEX sqlite_autoindex_objects_1 (object_pk=?)',
		'bucket should be found via the objects PK index')
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

	-- All six joins hit indexes; the extra `var_name = ?` predicate
	-- lets var_ref use the (parent, key) unique index for a direct hit.
	assert_plan_contains(p, 'SEARCH f USING INDEX sqlite_autoindex_objects_1 (object_pk=?)',
		'f should use the PK index')
	assert_plan_contains(p, 'SEARCH bucket_ref USING INDEX refs_parent (parent=?)',
		'bucket_ref should use the refs_parent index')
	assert_plan_contains(p, 'SEARCH bucket USING INDEX sqlite_autoindex_objects_1 (object_pk=?)',
		'bucket joined via objects PK index')
	assert_plan_contains(p, 'scopes_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'scopes_ref uses (parent, key) unique index')
	assert_plan_contains(p, 'var_ref USING INDEX sqlite_autoindex_refs_1 (parent=? AND key=?)',
		'var_ref uses (parent, key) unique index for direct var lookup')
	assert_plan_lacks(p, 'SCAN', 'effective-binding plan should have no full scans')
	db:close()
end)


-- ============================================================
-- object_bucket / object_stack views
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
		.. obj .. "', '" .. bucket .. "', null, 0)"), db)

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
		.. obj .. "', '" .. stack .. "', null, 0)"), db)

	local row = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.bucket_pk == nil, 'bucket_pk should be null when only an array-child exists')
	db:close()
end)

test('object_stack: returns null for an object with no stack', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')

	local row = first(db, "select stack_pk from object_stack "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.stack_pk == nil, 'stack_pk should be null (no stack)')
	db:close()
end)

test('object_stack: returns the stack_pk when the object has an array-child', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local obj = insert_object(db, user_pk, 'o')
	local stack = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. stack .. "', null, 0)"), db)

	local row = first(db, "select stack_pk from object_stack "
		.. "where object_pk = '" .. obj .. "'")
	assert(row.stack_pk == stack, 'stack_pk should match the linked array')
	db:close()
end)

test('object_bucket / object_stack: frames are included (non-container)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket = insert_hash(db, user_pk)
	local stack  = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket .. "', null, 0)"), db)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. stack .. "', null, 1)"), db)

	local b = first(db, "select bucket_pk from object_bucket "
		.. "where object_pk = '" .. frame_pk .. "'")
	assert(b.bucket_pk == bucket, 'frame bucket found')

	local s = first(db, "select stack_pk from object_stack "
		.. "where object_pk = '" .. frame_pk .. "'")
	assert(s.stack_pk == stack, 'frame stack found')
	db:close()
end)

test('object_bucket / object_stack: containers do not appear (out of scope)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local hash = insert_hash(db, user_pk)

	local row = first(db, "select object_pk from object_bucket "
		.. "where object_pk = '" .. hash .. "'")
	assert(row == nil, 'hash should not appear in object_bucket')

	row = first(db, "select object_pk from object_stack "
		.. "where object_pk = '" .. hash .. "'")
	assert(row == nil, 'hash should not appear in object_stack')
	db:close()
end)


-- ============================================================
-- Process completion
-- ============================================================

test('cap reaches terminal state (stmt_idx=1, gc=null, no children) after frame 0 is swept', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Frame 0 finishes normally: advance past its single statement,
	-- run gc cycle to completion. Now frame 0 is in terminal state
	-- and cascade-sweep-eligible.
	assert_ok(walker_advance(db, frame_pk, 1), db, 'frame 0 advance')
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. frame_pk .. "';"),
		db, 'frame 0 gc reset')

	-- Cap advances 0→1 with gc=1; cascade sweeps frame 0 (which is
	-- gc=null and passes the delete rule).
	assert_ok(walker_advance(db, cap_pk, 1), db, 'cap advance sweeps frame 0')

	-- Cap resets gc → null. No children remain.
	assert_ok(db:exec("update objects set gc = null where object_pk = '" .. cap_pk .. "';"),
		db, 'cap gc reset')

	-- Cap is now terminal: stmt_idx=1, gc=null, no children.
	local cap_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(tonumber(cap_row.stmt_idx) == 1, 'cap stmt_idx should be 1')
	assert(cap_row.gc == nil, 'cap gc should be null')

	local children = first(db, "select count(*) as n from objects where parent_frame = '" .. cap_pk .. "'")
	assert(tonumber(children.n) == 0, 'cap should have no children')
	db:close()
end)

test('deleting a frame with gc=null is accepted regardless of stmt_idx', function()
	-- The delete rule permits deletion at any stmt_idx as long as gc
	-- is null. Uses a cap (no parent, so no cascade check) with no
	-- children (no FK to satisfy) to exercise the rule directly.
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	-- Cap: stmt_idx=0, gc=null, no children, no parent.
	assert_ok(db:exec("delete from objects where object_pk = '" .. cap_pk .. "';"),
		db, 'delete at gc=null succeeded')
	db:close()
end)

test('deleting a frame in gc=1 (mid-cleanup) state is rejected', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Advance to past-max with gc=1 — mid-cleanup, gc not yet reset.
	assert_ok(walker_advance(db, frame_pk, 1), db, 'advance')

	assert_fails_with(
		db:exec("delete from objects where object_pk = '" .. frame_pk .. "';"),
		db, 'frames_delete_requires_gc_null',
		'mid-cleanup delete rejected')
	db:close()
end)

test('deleting a frame marks its bucket needs_trace=1 via cascade of the owner→bucket ref', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Attach a bucket to frame 0 as a refs row (owner→bucket).
	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db)

	-- Delete frame 0 via cap-advance cascade. Frame 0's row goes; its
	-- outgoing refs (including owner→bucket) cascade-delete (refs.parent
	-- ON DELETE CASCADE); each ref-delete fires
	-- refs_mark_needs_trace_after_delete → marks the bucket needs_trace=1.
	assert_ok(walker_advance(db, cap_pk, 1), db, 'cap advance sweeps frame 0')

	-- Bucket survives; needs_trace set.
	local bucket = first(db, "select needs_trace from objects "
		.. "where object_pk = '" .. bucket_pk .. "'")
	assert(bucket ~= nil, 'bucket should survive frame delete')
	assert(tonumber(bucket.needs_trace) == 1, 'bucket should be marked needs_trace=1')
	db:close()
end)

test('swapping the owner→bucket ref for a different target marks the old target needs_trace=1', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- Attach bucket A to frame 0.
	local bucket_a = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_a .. "', null, 0)"), db)

	-- Swap for bucket B: delete the old ref, insert a new one.
	assert_ok(db:exec("delete from refs where parent = '" .. frame_pk
		.. "' and child = '" .. bucket_a .. "'"), db, 'drop old ref')

	local bucket_b = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_b .. "', null, 0)"), db, 'add new ref')

	-- Old bucket (A) marked needs_trace=1 (from the ref-delete); new (B) not.
	local a = first(db, "select needs_trace from objects "
		.. "where object_pk = '" .. bucket_a .. "'")
	assert(tonumber(a.needs_trace) == 1, 'old bucket should be marked needs_trace=1')

	local b = first(db, "select needs_trace from objects "
		.. "where object_pk = '" .. bucket_b .. "'")
	assert(b.needs_trace == nil, 'new bucket should not be marked')
	db:close()
end)

test('a non-container owner can hold at most one hash-child (its bucket)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	-- First hash-ref: accepted.
	local hash_a = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. hash_a .. "', null, 0)"), db, 'first hash-child')

	-- Second hash-ref: rejected by the one-hash-one-array cap trigger.
	local hash_b = insert_hash(db, user_pk)
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. frame_pk .. "', '" .. hash_b .. "', null, 1)"),
		db, 'refs_owner_at_most_one_hash_and_one_array',
		'second hash-child rejected')
	db:close()
end)

test('a non-container owner can hold at most one array-child (its stack)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local arr_a = insert_object(db, user_pk, 'a')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. arr_a .. "', null, 0)"), db, 'first array-child')

	local arr_b = insert_object(db, user_pk, 'a')
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. frame_pk .. "', '" .. arr_b .. "', null, 1)"),
		db, 'refs_owner_at_most_one_hash_and_one_array',
		'second array-child rejected')
	db:close()
end)

test('a regular object (primitive=o) can hold at most one hash and one array', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	-- A full object (non-scalar 'o').
	local obj = insert_object(db, user_pk, 'o')

	local bucket_a = insert_hash(db, user_pk)
	local bucket_b = insert_hash(db, user_pk)
	local stack_a  = insert_object(db, user_pk, 'a')
	local stack_b  = insert_object(db, user_pk, 'a')

	-- First hash + first array: accepted.
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. bucket_a .. "', null, 0)"), db, 'first hash-child')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. obj .. "', '" .. stack_a .. "', null, 1)"), db, 'first array-child')

	-- Second hash: rejected.
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. obj .. "', '" .. bucket_b .. "', null, 2)"),
		db, 'refs_owner_at_most_one_hash_and_one_array',
		'second hash-child on regular object rejected')

	-- Second array: rejected.
	assert_fails_with(
		db:exec("insert into refs (parent, child, key, idx) values ('"
			.. obj .. "', '" .. stack_b .. "', null, 3)"),
		db, 'refs_owner_at_most_one_hash_and_one_array',
		'second array-child on regular object rejected')
	db:close()
end)

test('a non-container owner can hold one hash AND one array (bucket + stack)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local frame_pk = insert_frame_0(db, cap_pk, user_pk)

	local bucket_pk = insert_hash(db, user_pk)
	local stack_pk  = insert_object(db, user_pk, 'a')

	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. bucket_pk .. "', null, 0)"), db, 'bucket ref')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_pk .. "', '" .. stack_pk .. "', null, 1)"), db, 'stack ref')
	db:close()
end)

test('a bucket can be shared across multiple owners (owner→bucket is just a ref)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_a = insert_process(db, user_pk)
	local cap_b = insert_process(db, user_pk)
	local frame_a = insert_frame_0(db, cap_a, user_pk)
	local frame_b = insert_frame_0(db, cap_b, user_pk)

	local shared = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_a .. "', '" .. shared .. "', null, 0)"), db, 'first owner')
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. frame_b .. "', '" .. shared .. "', null, 0)"), db, 'second owner (shared)')
	db:close()
end)

test('scalars can own a bucket (regular objects, no exclusion)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)

	local scalar_pk = first(db, "insert into objects (primitive, scalar_type, scalar_value, owner_role) "
		.. "values ('o', 'n', 42, '" .. user_pk .. "') returning object_pk").object_pk

	local bucket_pk = insert_hash(db, user_pk)
	assert_ok(db:exec("insert into refs (parent, child, key, idx) values ('"
		.. scalar_pk .. "', '" .. bucket_pk .. "', null, 0)"), db, 'scalar owns bucket')
	db:close()
end)

test('sweeping a nested marker leaves the cap untouched (still stmt_idx=0)', function()
	local db = fresh_db()
	local user_pk = seed_user(db)
	local cap_pk = insert_process(db, user_pk)
	local parent_pk = insert_frame_0(db, cap_pk, user_pk)
	push_marker(db, parent_pk, user_pk)

	-- Advance sweeps the marker under frame 0. Cap is unaffected —
	-- still at stmt_idx=0, gc=null, still parent of frame 0.
	assert_ok(walker_advance(db, parent_pk, 1), db)

	local cap_row = first(db, "select stmt_idx, gc from objects where object_pk = '" .. cap_pk .. "'")
	assert(tonumber(cap_row.stmt_idx) == 0, 'cap stmt_idx should still be 0')
	assert(cap_row.gc == nil, 'cap gc should still be null')

	local frame_0_still_there = first(db, "select object_pk from objects where object_pk = '" .. parent_pk .. "'")
	assert(frame_0_still_there ~= nil, 'frame 0 should still exist under cap')
	db:close()
end)


-- Runner (tests/main/lua/engine/run.lua) aggregates results across
-- files; no per-file report or os.exit here.
