--[[ {
	"vibecode": {
		"module": "mvm",
		"role": "MVM engine entry point: opens a SQLite connection (in-memory or file), enables FKs, installs the MVM infrastructure from the sibling mvm.sql file if this is a fresh DB (skips the install if the mvm marker table is already present so revive-open on a persisted file is idempotent), inserts a fresh processes row and captures its pk, and creates the per-connection current_process TEMP table populated with that pk.",
		"status": "walking-skeleton — open + gated install + process record + populated current_process",
		"exports": ["open", "load_schema"],
		"depends_on": ["lsqlite3"]
	}
} ]]

local sqlite = require('lsqlite3')

local M = {}

-- Default path to the schema. mvm.lua and mvm.sql are siblings
-- under src/engine/. The .sql file is authoritative; the display page
-- at requirements/mvm/sql.md pulls it in for rendering via
-- Orlando's file: directive.
local function default_schema_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. 'mvm.sql'
end

--[[ {"in": "path to a .sql file", "out": "the SQL text", "note": "single-source-of-truth: the .sql file is authoritative"} ]]
function M.load_schema(path)
	path = path or default_schema_path()

	local file, err = io.open(path, 'r')

	if not file then
		error('mvm_schema_read_failed: could not open ' .. tostring(path) .. ': ' .. tostring(err))
	end

	local text = file:read('*a')
	file:close()

	return text
end

--[[ {"in": "optional opts table {path = <db path or ':memory:'>, schema = <sql text override>, schema_path = <path to mvm.sql>}", "out": "an lsqlite3 db handle with schema applied, foreign keys on, and current_process temp table created", "note": "one connection = one process context — the current_process TEMP table dies with the connection"} ]]
function M.open(opts)
	opts = opts or {}

	local path = opts.path or ':memory:'
	local schema = opts.schema or M.load_schema(opts.schema_path)

	local db, err_code, err_msg = sqlite.open(path)

	if not db then
		error('mvm_open_failed: sqlite.open(' .. tostring(path) .. ') returned code ' .. tostring(err_code) .. ': ' .. tostring(err_msg))
	end

	-- Foreign keys are OFF by default in SQLite; enable per-connection.
	local ok = db:exec('pragma foreign_keys = on;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('mvm_pragma_fk_failed: ' .. tostring(msg))
	end

	-- Recursive triggers are OFF by default in SQLite; enable per-connection.
	-- The schema's opening comment declares them ON as a design principle
	-- (see mvm.sql), so every connection has to set it to match.
	ok = db:exec('pragma recursive_triggers = on;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('mvm_pragma_recursive_triggers_failed: ' .. tostring(msg))
	end

	-- Install-infrastructure gate: presence of the mvm marker table
	-- is the "already installed" flag. No mvm table means this is a
	-- fresh DB and the DDL from mvm.sql needs to run; mvm table
	-- present means the DB is a revive of an already-installed file and
	-- re-running the install would fail on "table objects already exists."
	-- Same code path for fresh and revive; the check is what makes open
	-- idempotent.
	local mvm_installed = false

	for _ in db:nrows("select name from sqlite_master where type = 'table' and name = 'mvm'") do
		mvm_installed = true
	end

	if not mvm_installed then
		-- Apply the main schema. This is the DDL from mvm.sql: creates
		-- every table / trigger / index / view, seeds the user row, inserts
		-- the mvm marker row.
		ok = db:exec(schema)

		if ok ~= sqlite.OK then
			local msg = db:errmsg()
			db:close()
			error('mvm_schema_apply_failed: ' .. tostring(msg))
		end
	end

	-- Initialize the process record. Insert a fresh row into the
	-- persistent processes table and capture its autoincrement pk.
	-- Fresh insert only — a revive path that looks up an existing
	-- process pk instead of allocating a new one isn't yet spec'd.
	ok = db:exec('insert into processes default values;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('mvm_process_insert_failed: ' .. tostring(msg))
	end

	local process_pk = db:last_insert_rowid()

	-- Per-connection state. TEMP table: dies with this connection.
	-- Noted in the mvm.sql intro comments but not in the main
	-- DDL because temp tables can't be defined by the once-per-DB
	-- main schema. Populated with the process pk so the rest of the
	-- engine knows which process this connection is running.
	ok = db:exec(string.format([[
		create temp table current_process (
			key text primary key,
			value
		);

		insert into current_process (key, value)
			values ('current_process_pk', %d);
	]], process_pk))

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('mvm_temp_table_failed: ' .. tostring(msg))
	end

	return db
end

return M
