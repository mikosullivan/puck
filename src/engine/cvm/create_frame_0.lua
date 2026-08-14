--[[
{
	"module": "cvm.create_frame_0",
	"role": "CVM routine: creates frame 0 for a fresh process. Composes `initialize_process` (one INSERT into `processes`, returns the new pk) with the frame INSERT (one INSERT into `objects` — `primitive='f'`, the CaspM in `ast`, the new process pk in `process_pk`). Both writes wrap in a single SAVEPOINT / RELEASE SAVEPOINT with pcall + ROLLBACK TO SAVEPOINT on error, so the routine composes cleanly whether or not the caller has an outer transaction open.",
	"exports": {
		"(function)": "(db, engine) -> frame_pk"
	},
	"depends_on": ["cjson", "cvm.initialize_process"],
	"status": "walking-skeleton"
}
]]

--[[
# `cvm.create_frame_0`

Creates frame 0 for a fresh process — the case where no existing process was handed in and the engine has to invent one from scratch. Companion to [`get_latest_frame`](./get_latest_frame.lua), which handles the revival case.

Two writes, one savepoint:

1. **Initialize the process** via [`initialize_process(db)`](./initialize_process.lua). Returns the new process pk.
2. **Insert frame 0** — one row into `objects` with `primitive = 'f'`, the CaspM value read from `engine.caspm` bound to `ast`, the process pk from step 1 bound to `process_pk`, `stmt_idx = 0`, and the user role's pk in `owner_role`.

Wrapped in `SAVEPOINT create_frame_0` / `RELEASE SAVEPOINT create_frame_0`, with a `pcall` around the body and `ROLLBACK TO SAVEPOINT create_frame_0` on error. Savepoints compose whether or not the caller already has an outer transaction open — this matters once V1 ships user-facing transactions, so `create_frame_0` doesn't accidentally commit a caller's outer transaction by using naked `BEGIN`/`COMMIT`.

**Return value:** the new frame's `object_pk` — bootstrap's resume point.

**Preconditions:**

- `engine.caspm` is populated. `engine:run()`'s nil-check on `self.caspm` vouches for this upstream; this routine trusts that guarantee and doesn't re-check.
]]
local cjson              = require("cjson")
local initialize_process = require("cvm.initialize_process")

local function create_frame_0(db, engine)
	-- Transpilation to be done here
	local caspm = engine.caspm

	db:exec("savepoint create_frame_0;")

	local ok, result = pcall(function()
		-- 1. Create the process row.
		local process_pk = initialize_process(db)

		-- 2. Look up the user role's pk — frame 0 runs as the user.
		local user_pk

		for row in db:nrows("select object_pk from objects where core_role = 'u'") do
			user_pk = row.object_pk
		end

		-- 3. Insert frame 0.
		local stmt = db:prepare(
			"insert into objects (primitive, ast, process_pk, stmt_idx, owner_role) " ..
			"values ('f', ?, ?, 0, ?) returning object_pk"
		)
		stmt:bind_values(cjson.encode(caspm), process_pk, user_pk)

		local frame_pk

		for row in stmt:nrows() do
			frame_pk = row.object_pk
		end

		stmt:reset()

		return frame_pk
	end)

	if not ok then
		db:exec("rollback to savepoint create_frame_0;")
		db:exec("release savepoint create_frame_0;")
		error(result)
	end

	db:exec("release savepoint create_frame_0;")

	return result
end

return create_frame_0
