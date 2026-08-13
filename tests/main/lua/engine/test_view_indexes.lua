-- Verify the views defined in src/engine/cvm/schema.sql use the
-- intended indexes.
--
-- Run via the shared runner:
--     lua5.4 tests/main/lua/engine/run.lua
--
-- Each test loads the schema into an in-memory SQLite, runs
-- EXPLAIN QUERY PLAN on a target query, and checks the plan text
-- for the expected access strategy.

local sqlite = require("lsqlite3")

local SCHEMA_PATH = "src/engine/cvm/schema.sql"

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

test("roles: full listing uses the user + role_parent indexes, no full scan", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from roles")
	-- The user-branch of the UNION should hit the UNIQUE-on-user autoindex,
	-- and the role_parent branch should hit the partial index. Neither
	-- should scan.
	assert_plan_contains(p, "USING INDEX objects_user (user=?)",
		"user branch should use the objects_user partial unique index")
	assert_plan_contains(p, "USING INDEX objects_role_parent",
		"role_parent branch should use the partial index")
	assert_plan_lacks(p, "SCAN objects",
		"neither union branch should full-scan objects")
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

test("uspace: full listing uses user + role_parent + persistent indexes, no full scan", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from uspace")
	assert_plan_contains(p, "USING INDEX objects_user (user=?)",
		"user branch of roles → uspace should use the objects_user partial unique index")
	assert_plan_contains(p, "USING INDEX objects_role_parent",
		"role_parent branch should use the partial index")
	assert_plan_contains(p, "USING INDEX objects_persistent",
		"persistent branch should use the partial index")
	assert_plan_lacks(p, "SCAN objects",
		"no branch of uspace should full-scan objects")
	db:close()
end)

-- =============================================================================
-- Underlying single-column filters that the views compose from
-- =============================================================================

test("`where role_parent is not null` uses the objects_role_parent partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where role_parent is not null")
	assert_plan_contains(p, "USING INDEX objects_role_parent")
	db:close()
end)

test("`where owner_role is not null` uses the objects_owner_role partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where owner_role is not null")
	assert_plan_contains(p, "USING INDEX objects_owner_role")
	db:close()
end)

test("`where needs_trace = 1` uses the objects_needs_trace partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where needs_trace = 1")
	assert_plan_contains(p, "USING INDEX objects_needs_trace")
	db:close()
end)

test("`where in_trace is not null` uses the objects_in_trace partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where in_trace is not null")
	assert_plan_contains(p, "USING INDEX objects_in_trace")
	db:close()
end)

test("`where persistent = 1` uses the objects_persistent partial index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where persistent = 1")
	assert_plan_contains(p, "USING INDEX objects_persistent")
	db:close()
end)

test("`where user = 1` uses the objects_user partial unique index", function()
	local db = fresh_db()
	local p = plan(db, "select object_pk from objects where user = 1")
	-- The user column's UNIQUE lives in the objects_user partial
	-- index (`where user = 1`) — SQLite ALTER TABLE ADD COLUMN
	-- doesn't accept inline UNIQUE, so the constraint moves to
	-- an explicit index in the CVM section.
	assert_plan_contains(p, "USING INDEX objects_user (user=?)")
	db:close()
end)

test("uspace's frame-anchor branch uses the objects_frame_on_stack partial index", function()
	local db = fresh_db()
	-- uspace's third branch is `where primitive = 'f' and process is not null`.
	-- Test that predicate directly against objects so the plan
	-- output surfaces the specific index; the same predicate inside
	-- the view flattens to it.
	local p = plan(db, "select object_pk from objects where primitive = 'f' and process is not null")
	assert_plan_contains(p, "USING INDEX objects_frame_on_stack")
	db:close()
end)
