--[[
{
  "module": "helpers",
  "role": "Test helpers for the Fiona hsa test suite. Wires lsqlite3 (the Cache-tier binding that ships with Caspian) via the per-user luarocks install; exposes fresh_db() that loads ../lua/src/fiona.sql (schema sits next to fiona.lua) into a fresh in-memory database; provides assert helpers and a test-registration + reporting harness.",
  "exports": {
    "test":                    "name, fn -> nil (registers a test)",
    "reset":                   "() -> nil (clears results between files)",
    "results":                 "{passed, failed, failures} — mutated by test()",
    "fresh_db":                "() -> lsqlite3 db (in-memory, schema pre-loaded)",
    "assert_eq":               "actual, expected, msg? -> nil (raises on mismatch)",
    "assert_true":             "value, msg? -> nil",
    "assert_raises":           "fn, pattern?, label? -> nil (asserts fn() raised; pattern matched against error text via string.find)",
    "plan":                    "db, sql -> [detail_string] (EXPLAIN QUERY PLAN output)",
    "assert_uses_index":       "db, sql, label? -> nil (raises if any plan step is a full table scan)",
    "assert_ordered_via_index":"db, sql, label? -> nil (raises if ORDER BY needs a separate sort step)"
  }
}
]]

-- Wire the per-user luarocks install so lsqlite3 resolves. Matches
-- the same pattern used in unotate.lua for cjson.
local home = os.getenv("HOME") or "."
package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath
package.path  = home .. "/.luarocks/share/lua/5.4/?.lua;" .. package.path

local sqlite3 = require("lsqlite3")

local H = {}

-- Locate the schema relative to this file.
local script_dir = arg[0] and arg[0]:match("(.*/)") or "./"
local SCHEMA_PATH = script_dir .. "../../lua/src/fiona.sql"

local function read_file(path)
	local f, err = io.open(path, "r")

	if not f then
		error("cannot open schema: " .. path .. " — " .. tostring(err))
	end

	local content = f:read("*a")
	f:close()
	return content
end

--[[ {"in": {}, "out": "lsqlite3 db with fiona.sql applied"} ]]
function H.fresh_db()
	local db = sqlite3.open_memory()
	local sql = read_file(SCHEMA_PATH)
	local ok = db:exec(sql)

	if ok ~= sqlite3.OK then
		error("schema load failed: " .. db:errmsg())
	end

	return db
end

--[[ {"in": {"actual": "any", "expected": "any", "msg": "string?"}, "out": "nil"} ]]
function H.assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s",
			msg or "assert_eq", tostring(expected), tostring(actual)), 2)
	end
end

--[[ {"in": {"value": "any", "msg": "string?"}, "out": "nil"} ]]
function H.assert_true(value, msg)
	if not value then
		error((msg or "assert_true") .. ": expected truthy, got " .. tostring(value), 2)
	end
end

--[[ {"in": {"fn": "function", "pattern": "string?", "label": "string?"}, "out": "nil — raises if fn() didn't raise or if pattern didn't match"} ]]
function H.assert_raises(fn, pattern, label)
	local ok, err = pcall(fn)

	if ok then
		error((label or "assert_raises") .. ": expected raise, got success", 2)
	end

	if pattern and not tostring(err):find(pattern, 1, true) then
		error(string.format("%s: raised the wrong error. expected match /%s/, got: %s",
			label or "assert_raises", pattern, tostring(err)), 2)
	end
end

-- ------------------------------------------------------------
-- Query-plan introspection (EXPLAIN QUERY PLAN)
-- ------------------------------------------------------------

--[[ {"in": {"db": "lsqlite3 db", "sql": "string"}, "out": "array of plan-step detail strings"} ]]
function H.plan(db, sql)
	local out = {}

	for row in db:nrows("explain query plan " .. sql) do
		out[#out + 1] = row.detail
	end

	return out
end

--[[ {"in": {"db": "lsqlite3 db", "sql": "string", "label": "string?"}, "out": "nil — raises if any plan step scans a base table without using an index"} ]]
function H.assert_uses_index(db, sql, label)
	-- Flag only SCAN steps against our actual base tables that don't use
	-- an index. Benign SCAN forms — SCAN CONSTANT ROW (CTE base case),
	-- SCAN SUBQUERY, SCAN <cte_name> — are not real table scans and pass
	-- through. Add table names here as the schema grows.
	local base_tables = {hsa = true, relationships = true}

	for _, detail in ipairs(H.plan(db, sql)) do
		local scanned = detail:match("^SCAN (%w+)")

		if scanned and base_tables[scanned] and not detail:find("USING") then
			error(string.format("%s: plan step does a full table scan — %s",
				label or "assert_uses_index", detail), 2)
		end
	end
end

-- ------------------------------------------------------------
-- normalize_hashes helper — the mechanism the future Lua API method
-- normalize_hashes() will run. Two-phase: park all hash-parented rows into
-- the safe range, then renumber to dense 0..n-1 per parent via
-- UPDATE ... FROM (SQLite 3.33+). Arrays untouched.
-- ------------------------------------------------------------

--[[ {"in": {"db": "lsqlite3 db"}, "out": "nil — normalizes every hash-parented relationship's idx to dense 0..n-1 per parent"} ]]
function H.normalize_hashes(db)
	local ok1 = db:exec([[
		update relationships set idx = idx + 1000000000000000000
		where parent in (select hsa_pk from hsa where type = 'h')
	]])

	if ok1 ~= sqlite3.OK then
		error(db:errmsg())
	end

	local ok2 = db:exec([[
		update relationships set idx = ranked.new_idx
		from (
			select rel_pk,
			       row_number() over (partition by parent order by idx) - 1 as new_idx
			from relationships
			where idx >= 1000000000000000000
		) as ranked
		where relationships.rel_pk = ranked.rel_pk
			and relationships.idx >= 1000000000000000000
	]])

	if ok2 ~= sqlite3.OK then
		error(db:errmsg())
	end
end

--[[ {"in": {"db": "lsqlite3 db", "sql": "string", "label": "string?"}, "out": "nil — raises if the plan includes a separate ORDER BY sort step"} ]]
function H.assert_ordered_via_index(db, sql, label)
	for _, detail in ipairs(H.plan(db, sql)) do
		if detail:find("USE TEMP B%-TREE FOR ORDER BY") then
			error(string.format("%s: ORDER BY requires a separate sort — %s",
				label or "assert_ordered_via_index", detail), 2)
		end
	end
end

-- ------------------------------------------------------------
-- Test registration + reporting
-- ------------------------------------------------------------

H.results = {passed = 0, failed = 0, failures = {}}

function H.reset()
	H.results.passed = 0
	H.results.failed = 0
	H.results.failures = {}
end

--[[ {"in": {"name": "string", "fn": "function"}, "out": "nil (updates H.results)"} ]]
function H.test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)

	if ok then
		H.results.passed = H.results.passed + 1
	else
		H.results.failed = H.results.failed + 1
		table.insert(H.results.failures, {name = name, err = err})
	end
end

return H
