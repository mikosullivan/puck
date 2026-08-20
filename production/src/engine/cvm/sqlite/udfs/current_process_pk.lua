--[[
{
	"module": "current_process_pk",
	"role": "SQLite UDF: returns the object_pk of the current process cap, as tracked by the engine at runtime. Schema-side rules that need to scope operations by process (e.g., an INSERT into `needs_trace` that populates `process_pk`) call `current_process_pk()` in SQL and get the running cap's id back. Text (uuid) or nil if no process is currently active.",
	"exports": "register(db, get_current_pk_fn) — installs the UDF against a SQLite connection. `get_current_pk_fn` is a nullary callable invoked each time the UDF fires; return whatever the engine considers the current process cap's pk."
}
]]

--[[
# `current_process_pk`

SQLite UDF that exposes the engine's "current process cap" as a nullary
SQL function. The engine tracks which process it's currently dispatching
in Lua-side state; this UDF is the bridge that lets schema-level rules
read that state.

Registered per connection: pass in a getter closure that reads the
engine's state and returns the current cap's `object_pk` (or nil when
no process is active). The UDF re-invokes the getter on every call so
callers pick up whatever the engine's state currently says — no cache.
]]

local M = {}


--[[
Install the `current_process_pk` UDF on the given `db` connection.

- `db`: an open lsqlite3 connection.
- `get_current_pk`: a nullary Lua callable. Each SQL invocation of
  `current_process_pk()` calls it; the returned text (or nil) becomes
  the SQL value. Typically closes over engine state.

lsqlite3's `create_function` callback receives an sqlite context as
its first arg and expects the result to be set via `ctx:result_*()`
— a plain Lua `return` from the callback is NOT propagated.
]]
function M.register(db, get_current_pk)
	db:create_function('current_process_pk', 0, function(ctx)
		local pk = get_current_pk()

		if pk == nil then
			ctx:result_null()
		else
			ctx:result_text(pk)
		end
	end)
end


return M
