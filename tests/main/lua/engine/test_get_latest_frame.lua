--[[
{
	"spec": "test_get_latest_frame",
	"role": "Tests for `cvm.get_latest_frame`. Verifies the revival routine: three-deep stack returns the deepest frame; single-frame process returns that frame; read-only (no writes); empty process returns nil and leaves the process row intact; unknown process pk raises; popped frames are excluded; two processes with independent chains each find their own deepest frame.",
	"status": "walking-skeleton"
}
]]

--[[
# `test_get_latest_frame`

Behavioural tests for the `get_latest_frame(db, process_pk) -> frame_pk | nil` routine at [src/engine/cvm/get_latest_frame.lua](https://puck.uno/src/engine/cvm/get_latest_frame.lua). Finds frame 0 via `process`, walks the `parent_frame` chain down to the deepest live frame.
]]

local h                = require('helpers')
local cvm              = require('cvm.open')
local get_latest_frame = require('cvm.get_latest_frame')

local function user_pk(db)
	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		return row.object_pk
	end
end

local function insert_process(db)
	for row in db:nrows("insert into processes default values returning process_pk") do
		return row.process_pk
	end
end

local function push_frame_0(db, process_pk, user)
	local sql = string.format(
		"insert into objects (primitive, ast, process_pk, stmt_idx, owner_role) " ..
		"values ('f', '[[]]', '%s', 0, '%s') returning object_pk",
		process_pk, user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

local function push_child_frame(db, parent_pk, user)
	local sql = string.format(
		"insert into objects (primitive, ast, parent_frame, stmt_idx, owner_role) " ..
		"values ('f', '[[]]', '%s', 0, '%s') returning object_pk",
		parent_pk, user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

h.test('get_latest_frame — three-deep stack returns the deepest frame', function()
	local db = cvm.open()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	local frame_0 = push_frame_0(db, process_pk, user)
	local frame_1 = push_child_frame(db, frame_0, user)
	local frame_2 = push_child_frame(db, frame_1, user)

	local frame_0_count

	for row in db:nrows(string.format(
		"select count(*) as n from objects where primitive = 'f' and process_pk = '%s'",
		process_pk
	)) do
		frame_0_count = row.n
	end

	h.assert_eq(frame_0_count, 1, 'exactly one frame (frame 0) should bind to the process')

	local sub_frame_count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f' and parent_frame is not null") do
		sub_frame_count = row.n
	end

	h.assert_eq(sub_frame_count, 2, 'two sub-frames should chain via parent_frame')

	local pk = get_latest_frame(db, process_pk)
	h.assert_eq(pk, frame_2, 'should return the deepest (last-chained) frame')
	h.assert_true(pk ~= frame_0, 'should not return frame_0')
	h.assert_true(pk ~= frame_1, 'should not return frame_1')

	db:close()
end)

h.test('get_latest_frame — single-frame process returns that frame (frame 0 with no children)', function()
	local db = cvm.open()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	local only_frame = push_frame_0(db, process_pk, user)

	local pk = get_latest_frame(db, process_pk)
	h.assert_eq(pk, only_frame, 'single-frame process should return that frame')

	db:close()
end)

h.test('get_latest_frame — read-only, no writes to processes or objects', function()
	local db = cvm.open()
	local user = user_pk(db)
	local process_pk = insert_process(db)
	push_frame_0(db, process_pk, user)

	local process_count_before
	local object_count_before

	for row in db:nrows('select count(*) as n from processes') do
		process_count_before = row.n
	end

	for row in db:nrows('select count(*) as n from objects') do
		object_count_before = row.n
	end

	get_latest_frame(db, process_pk)

	local process_count_after
	local object_count_after

	for row in db:nrows('select count(*) as n from processes') do
		process_count_after = row.n
	end

	for row in db:nrows('select count(*) as n from objects') do
		object_count_after = row.n
	end

	h.assert_eq(process_count_after, process_count_before, 'should not touch processes')
	h.assert_eq(object_count_after,  object_count_before,  'should not touch objects')

	db:close()
end)

h.test('get_latest_frame — empty process returns nil and leaves the process row intact', function()
	local db = cvm.open()
	local process_pk = insert_process(db)

	local process_count_before

	for row in db:nrows('select count(*) as n from processes') do
		process_count_before = row.n
	end

	h.assert_eq(process_count_before, 1, 'should start with the one process row we inserted')

	local pk = get_latest_frame(db, process_pk)
	h.assert_eq(pk, nil, 'empty process should return nil')

	local process_count_after

	for row in db:nrows('select count(*) as n from processes') do
		process_count_after = row.n
	end

	h.assert_eq(process_count_after, process_count_before, 'process count should not change')

	local still_present = false

	for _ in db:nrows(string.format(
		"select 1 from processes where process_pk = '%s'",
		process_pk
	)) do
		still_present = true
	end

	h.assert_eq(still_present, true, 'the process pk should still resolve after returning nil')

	db:close()
end)

h.test('get_latest_frame — unknown process pk raises get_latest_frame_process_not_found', function()
	local db = cvm.open()

	local bogus_pk = '00000000-0000-4000-8000-000000000000'

	local ok, err = pcall(function()
		get_latest_frame(db, bogus_pk)
	end)

	h.assert_eq(ok, false, 'expected pcall to fail on unknown process pk')

	if not string.find(tostring(err), 'get_latest_frame_process_not_found', 1, true) then
		error('expected get_latest_frame_process_not_found, got: ' .. tostring(err))
	end

	if not string.find(tostring(err), bogus_pk, 1, true) then
		error('expected the bogus pk to appear in the error message, got: ' .. tostring(err))
	end

	db:close()
end)

h.test('get_latest_frame — excludes popped frames (process and parent_frame both null)', function()
	local db = cvm.open()
	local user = user_pk(db)
	local process_pk = insert_process(db)

	local live_frame = push_frame_0(db, process_pk, user)

	db:exec(string.format(
		"insert into objects (primitive, ast, owner_role) values ('f', '[[]]', '%s')",
		user
	))

	local pk = get_latest_frame(db, process_pk)
	h.assert_eq(pk, live_frame, 'should return the on-stack frame, not the popped-but-captured one')

	db:close()
end)

h.test('get_latest_frame — two processes with independent chains each find their own deepest', function()
	local db = cvm.open()
	local user = user_pk(db)

	local process_a = insert_process(db)
	local a_frame_0 = push_frame_0(db, process_a, user)
	local a_frame_1 = push_child_frame(db, a_frame_0, user)

	local process_b = insert_process(db)
	local b_frame_0 = push_frame_0(db, process_b, user)
	local b_frame_1 = push_child_frame(db, b_frame_0, user)
	local b_frame_2 = push_child_frame(db, b_frame_1, user)

	local a_frame_2 = push_child_frame(db, a_frame_1, user)

	local deepest_a = get_latest_frame(db, process_a)
	local deepest_b = get_latest_frame(db, process_b)

	h.assert_eq(deepest_a, a_frame_2, 'process A should resolve to its own deepest frame')
	h.assert_eq(deepest_b, b_frame_2, 'process B should resolve to its own deepest frame')
	h.assert_true(deepest_a ~= deepest_b, 'the two processes should return distinct frame pks')

	db:close()
end)
