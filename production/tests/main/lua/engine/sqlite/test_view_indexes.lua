--[[
{
	"spec": "test_view_indexes",
	"role": "Verifies the views defined in `src/engine/cvm/sqlite/schema.sql` use the intended indexes. Each case loads the schema into an in-memory SQLite, runs `EXPLAIN QUERY PLAN` against a target query, and asserts on the plan text — index-scan hits over full-table scans on the columns the schema declares indexes for.",
	"run": "lua5.4 tests/main/lua/engine/run.lua (from repo root)"
}
]]

--[[
# `test_view_indexes`

Guards the query-plan side of the CVM schema. Views over `objects`
/ `refs` that were designed to use an index (e.g. `refs(parent,
key)`) fall onto a full-table scan silently if the index is dropped
or renamed. These tests catch that regression by pattern-matching
against SQLite's `EXPLAIN QUERY PLAN` output — a fragile-looking
assertion that's genuinely load-bearing because there's no other
way to check.
]]

local sqlite             = require("lsqlite3")
local current_process_pk = require('cvm.sqlite.udfs.current_process_pk')

local SCHEMA_PATH    = "production/src/engine/cvm/sqlite/schema.sql"
local PREFLIGHT_PATH = "production/src/engine/cvm/sqlite/preflight.sql"

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
	current_process_pk.register(db, function() return nil end)
	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, "schema apply failed: " .. tostring(db:errmsg()))
	rcvr = db:exec(slurp(PREFLIGHT_PATH))
	assert(rc == sqlite.OK, "preflight apply failed: " .. tostring(db:errmsg()))
	return db
end

local function plan(db, sql)
	local rows = {}
	for row in db:nrows("explain query plan " .. sql) do
		table.insert(rows, row.detail)
	end
	return table.concat(rows, "\n")
end

local h = require('helpers')
local test = h.test

-- Local plan-shape asserts — specific to this file's EXPLAIN QUERY
-- PLAN output inspection; not general enough to promote to helpers.
local function assert_plan_contains(actual, expected, note)
	if actual:find(expected, 1, true) then return end
	error(
		(note or "plan mismatch") .. "\n"
			.. "expected substring: " .. expected .. "\n"
			.. "actual plan:\n" .. actual,
		2
	)
end

local function assert_plan_lacks(actual, forbidden, note)
	if not actual:find(forbidden, 1, true) then return end
	error(
		(note or "plan should not contain") .. "\n"
			.. "forbidden substring: " .. forbidden .. "\n"
			.. "actual plan:\n" .. actual,
		2
	)
end

-- =============================================================================
-- roles view
-- =============================================================================

test("roles: pk lookup uses the object_pk primary key index", function()
	local db = fresh_db()
	local p = plan(db, "select 1 from roles where object_pk = 'x'")
	-- SQLite names the implicit PK index `sqlite_autoindex_<table>_1`.
	assert_plan_contains(p, "USING INDEX sqlite_autoindex_objects_1")
	db:close()
end)

test("roles: pk lookup does not fall back to a full scan", function()
	local db = fresh_db()
	local p = plan(db, "select 1 from roles where object_pk = 'x'")
	assert_plan_lacks(p, "SCAN objects")
	db:close()
end)

test("roles: full listing uses the objects_roles partial index, no full scan", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from roles")
	-- Under the 'r'-as-primitive design, the roles view is
	-- `select object_pk from objects where control = 'r'` — a
	-- single-column filter that reads through the objects_roles
	-- partial index (WHERE control = 'r'). The plan reads
	-- "SCAN objects USING COVERING INDEX objects_roles" — that's
	-- a full scan OF THE INDEX (all indexed rows are wanted), not
	-- a table scan; the partial predicate keeps it bounded to the
	-- 'r'-primitive rows only.
	assert_plan_contains(p, "USING COVERING INDEX objects_roles",
		"roles view should use the objects_roles partial index")
	db:close()
end)

-- =============================================================================
-- uspace view
-- =============================================================================

test("uspace: pk lookup uses the PK index in each union branch", function()
	local db = fresh_db()
	local p = plan(db, "select 1 from uspace where object_pk = 'x'")
	-- Both branches of the union should hit the PK index.
	local _, hits = p:gsub("USING INDEX sqlite_autoindex_objects_1", "")
	assert(hits >= 2,
		"expected the PK index used in both union branches, got " .. hits
			.. " hits in plan:\n" .. p)
	db:close()
end)

test("uspace: full listing uses roles + persistent + frame_process_cap indexes, no full scan", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from uspace")
	assert_plan_contains(p, "USING COVERING INDEX objects_roles",
		"roles branch (feeding uspace) should use the objects_roles partial index")
	assert_plan_contains(p, "USING INDEX objects_persistent",
		"persistent branch should use the partial index")
	assert_plan_contains(p, "USING INDEX objects_process_cap",
		"cap-frame branch should use the objects_process_cap partial index")
	-- Every reference to `objects` in the plan should be qualified by
	-- an index name — never a bare table scan. A partial-index covering
	-- scan (SCAN objects USING COVERING INDEX ...) is fine.
	for line in p:gmatch("[^\n]+") do
		if line:match("SCAN objects") and not line:match("USING") then
			error("uspace plan contains a bare table scan on objects:\n  " .. line)
		end
	end
	db:close()
end)

-- =============================================================================
-- Underlying single-column filters that the views compose from
-- =============================================================================

test("`where role_parent is not null` uses the objects_parent_role partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where role_parent is not null")
	assert_plan_contains(p, "USING INDEX objects_parent_role")
	db:close()
end)

