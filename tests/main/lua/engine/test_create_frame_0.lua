--[[
{
	"spec": "test_create_frame_0",
	"role": "Tests for `cvm.create_frame_0`. Verifies the composed two-write routine (initialize_process + frame INSERT under one savepoint): returned pk is non-nil; side effects are correct (one processes row, one 'f' frame row); frame's columns are populated correctly; ast round-trips through cjson intact; multiple calls create distinct process+frame pairs; empty CaspM works; raises when caspm can't be JSON-encoded.",
	"status": "walking-skeleton"
}
]]

--[[
# `test_create_frame_0`

Behavioural tests for the `create_frame_0(db, engine) -> frame_pk` routine at [src/engine/cvm/create_frame_0.lua](https://puck.uno/src/engine/cvm/create_frame_0.lua). Composes `initialize_process` with the frame INSERT under a `SAVEPOINT create_frame_0` / `RELEASE SAVEPOINT create_frame_0` bracket with `pcall` + `ROLLBACK TO SAVEPOINT` on error.

Uses a bare Lua table `{caspm = ...}` as the mock engine — `create_frame_0` only reads `engine.caspm`, nothing else on the engine.
]]

local h              = require('helpers')
local cjson          = require('cjson')
local cvm            = require('cvm.open')
local create_frame_0 = require('cvm.create_frame_0')

local function fake_engine(caspm)
	return {caspm = caspm}
end

-- Plausible CaspM shape for tests. Avoids Lua reserved words as table
-- keys (CaspM uses `{in = "as"}` etc.; those'd need bracket-quoting in
-- Lua source).
local function sample_caspm()
	return {
		{{bwc = 'puts'}, {value = 'hello'}},
		{{bwc = 'puts'}, {value = 'world'}},
	}
end

-- Structural equality for Lua tables (recursive). Used to check the
-- ast round-trip.
local function deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= 'table' then return a == b end

	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end

	for k in pairs(b) do
		if a[k] == nil then return false end
	end

	return true
end

h.test('create_frame_0 returns a non-nil frame pk', function()
	local db = cvm.open()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))
	h.assert_true(frame_pk ~= nil, 'create_frame_0 returned nil')
	db:close()
end)

h.test('create_frame_0 creates exactly one processes row', function()
	local db = cvm.open()
	create_frame_0(db, fake_engine(sample_caspm()))

	local count

	for row in db:nrows('select count(*) as n from processes') do
		count = row.n
	end

	h.assert_eq(count, 1, 'expected one processes row after one call')
	db:close()
end)

h.test("create_frame_0 creates exactly one 'f' frame row", function()
	local db = cvm.open()
	create_frame_0(db, fake_engine(sample_caspm()))

	local count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f'") do
		count = row.n
	end

	h.assert_eq(count, 1, "expected one 'f' frame row after one call")
	db:close()
end)

h.test('create_frame_0 — frame binds to the just-created process via `process_pk` column', function()
	local db = cvm.open()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local process_pk_from_row

	for row in db:nrows('select process_pk from processes') do
		process_pk_from_row = row.process_pk
	end

	local frame_process

	for row in db:nrows(string.format(
		"select process_pk from objects where object_pk = '%s'",
		frame_pk
	)) do
		frame_process = row.process_pk
	end

	h.assert_eq(frame_process, process_pk_from_row, "frame's process column should point at the created process")
	db:close()
end)

h.test("create_frame_0 — frame's stmt_idx is 0", function()
	local db = cvm.open()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local stmt_idx

	for row in db:nrows(string.format(
		"select stmt_idx from objects where object_pk = '%s'",
		frame_pk
	)) do
		stmt_idx = row.stmt_idx
	end

	h.assert_eq(stmt_idx, 0, "frame's stmt_idx should be 0")
	db:close()
end)

h.test("create_frame_0 — frame's owner_role is the user seed", function()
	local db = cvm.open()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local user_pk

	for row in db:nrows("select object_pk from objects where core_role = 'u'") do
		user_pk = row.object_pk
	end

	local frame_owner

	for row in db:nrows(string.format(
		"select owner_role from objects where object_pk = '%s'",
		frame_pk
	)) do
		frame_owner = row.owner_role
	end

	h.assert_eq(frame_owner, user_pk, "frame's owner_role should point at the user seed")
	db:close()
end)

h.test("create_frame_0 — frame's ast round-trips through cjson intact", function()
	local db = cvm.open()
	local input = sample_caspm()
	local frame_pk = create_frame_0(db, fake_engine(input))

	local ast_json

	for row in db:nrows(string.format(
		"select ast from objects where object_pk = '%s'",
		frame_pk
	)) do
		ast_json = row.ast
	end

	h.assert_true(ast_json ~= nil, "frame's ast column should have data")

	local decoded = cjson.decode(ast_json)
	h.assert_eq(deep_equal(decoded, input), true, 'decoded ast should structurally equal the input CaspM')

	db:close()
end)

h.test('create_frame_0 — two calls create two distinct process+frame pairs', function()
	local db = cvm.open()
	local frame_pk_1 = create_frame_0(db, fake_engine(sample_caspm()))
	local frame_pk_2 = create_frame_0(db, fake_engine(sample_caspm()))

	local process_count

	for row in db:nrows('select count(*) as n from processes') do
		process_count = row.n
	end

	h.assert_eq(process_count, 2, 'expected two processes rows after two calls')

	local frame_count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f'") do
		frame_count = row.n
	end

	h.assert_eq(frame_count, 2, 'expected two frame rows after two calls')
	h.assert_true(frame_pk_1 ~= frame_pk_2, 'the two frame pks should differ')

	db:close()
end)

h.test('create_frame_0 — empty CaspM is a valid input', function()
	local db = cvm.open()
	local frame_pk = create_frame_0(db, fake_engine({}))

	h.assert_true(frame_pk ~= nil, 'empty CaspM should still return a frame pk')

	local ast_json

	for row in db:nrows(string.format(
		"select ast from objects where object_pk = '%s'",
		frame_pk
	)) do
		ast_json = row.ast
	end

	h.assert_true(ast_json ~= nil, 'ast column should be non-null even for empty CaspM')

	db:close()
end)

h.test("create_frame_0 raises when caspm can't be JSON-encoded", function()
	local db = cvm.open()
	local unencodable = function() end

	local ok = pcall(function()
		create_frame_0(db, fake_engine(unencodable))
	end)

	h.assert_eq(ok, false, 'expected create_frame_0 to raise on unencodable caspm')

	db:close()
end)
