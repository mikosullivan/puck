--[[ {
	"vibecode": {
		"module": "drinian",
		"role": "Drinian entry point (ideas/-scoped prototype): opens a SQLite connection (in-memory or file), applies the schema from the sibling drinian.sql file, enables FKs, and creates the per-connection current_process TEMP table. Lives under ideas/drinian-with-sqlite/ because the spec is still in ideas/, not requirements/ — per the spec-before-implementation rule.",
		"status": "walking-skeleton — open + apply schema + verify seed",
		"exports": ["open", "load_schema"],
		"depends_on": ["lsqlite3"]
	}
} ]]

local sqlite = require('lsqlite3')

local M = {}

-- Default path to the schema. drinian.lua and drinian.sql are siblings
-- under ideas/drinian-with-sqlite/src/. The .sql file is authoritative;
-- ideas/drinian-with-sqlite/sql.md pulls it in for display via Orlando's
-- file: directive.
local function default_schema_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. 'drinian.sql'
end

--[[ {"in": "path to a .sql file", "out": "the SQL text", "note": "single-source-of-truth: the .sql file is authoritative"} ]]
function M.load_schema(path)
	path = path or default_schema_path()

	local file, err = io.open(path, 'r')

	if not file then
		error('drinian_schema_read_failed: could not open ' .. tostring(path) .. ': ' .. tostring(err))
	end

	local text = file:read('*a')
	file:close()

	return text
end

--[[ {"in": "optional opts table {path = <db path or ':memory:'>, schema = <sql text override>, schema_path = <path to drinian.sql>}", "out": "an lsqlite3 db handle with schema applied, foreign keys on, and current_process temp table created", "note": "one connection = one process context — the current_process TEMP table dies with the connection"} ]]
function M.open(opts)
	opts = opts or {}

	local path = opts.path or ':memory:'
	local schema = opts.schema or M.load_schema(opts.schema_path)

	local db, err_code, err_msg = sqlite.open(path)

	if not db then
		error('drinian_open_failed: sqlite.open(' .. tostring(path) .. ') returned code ' .. tostring(err_code) .. ': ' .. tostring(err_msg))
	end

	-- Foreign keys are OFF by default in SQLite; enable per-connection.
	local ok = db:exec('pragma foreign_keys = on;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('drinian_pragma_fk_failed: ' .. tostring(msg))
	end

	-- Apply the main schema. This is the DDL from schema.md.
	ok = db:exec(schema)

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('drinian_schema_apply_failed: ' .. tostring(msg))
	end

	-- Per-connection state. TEMP table: dies with this connection.
	-- Documented in schema.md but not in the main DDL because temp
	-- tables can't be defined by the once-per-DB main schema.
	ok = db:exec([[
		create temp table current_process (
			key text primary key,
			value
		);
	]])

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('drinian_temp_table_failed: ' .. tostring(msg))
	end

	return db
end

return M
