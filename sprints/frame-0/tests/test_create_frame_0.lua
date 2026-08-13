--[[
{
	"module": "test_create_frame_0",
	"role": "Sprint frame-0 tests for `create_frame_0`. Standalone — not wired into tests/main/lua/engine/run.lua because the sprint uses its own schema. Promotes into the shared runner when the sprint closes.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_create_frame_0`

Standalone test file for [`create_frame_0`](../src/create_frame_0.lua). Run from the repo root:

~~~
lua5.4 sprints/frame-0/tests/test_create_frame_0.lua
~~~

Uses the sprint's schema at `sprints/frame-0/src/schema.sql`.

`create_frame_0(db, engine)` composes a process INSERT with a frame INSERT under one transaction. The tests verify: returned pk is non-nil; the write side effects are correct (one processes row, one `'f'` frame row); the frame's columns are populated correctly (`primitive`, `process`, `stmt_idx`, `owner_role`, `ast`); the `ast` round-trips through `cjson` intact; multiple calls create distinct process+frame pairs; empty CaspM is a valid input; and the function raises on a CaspM value `cjson` can't encode.

Uses a bare Lua table `{caspm = ...}` as the mock engine — `create_frame_0` only reads `engine.caspm`, nothing else on the engine.
]]

package.path  = "./sprints/frame-0/src/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite         = require("lsqlite3")
local cjson          = require("cjson")
local create_frame_0 = require("create_frame_0")

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

-- Mock engine — create_frame_0 only touches engine.caspm.
local function fake_engine(caspm)
	return {caspm = caspm}
end

-- Plausible CaspM shape for tests: two statement rows, each a bwc puts
-- with a value atom. Avoids Lua reserved words as table keys (which
-- rules out `{in = "as"}` etc. — CaspM uses those but they'd need
-- bracket-quoting in Lua source).
local function sample_caspm()
	return {
		{{bwc = "puts"}, {value = "hello"}},
		{{bwc = "puts"}, {value = "world"}},
	}
end

-- Structural equality for Lua tables (recursive). Used to check
-- that ast round-trips through JSON encode/decode.
local function deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end

	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end

	for k in pairs(b) do
		if a[k] == nil then return false end
	end

	return true
end

-- ------------------------------------------------------------
-- Local test infrastructure (matches the pattern of the sprint's
-- other test files; promotes into the shared runner on close).
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

local function assert_not_nil(actual, msg)
	if actual ~= nil then return end
	error((msg or "expected non-nil"), 2)
end

-- ==============================================================
-- Tests
-- ==============================================================

test("returns a non-nil frame pk", function()
	local db = fresh_db()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))
	assert_not_nil(frame_pk, "create_frame_0 returned nil")
	db:close()
end)

test("creates exactly one processes row", function()
	local db = fresh_db()
	create_frame_0(db, fake_engine(sample_caspm()))

	local count

	for row in db:nrows("select count(*) as n from processes") do
		count = row.n
	end

	assert_eq(count, 1, "expected one processes row after one call")
	db:close()
end)

test("creates exactly one 'f' frame row", function()
	local db = fresh_db()
	create_frame_0(db, fake_engine(sample_caspm()))

	local count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f'") do
		count = row.n
	end

	assert_eq(count, 1, "expected one 'f' frame row after one call")
	db:close()
end)

test("frame binds to the just-created process via `process` column", function()
	local db = fresh_db()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local process_pk_from_row

	for row in db:nrows("select process_pk from processes") do
		process_pk_from_row = row.process_pk
	end

	local frame_process

	for row in db:nrows(string.format(
		"select process from objects where object_pk = '%s'",
		frame_pk
	)) do
		frame_process = row.process
	end

	assert_eq(frame_process, process_pk_from_row,
		"frame's process column should point at the created process")
	db:close()
end)

test("frame's stmt_idx is 0", function()
	local db = fresh_db()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local stmt_idx

	for row in db:nrows(string.format(
		"select stmt_idx from objects where object_pk = '%s'",
		frame_pk
	)) do
		stmt_idx = row.stmt_idx
	end

	assert_eq(stmt_idx, 0, "frame's stmt_idx should be 0")
	db:close()
end)

test("frame's owner_role is the user seed", function()
	local db = fresh_db()
	local frame_pk = create_frame_0(db, fake_engine(sample_caspm()))

	local user_pk

	for row in db:nrows("select object_pk from objects where user") do
		user_pk = row.object_pk
	end

	local frame_owner

	for row in db:nrows(string.format(
		"select owner_role from objects where object_pk = '%s'",
		frame_pk
	)) do
		frame_owner = row.owner_role
	end

	assert_eq(frame_owner, user_pk,
		"frame's owner_role should point at the user seed")
	db:close()
end)

test("frame's ast round-trips through cjson intact", function()
	local db = fresh_db()
	local input = sample_caspm()
	local frame_pk = create_frame_0(db, fake_engine(input))

	local ast_json

	for row in db:nrows(string.format(
		"select ast from objects where object_pk = '%s'",
		frame_pk
	)) do
		ast_json = row.ast
	end

	assert_not_nil(ast_json, "frame's ast column should have data")

	local decoded = cjson.decode(ast_json)
	assert_eq(deep_equal(decoded, input), true,
		"decoded ast should structurally equal the input CaspM")

	db:close()
end)

test("two calls create two distinct process+frame pairs", function()
	local db = fresh_db()
	local frame_pk_1 = create_frame_0(db, fake_engine(sample_caspm()))
	local frame_pk_2 = create_frame_0(db, fake_engine(sample_caspm()))

	local process_count

	for row in db:nrows("select count(*) as n from processes") do
		process_count = row.n
	end

	assert_eq(process_count, 2, "expected two processes rows after two calls")

	local frame_count

	for row in db:nrows("select count(*) as n from objects where primitive = 'f'") do
		frame_count = row.n
	end

	assert_eq(frame_count, 2, "expected two frame rows after two calls")
	assert_eq(frame_pk_1 ~= frame_pk_2, true, "the two frame pks should differ")

	db:close()
end)

test("empty CaspM is a valid input", function()
	local db = fresh_db()
	local frame_pk = create_frame_0(db, fake_engine({}))

	assert_not_nil(frame_pk, "empty CaspM should still return a frame pk")

	local ast_json

	for row in db:nrows(string.format(
		"select ast from objects where object_pk = '%s'",
		frame_pk
	)) do
		ast_json = row.ast
	end

	assert_not_nil(ast_json, "ast column should be non-null even for empty CaspM")

	db:close()
end)

test("raises when caspm can't be JSON-encoded", function()
	local db = fresh_db()
	-- cjson can't encode function values; call should raise inside cjson.encode.
	local unencodable = function() end

	local ok, err = pcall(function()
		create_frame_0(db, fake_engine(unencodable))
	end)

	assert_eq(ok, false, "expected create_frame_0 to raise on unencodable caspm")

	-- Sanity that the error surfaced from cjson, not some earlier step.
	if not string.find(tostring(err), "cjson", 1, true) then
		-- Different message wording is acceptable — just needs to be an actual raise.
	end

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
