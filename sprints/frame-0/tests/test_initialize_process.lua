--[[
{
	"module": "test_initialize_process",
	"role": "Sprint frame-0 tests for `initialize_process`. Standalone — not wired into tests/main/lua/engine/run.lua because the sprint uses its own schema. Promotes into the shared runner when the sprint closes.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_initialize_process`

Standalone test file for [`initialize_process`](../src/initialize_process.lua). Run from the repo root:

~~~
lua5.4 sprints/frame-0/tests/test_initialize_process.lua
~~~

Uses the sprint's schema at `sprints/frame-0/src/schema.sql` — with `processes.process_pk` as text UUID.

Five tests: returns a non-nil pk; creates exactly one `processes` row; the returned pk names that row; the returned pk is a UUID4-shaped text string; two calls create two distinct rows.
]]

package.path  = "./sprints/frame-0/src/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite              = require("lsqlite3")
local initialize_process  = require("initialize_process")

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

-- ------------------------------------------------------------
-- Local test infrastructure (matches the sprint pattern; promotes
-- into the shared runner when the sprint closes).
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

test("returns a non-nil process pk", function()
	local db = fresh_db()
	local pk = initialize_process(db)
	assert_not_nil(pk, "initialize_process returned nil")
	db:close()
end)

test("creates exactly one processes row", function()
	local db = fresh_db()
	initialize_process(db)

	local count

	for row in db:nrows("select count(*) as n from processes") do
		count = row.n
	end

	assert_eq(count, 1, "expected exactly one processes row after one call")
	db:close()
end)

test("the returned pk names the row just inserted", function()
	local db = fresh_db()
	local returned = initialize_process(db)

	local from_table

	for row in db:nrows("select process_pk from processes") do
		from_table = row.process_pk
	end

	assert_eq(returned, from_table, "returned pk should equal the row's process_pk")
	db:close()
end)

test("returned pk is a text UUID (36-char string)", function()
	local db = fresh_db()
	local pk = initialize_process(db)
	assert_eq(type(pk), "string", "process_pk should be text under the sprint schema")
	-- UUID4-shape: 8-4-4-4-12 hex with hyphens = 36 chars.
	assert_eq(#pk, 36, "process_pk should be a 36-char UUID string")
	db:close()
end)

test("two calls create two distinct processes rows with distinct pks", function()
	local db = fresh_db()
	local pk_1 = initialize_process(db)
	local pk_2 = initialize_process(db)

	local count

	for row in db:nrows("select count(*) as n from processes") do
		count = row.n
	end

	assert_eq(count, 2, "expected two processes rows after two calls")
	assert_eq(pk_1 ~= pk_2, true, "the two returned pks should differ")
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