test("`where owner_role is not null` uses the objects_owner_role partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where owner_role is not null")
	assert_plan_contains(p, "USING INDEX objects_owner_role")
	db:close()
end)

test("`where persistent = 1` uses the objects_persistent partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where persistent = 1")
	assert_plan_contains(p, "USING INDEX objects_persistent")
	db:close()
end)

test("`where role_core = 'e'` uses the objects_core_role partial unique index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where role_core = 'e'")
	-- The role_core column's UNIQUE lives in the objects_core_role
	-- partial index (`where role_core is not null`).
	assert_plan_contains(p, "USING INDEX objects_core_role (role_core=?)")
	db:close()
end)

test("uspace's cap-frame branch uses the objects_process_cap partial index", function()
	local db = fresh_db()
	-- uspace's cap-frame branch is `where control = 'f' and frame_process_cap = 1`.
	-- Test that predicate directly against objects so the plan
	-- output surfaces the specific index; the same predicate inside
	-- the view flattens to it.
	local p = plan(db, "select object_pk from objects where control = 'f' and frame_process_cap = 1")
	assert_plan_contains(p, "USING INDEX objects_process_cap")
	db:close()
end)

-- =============================================================================
-- object_with_stack view + refs_key_p partial index
-- =============================================================================

test("object_with_stack: lookup by object_pk uses an index (not a scan)", function()
	local db = fresh_db()
	local p = plan(db, "select stack_pk from object_with_stack where object_pk = 'x'")
	-- The refs half of the view's inner join must be an index probe.
	-- Two indexes are candidates:
	--   - refs_key_p (partial index on parent where key='p') — added
	--     specifically to support this view
	--   - sqlite_autoindex_refs_1 (the auto-index for unique(parent,
	--     key)) — already there for the uniqueness constraint
	-- Either serves as O(log n). Assert only that SOME refs index is
	-- picked — if a future refactor breaks index eligibility, the plan
	-- degrades to `SCAN r` and this test catches it.
	assert_plan_contains(p, "SEARCH r USING INDEX",
		"refs lookup for object_with_stack should be an index probe (not a scan)")
	-- Objects half must also probe by pk, not scan.
	assert_plan_contains(p, "SEARCH o USING INDEX",
		"objects lookup for object_with_stack should be a pk probe (not a scan)")
	db:close()
end)

test("object_with_stack: excludes objects that don't have a stack", function()
	-- Seed an engine so we have a valid owner_role plus a couple of
	-- plain-'o' rows to work with, then bind a stack (via a refs row
	-- with key='p') to one but not the other.
	local engine = require('engine')
	local e = engine:new()

	-- Fetch the user role's pk for owner_role assignment.
	local user_pk
	for row in e.cvm:nrows("select object_pk from objects where role_core = 'u'") do
		user_pk = row.object_pk
	end

	-- Insert two hashless-'o' rows and one array (target for the p ref).
	local a_pk, b_pk, arr_pk
	for row in e.cvm:nrows(
		"insert into objects (base, owner_role) values ('o', '" .. user_pk .. "') returning object_pk") do
		a_pk = row.object_pk
	end
	for row in e.cvm:nrows(
		"insert into objects (base, owner_role) values ('o', '" .. user_pk .. "') returning object_pk") do
		b_pk = row.object_pk
	end
	for row in e.cvm:nrows(
		"insert into objects (base, owner_role) values ('a', '" .. user_pk .. "') returning object_pk") do
		arr_pk = row.object_pk
	end

	-- Give a_pk a stack; leave b_pk without one.
	e.cvm:exec("insert into refs (parent, child, key, idx) values ('"
		.. a_pk .. "', '" .. arr_pk .. "', 'p', 0)")

	-- object_with_stack should list a_pk (with stack_pk = arr_pk) but
	-- NOT b_pk.
	local seen = {}
	for row in e.cvm:nrows("select object_pk, stack_pk from object_with_stack") do
		seen[row.object_pk] = row.stack_pk
	end
	assert(seen[a_pk] == arr_pk, "a_pk should appear with stack_pk = arr_pk; got " .. tostring(seen[a_pk]))
	assert(seen[b_pk] == nil,    "b_pk should NOT appear (no stack)")
end)

test("object_with_stack: has-stack existence check is a single row lookup", function()
	local engine = require('engine')
	local e = engine:new()

	local user_pk
	for row in e.cvm:nrows("select object_pk from objects where role_core = 'u'") do
		user_pk = row.object_pk
	end

	local o_pk, arr_pk
	for row in e.cvm:nrows(
		"insert into objects (base, owner_role) values ('o', '" .. user_pk .. "') returning object_pk") do
		o_pk = row.object_pk
	end
	for row in e.cvm:nrows(
		"insert into objects (base, owner_role) values ('a', '" .. user_pk .. "') returning object_pk") do
		arr_pk = row.object_pk
	end

	-- Before binding a stack: has_stack query returns no row.
	local before_count = 0
	for _ in e.cvm:nrows("select 1 from object_with_stack where object_pk = '" .. o_pk .. "'") do
		before_count = before_count + 1
	end
	assert(before_count == 0, "before stack binding: no row in object_with_stack; got " .. before_count)

	-- Bind the stack.
	e.cvm:exec("insert into refs (parent, child, key, idx) values ('"
		.. o_pk .. "', '" .. arr_pk .. "', 'p', 0)")

	-- After: exactly one row.
	local after_count = 0
	for _ in e.cvm:nrows("select 1 from object_with_stack where object_pk = '" .. o_pk .. "'") do
		after_count = after_count + 1
	end
	assert(after_count == 1, "after stack binding: exactly one row in object_with_stack; got " .. after_count)
end)
