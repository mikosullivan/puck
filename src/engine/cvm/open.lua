--[[
{
	"module": "cvm.open",
	"role": "CVM connection entry point: opens a SQLite connection (in-memory or file), enables `foreign_keys` and `recursive_triggers` pragmas per the CVM's per-connection rules, and installs the CVM infrastructure from the sibling `schema.sql` file if this is a fresh DB (skips the install if the `cvm` marker table is already present so revive-open on a persisted file is idempotent). Returns just the db handle. Process rows are created per-run by `create_frame_0` (fresh case) or handed in by the caller (revival case) — no auto-creation at open time.",
	"exports": {
		"open":        "(opts?) -> db — opts.path (default ':memory:'), opts.schema (SQL text override), opts.schema_path (path to schema.sql)",
		"load_schema": "(path?) -> SQL text — path defaults to the sibling schema.sql"
	},
	"status": "walking-skeleton — open + gated install",
	"depends_on": ["lsqlite3"]
}
]]

--[[
# `cvm.open`

Entry point for opening a CVM-shaped SQLite connection. Every
caller that wants to talk to a CVM starts here — the higher-level
`engine.lua` calls `cvm.open()` as its first act during
construction, and tests that need a raw handle can call it directly
with `path = ':memory:'` for an in-memory DB.

**Idempotent install.** `open` uses the `cvm` marker table's
presence as the "already installed" flag. On a fresh DB the marker
is missing, so the full DDL from `schema.sql` runs. On a revive of a
persisted file the marker is there and the DDL is skipped — same
code path, no duplicate-object errors.

**Per-connection pragmas.** `foreign_keys` and `recursive_triggers`
are OFF by default in SQLite and reset per connection. `open` sets
both before returning; a caller that opens the DB by other means
needs to set them itself.

**No process auto-creation.** `open` returns just the db handle. Under
frames-as-objects, process rows are created per-run by `create_frame_0`
(fresh case) or handed in by the caller (revival case) — not at open
time. Auto-creating a process here would allocate one nobody asked
for and force one-process-per-open assumptions on the caller.
]]

local sqlite = require('lsqlite3')

local M = {}

--[[
## `default_schema_path` — locate the sibling `schema.sql`

Uses `debug.getinfo` to find this file's own on-disk path, then
returns the sibling `schema.sql` under the same directory. Falls
back to `./schema.sql` if `debug.getinfo` can't produce a path.

Called by `M.load_schema` when the caller doesn't supply an explicit
`path`. Locating the schema relative to the module file rather than
the current working directory means tests, tools, and the CLI all
find the same file regardless of `pwd`.
]]
local function default_schema_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. 'schema.sql'
end

--[[
## `M.load_schema` — read the schema SQL text

Reads the CVM schema from disk and returns it as a string. Default
path is the sibling `schema.sql`; callers can override by passing an
explicit `path` (tests occasionally point at a stripped-down schema
to isolate one table's behaviour).

Raises `cvm_schema_read_failed` with the underlying `io.open` error
message when the file can't be opened.

Kept as a public export so a caller who wants the SQL text without
opening a connection (e.g. an audit tool that greps the schema) can
reach it without duplicating the path-resolution.
]]
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

--[[
## `M.open` — open a CVM-shaped SQLite connection

Opens a SQLite connection (in-memory by default, file-backed if
`opts.path` is set), enables the `foreign_keys` and
`recursive_triggers` pragmas, and installs the CVM DDL from
`schema.sql` if the `cvm` marker table isn't already present. Returns
the lsqlite3 db handle.

**Options** (all optional):

- `path` — the SQLite path; defaults to `':memory:'` for a fresh
  in-memory DB.
- `schema` — SQL text to use in place of the on-disk schema; skips
  the `load_schema` call.
- `schema_path` — path to a schema file to load; overrides the
  default sibling `schema.sql`.

**Error surface.** Every failure raises with an underscore-prefixed
error id so `grep` finds the site: `cvm_open_failed` (sqlite.open
failed), `cvm_pragma_fk_failed` / `cvm_pragma_recursive_triggers_failed`
(pragma set failed), `cvm_schema_apply_failed` (DDL apply failed on a
fresh DB). The db handle is closed on every raise path so an error
doesn't leak a half-open connection.

**No process auto-creation.** Process rows are created per-run by
`create_frame_0` (fresh case) or handed in by the caller (revival
case) — not at open time.
]]
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

	-- Install-infrastructure gate: presence of the cvm marker table
	-- is the "already installed" flag. No cvm table means this is a
	-- fresh DB and the DDL from schema.sql needs to run; cvm table
	-- present means the DB is a revive of an already-installed file and
	-- re-running the install would fail on "table objects already exists."
	-- Same code path for fresh and revive; the check is what makes open
	-- idempotent.
	local cvm_installed = false

	for _ in db:nrows("select name from sqlite_master where type = 'table' and name = 'cvm'") do
		cvm_installed = true
	end

	if not cvm_installed then
		-- Apply the main schema. This is the DDL from schema.sql: creates
		-- every table / trigger / index / view, seeds the user row, inserts
		-- the cvm marker row.
		ok = db:exec(schema)

		if ok ~= sqlite.OK then
			local msg = db:errmsg()
			db:close()
			error('cvm_schema_apply_failed: ' .. tostring(msg))
		end
	end

	-- Process rows are NOT created here. Under frames-as-objects, each
	-- run either creates its process via `create_frame_0` (fresh case)
	-- or is handed a process pk by its caller (revival case). Auto-
	-- creating a process at open time would allocate one nobody asked
	-- for and force one-process-per-open assumptions on the caller.
	return db
end

return M
