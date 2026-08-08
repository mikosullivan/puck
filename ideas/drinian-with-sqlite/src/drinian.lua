--[[ {
	"vibecode": {
		"module": "drinian",
		"role": "Drinian entry point (ideas/-scoped prototype): opens a SQLite connection (in-memory or file), applies the schema from the sibling schema.md, enables FKs, and creates the per-connection current_process TEMP table. Lives under ideas/drinian-with-sqlite/ because the spec is still in ideas/, not requirements/ — per the spec-before-implementation rule.",
		"status": "walking-skeleton — open + apply schema + verify seed",
		"exports": ["open", "load_schema_from_md"],
		"depends_on": ["lsqlite3"]
	}
} ]]

local sqlite = require('lsqlite3')

local M = {}

-- Default path to the schema.md file. drinian.lua lives at
-- ideas/drinian-with-sqlite/src/drinian.lua; schema.md is the
-- sibling one directory up.
local function default_schema_md_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. '../schema.md'
end

--[[ {"in": "path to a schema.md file", "out": "the SQL text extracted from the first ~~~sql fenced block", "note": "single-source-of-truth: the .md is authoritative; we extract at runtime rather than duplicating into a .sql file"} ]]
function M.load_schema_from_md(path)
	path = path or default_schema_md_path()

	local file, err = io.open(path, 'r')

	if not file then
		error('drinian_schema_read_failed: could not open ' .. tostring(path) .. ': ' .. tostring(err))
	end

	local text = file:read('*a')
	file:close()

	-- Find the first ~~~sql ... ~~~ block. The schema is a single
	-- contiguous fenced block; if that ever changes we'll need to
	-- concatenate all sql blocks in order.
	local sql = text:match('~~~sql\n(.-)\n~~~')

	if not sql then
		error('drinian_schema_block_missing: no ~~~sql fenced block found in ' .. tostring(path))
	end

	return sql
end

--[[ {"in": "optional opts table {path = <db path or ':memory:'>, schema = <sql text override>, schema_md_path = <path to schema.md>}", "out": "an lsqlite3 db handle with schema applied, foreign keys on, and current_process temp table created", "note": "one connection = one process context — the current_process TEMP table dies with the connection"} ]]
function M.open(opts)
	opts = opts or {}

	local path = opts.path or ':memory:'
	local schema = opts.schema or M.load_schema_from_md(opts.schema_md_path)

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
