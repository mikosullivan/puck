--[[
{
	"module": "test_get_latest_frame",
	"role": "Sprint frame-0 tests for `get_latest_frame`. Standalone — not wired into tests/main/lua/engine/run.lua because the sprint uses its own schema (`objects.idx` dropped, `processes.process_pk` as text UUID, `objects.frame_parent` added for the sub-frame chain) that differs from shipping. Promotes into the shared runner when the sprint closes.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_get_latest_frame`

Standalone test file for [`get_latest_frame`](../src/get_latest_frame.lua). Run from the repo root:

~~~
lua5.4 sprints/frame-0/tests/test_get_latest_frame.lua
~~~

Uses the sprint's schema at `sprints/frame-0/src/schema.sql` — a fork of shipping with `objects.idx` dropped, `processes.process_pk` as text UUID, and `objects.frame_parent` added. Under this schema only frame 0 of a process binds to `processes` via `process`; every sub-frame carries `frame_parent` pointing at the frame that pushed it.

`get_latest_frame(db, process_pk)` is a read-only lookup: finds frame 0 with one indexed query, then walks the `frame_parent`-inverse chain in a Lua loop until it finds a frame with no child. Returns that pk, or `nil` if the process has no frames, or raises `get_latest_frame_process_not_found` if the process pk isn't in the DB.

Seven tests: three-deep stack returns the deepest frame; single-frame process returns that frame; read-only (no writes to `processes` or `objects`); empty process returns `nil` AND leaves the process row intact (cleanup happens elsewhere); unknown process pk raises `get_latest_frame_process_not_found`; popped-but-captured frames (those whose `process` went null on pop) are excluded from consideration; two processes with independent chains each find their own deepest frame.
]]

package.path  = "./sprints/frame-0/src/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite            = require("lsqlite3")
local get_latest_frame  = require("get_latest_frame")

local SCHEMA_PATH = "sprints/frame-0/src/schema.sql"

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

local function user_pk(db)
	for row in db:nrows("select object_pk from objects where user") do
		return row.object_pk
	end
end

-- Insert a fresh processes row and return its pk. Used by tests to
-- arrange a process without going through the fresh-case creation
-- routine (which lives elsewhere).
local function insert_process(db)
	for row in db:nrows("insert into processes default values returning process_pk") do
		return row.process_pk
	end
end

-- Push frame 0 onto a process's stack — the one frame per process
-- that binds directly to `processes` via `process`. Raw INSERT, no
-- dispatch machinery. Returns the new frame's object_pk.
local function push_frame_0(db, process_pk, user)
	local sql = string.format(
		"insert into objects (primitive, ast, process, stmt_idx, owner_role) " ..
		"values ('f', '[[]]', '%s', 0, '%s') returning object_pk",
		process_pk, user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

-- Push a sub-frame chained under `parent_pk`. `process` is null on
-- sub-frames — chain membership is via `frame_parent`. Returns the
-- new frame's object_pk.
local function push_child_frame(db, parent_pk, user)
	local sql = string.format(
		"insert into objects (primitive, ast, frame_parent, stmt_idx, owner_role) " ..
		"values ('f', '[[]]', '%s', 0, '%s') returning object_pk",
		parent_pk, user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

-- ------------------------------------------------------------
-- Local test infrastructure (matches the ideas-tree pattern; this
-- test file predates promotion into the shared runner).
-- ------------------------------------------------------------

local pass_count, fail_count = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)

	if ok then
		pass_count = pass_count + 1
		print("  PASS " .. name)
	else
		fail_count = fail_count + 1
		print("  FAIL " .. name)
		print("       " .. tostring(err))
	end
end

local function assert_eq(actual, expected, msg)
	if actual == expected then return end
	error((msg or "not equal") .. "\n  actual:   " .. tostring(actual) .. "\n  expected: " .. tostring(expected), 2)
end

-- ==============================================================
-- Tests
-- ==============================================================

test("three-deep stack returns the deepest frame", function()
	local db = fresh_db()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	-- Only frame 0 binds to `processes`; sub-frames chain via
	-- `frame_parent`. The walk finds frame 0 first, then hops
	-- child → child until no child exists.
	local frame_0 = push_frame_0(db, process_pk, user)
	local frame_1 = push_child_frame(db, frame_0, user)
	local frame_2 = push_child_frame(db, frame_1, user)

	-- Sanity: exactly one frame binds to `processes` (frame 0), and
	-- two others chain via `frame_parent`.
	local frame_0_count

	for row in db:nrows(string.format(
		"select count(*) as n from objects where primitive = 'f' and process = '%s'",
		process_pk
	)) do
		frame_0_count = row.n
	end

	assert_eq(frame_0_count, 1, "exactly one frame (frame 0) should bind to the process")

	local sub_frame_count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f' and frame_parent is not null") do
		sub_frame_count = row.n
	end

	assert_eq(sub_frame_count, 2, "two sub-frames should chain via frame_parent")

	local pk = get_latest_frame(db, process_pk)
	assert_eq(pk, frame_2, "should return the deepest (last-chained) frame")

	-- Not just "some frame" — specifically NOT the shallower ones.
	assert_eq(pk ~= frame_0, true, "should not return frame_0")
	assert_eq(pk ~= frame_1, true, "should not return frame_1")

	db:close()
end)

test("single-frame process returns that frame (frame 0 with no children)", function()
	local db = fresh_db()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	-- Frame 0 with no sub-frames — the child walk terminates
	-- immediately and returns frame 0 itself.
	local only_frame = push_frame_0(db, process_pk, user)

	local pk = get_latest_frame(db, process_pk)
	assert_eq(pk, only_frame, "single-frame process should return that frame")

	db:close()
end)

test("read-only — no writes to processes or objects", function()
	local db = fresh_db()
	local user = user_pk(db)
	local process_pk = insert_process(db)
	push_frame_0(db, process_pk, user)

	local process_count_before
	local object_count_before

	for row in db:nrows("select count(*) as n from processes") do
		process_count_before = row.n
	end

	for row in db:nrows("select count(*) as n from objects") do
		object_count_before = row.n
	end

	get_latest_frame(db, process_pk)

	local process_count_after
	local object_count_after

	for row in db:nrows("select count(*) as n from processes") do
		process_count_after = row.n
	end

	for row in db:nrows("select count(*) as n from objects") do
		object_count_after = row.n
	end

	assert_eq(process_count_after, process_count_before, "should not touch processes")
	assert_eq(object_count_after,  object_count_before,  "should not touch objects")

	db:close()
end)

test("empty process returns nil and leaves the process row intact", function()
	local db = fresh_db()
	local process_pk = insert_process(db)

	local process_count_before
	local frame_count_before

	for row in db:nrows("select count(*) as n from processes") do
		process_count_before = row.n
	end

	for row in db:nrows(string.format(
		"select count(*) as n from objects where primitive = 'f' and process = '%s'",
		process_pk
	)) do
		frame_count_before = row.n
	end

	assert_eq(process_count_before, 1, "should start with the one process row we inserted")
	assert_eq(frame_count_before,   0, "should start with no frames on the process")

	local pk = get_latest_frame(db, process_pk)
	assert_eq(pk, nil, "empty process should return nil (no frame to resume)")

	local process_count_after

	for row in db:nrows("select count(*) as n from processes") do
		process_count_after = row.n
	end

	assert_eq(process_count_after, process_count_before,
		"process count should not change — get_latest_frame doesn't delete the process")

	local still_present = false

	for _ in db:nrows(string.format(
		"select 1 from processes where process_pk = '%s'",
		process_pk
	)) do
		still_present = true
	end

	assert_eq(still_present, true,
		"the specific process pk should still resolve after returning nil")

	db:close()
end)

test("unknown process pk raises get_latest_frame_process_not_found", function()
	local db = fresh_db()

	-- UUID-shape but guaranteed not to match anything.
	local bogus_pk = "00000000-0000-4000-8000-000000000000"

	local ok, err = pcall(function()
		get_latest_frame(db, bogus_pk)
	end)

	assert_eq(ok, false, "expected pcall to fail on unknown process pk")

	if not string.find(tostring(err), "get_latest_frame_process_not_found", 1, true) then
		error("expected get_latest_frame_process_not_found, got: " .. tostring(err))
	end

	-- The bogus pk should appear in the error message so a debugger
	-- can trace which pk the caller passed.
	if not string.find(tostring(err), bogus_pk, 1, true) then
		error("expected the bogus pk to appear in the error message, got: " .. tostring(err))
	end

	db:close()
end)

test("excludes popped frames (process and frame_parent both null)", function()
	local db = fresh_db()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	local live_frame = push_frame_0(db, process_pk, user)

	-- Insert a popped-but-captured frame: `primitive = 'f'`, `ast`
	-- set, both stack coordinates (`process` AND `frame_parent`)
	-- null. This row is a frame that was on some stack but got
	-- popped while a closure still held a ref to it. It MUST NOT be
	-- returned by get_latest_frame under any process pk.
	db:exec(string.format(
		"insert into objects (primitive, ast, owner_role) values ('f', '[[]]', '%s')",
		user
	))

	local pk = get_latest_frame(db, process_pk)
	assert_eq(pk, live_frame, "should return the on-stack frame, not the popped-but-captured one")

	db:close()
end)

test("two processes with independent chains each find their own deepest", function()
	local db = fresh_db()
	local user = user_pk(db)

	-- Process A: two frames deep.
	local process_a = insert_process(db)
	local a_frame_0 = push_frame_0(db, process_a, user)
	local a_frame_1 = push_child_frame(db, a_frame_0, user)

	-- Process B: three frames deep, interleaved insert order with
	-- process A so rowid ordering can't be what disambiguates.
	local process_b = insert_process(db)
	local b_frame_0 = push_frame_0(db, process_b, user)
	local b_frame_1 = push_child_frame(db, b_frame_0, user)
	local b_frame_2 = push_child_frame(db, b_frame_1, user)

	-- Also push one more onto A AFTER B's frames, to make the point:
	-- if the routine were using rowid ordering it might return the
	-- wrong frame here.
	local a_frame_2 = push_child_frame(db, a_frame_1, user)

	local deepest_a = get_latest_frame(db, process_a)
	local deepest_b = get_latest_frame(db, process_b)

	assert_eq(deepest_a, a_frame_2, "process A should resolve to its own deepest frame")
	assert_eq(deepest_b, b_frame_2, "process B should resolve to its own deepest frame")
	assert_eq(deepest_a ~= deepest_b, true, "the two processes should return distinct frame pks")

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
