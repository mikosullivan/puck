--[[ {
	"vibecode": {
		"module": "cvm",
		"role": "CVM engine entry point: opens a SQLite connection (in-memory or file), enables FKs and recursive triggers, installs the CVM infrastructure from the sibling schema.sql file if this is a fresh DB (skips the install if the mvm marker table is already present so revive-open on a persisted file is idempotent), and inserts a fresh processes row. Returns the db handle and the new process pk; callers hold the pk in Lua-side state and bind it into queries at the call site.",
		"status": "walking-skeleton — open + gated install + process record",
		"exports": ["open", "load_schema"],
		"depends_on": ["lsqlite3"]
	}
} ]]

local sqlite = require('lsqlite3')

local M = {}

-- Default path to the schema. open.lua and schema.sql are siblings
-- under src/engine/cvm/. The .sql file is authoritative; the display
-- page at requirements/cvm/sql.md pulls it in for rendering via
-- Orlando's file: directive.
local function default_schema_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. 'schema.sql'
end

--[[ {"in": "path to a .sql file", "out": "the SQL text", "note": "single-source-of-truth: the .sql file is authoritative"} ]]
function M.load_schema(path)
	path = path or default_schema_path()

	local file, err = io.open(path, 'r')

	if not file then
		error('cvm_schema_read_failed: could not open ' .. tostring(path) .. ': ' .. tostring(err))
	end

	local text = file:read('*a')
	file:close()

	return text
end

--[[ {"in": "optional opts table {path = <db path or ':memory:'>, schema = <sql text override>, schema_path = <path to schema.sql>}", "out": "two values: an lsqlite3 db handle with schema applied and pragmas set, and the fresh process pk from the processes row this open inserted", "note": "one connection = one process context — the caller is expected to hold the returned pk in Lua-side state and bind it into queries at the call site"} ]]
function M.open(opts)
	opts = opts or {}

	local path = opts.path or ':memory:'
	local schema = opts.schema or M.load_schema(opts.schema_path)

	local db, err_code, err_msg = sqlite.open(path)

	if not db then
		error('cvm_open_failed: sqlite.open(' .. tostring(path) .. ') returned code ' .. tostring(err_code) .. ': ' .. tostring(err_msg))
	end

	-- Foreign keys are OFF by default in SQLite; enable per-connection.
	local ok = db:exec('pragma foreign_keys = on;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('cvm_pragma_fk_failed: ' .. tostring(msg))
	end

	-- Recursive triggers are OFF by default in SQLite; enable per-connection.
	-- The schema's opening comment declares them ON as a design principle
	-- (see schema.sql), so every connection has to set it to match.
	ok = db:exec('pragma recursive_triggers = on;')

	if ok ~= sqlite.OK then
		local msg = db:errmsg()
		db:close()
		error('cvm_pragma_recursive_triggers_failed: ' .. tostring(msg))
	end

	-- Install-infrastructure gate: presence of the mvm marker table
	-- is the "already installed" flag. No mvm table means this is a
	-- fresh DB and the DDL from schema.sql needs to run; mvm table
	-- present means the DB is a revive of an already-installed file and
	-- re-running the install would fail on "table objects already exists."
	-- Same code path for fresh and revive; the check is what makes open
	-- idempotent.
	local mvm_installed = false

	for _ in db:nrows("select name from sqlite_master where type = 'table' and name = 'mvm'") do
		mvm_installed = true
	end

	if not mvm_installed then
		-- Apply the main schema. This is the DDL from schema.sql: creates
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

	return db, process_pk
end

return M
