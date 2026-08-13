--[[
{
	"module": "create_frame_0",
	"role": "Sprint frame-0 routine: creates frame 0 for a fresh process. Composes `initialize_process` (one INSERT into `processes`, returns the new pk) with the frame INSERT (one INSERT into `objects` — `primitive='f'`, the CaspM in `ast`, the new process pk in `process`). Both writes wrap in a single `begin;`/`commit;` so a crash between them can't leave a process row with no frame.",
	"exports": {
		"(function)": "(db, engine) -> frame_pk"
	},
	"depends_on": ["initialize_process", "cjson (or dkjson) for CaspM serialization"],
	"status": "sprint-scoped"
}
]]

--[[
# `create_frame_0`

Creates frame 0 for a fresh process — the case where no existing process was handed in and the engine has to invent one from scratch. Companion to [`get_latest_frame`](./get_latest_frame.lua), which handles the revival case.

Two writes, one transaction:

1. **Initialize the process** via [`initialize_process(db)`](./initialize_process.lua). Returns the new process pk.
2. **Insert frame 0** — one row into `objects` with `primitive = 'f'`, the CaspM value read from `engine.caspm` bound to `ast`, the process pk from step 1 bound to `process`, `stmt_idx = 0`, and the user role's pk in `owner_role`.

Both wrapped in `begin;`/`commit;`. A crash between them can't leave a process with no frame.

**Return value:** the new frame's `object_pk` — bootstrap's resume point.

**Preconditions:**

- `engine.caspm` is populated. Per shipping engine, `engine:run()`'s nil-check on `self.caspm` already vouches for this upstream; this routine trusts that guarantee and doesn't re-check.
]]
local cjson              = require("cjson")
local initialize_process = require("initialize_process")

local function create_frame_0(db, engine)
	-- Transpilation to be done here
	local caspm = engine.caspm

	db:exec("begin;")

	-- 1. Create the process row.
	local process_pk = initialize_process(db)

	-- 2. Look up the user role's pk — frame 0 runs as the user.
	local user_pk

	for row in db:nrows("select object_pk from objects where user") do
		user_pk = row.object_pk
	end

	-- 3. Insert frame 0.
	local stmt = db:prepare(
		"insert into objects (primitive, ast, process, stmt_idx, owner_role) " ..
		"values ('f', ?, ?, 0, ?) returning object_pk"
	)
	stmt:bind_values(cjson.encode(caspm), process_pk, user_pk)

	local frame_pk

	for row in stmt:nrows() do
		frame_pk = row.object_pk
	end

	stmt:reset()

	db:exec("commit;")

	return frame_pk
end

return create_frame_0
