--[[
{
	"module": "handlers.variable-scalar",
	"role": "Handler subclass for the CaspM assignment pattern that binds a scalar value to a bare local name — the `$x = 1` shape. Matches `row[1].in == 'as'`; unpacks the target name (row[2]) and the value atom (row[3]); does the write inline — savepoint, add_scalar, ensure_own_scope, upsert_ref, mark_frame_gc — against the CVM directly, using engine.current_frame_pk + engine.current_role_pk for the frame context. Declines any other row shape (returns false); raises on value-atom shapes not yet supported.",
	"exports": {
		"new":    "() -> VariableScalar",
		"handle": "(engine, row) -> true (recognized and executed) | false (not our shape)"
	},
	"depends_on": ["handler"],
	"status": "V0.1"
}
]]

--[[
# `handlers.variable-scalar`

Handler for the CaspM shape produced by `$x = 1` — a three-element row whose head atom is `{in='as'}`, followed by a bare variable name and a value atom.

**Match criteria:** `row[1]` is a table with `.in == 'as'`. Any other head shape returns false; the next handler in the chain gets a shot.

**On match, execute:**

1. Unpack the target name (`row[2]`) and value atom (`row[3]`).
2. Recognize the value atom. Currently only `{v = <literal>}` — one value-atom shape. Other shapes (refs, calls, hash/array literals) raise `variable_scalar_unsupported_value_atom` and land in later work.
3. Read the current frame from `engine.current_frame` (set by `engine:run_frame` before each dispatch).
4. Wrap the writes in `savepoint variable_scalar_assign;`. Inside: `data:add_scalar(value, owner_role)` → scalar_pk; `frame:ensure_own_scope()` → own-scope hash; `data:upsert_ref(own_scope.object_pk, name, scalar_pk)`; `data:mark_frame_gc(frame.object_pk)`. On error, rollback + release + re-raise. On success, release.

The savepoint keeps the four writes atomic — a failure partway through can't leave a scope hash with a dangling scalar or a frame that's been marked without a binding to justify it.

**Direct-to-CVM.** No wrapper method involved. `add_scalar` / `upsert_ref` / `mark_frame_gc` are CVM methods called through `engine.data`. `ensure_own_scope` is the one wrapper-shaped operation left — it walks/creates the frame's b/p/s ref chain and legitimately reads the frame wrapper's memoized `_own_scope` field, so it stays a frame method for now.

Returns `true` on successful execute. Any raise inside the savepoint block re-raises after rollback.
]]
local Handler = require('handler')


local VariableScalar = setmetatable({}, {__index = Handler})
VariableScalar.__index = VariableScalar


function VariableScalar.new()
	return setmetatable(Handler.new(), VariableScalar)
end


function VariableScalar:handle(engine, row)
	-- Match: row[1] must be a table with `in` == 'as'.
	if type(row[1]) ~= 'table' or row[1]['in'] ~= 'as' then
		return false
	end

	local name       = row[2]
	local value_atom = row[3]

	-- Value atom must be {v = <literal>} for now.
	if type(value_atom) ~= 'table' or value_atom.v == nil then
		error("variable_scalar_unsupported_value_atom: only {v = <literal>} value atoms are supported")
	end

	-- The current frame's pk + owner_role_pk are set by engine:run_frame
	-- before dispatch.
	local frame_pk = engine.current_frame_pk
	local role_pk  = engine.current_role_pk

	if not frame_pk then
		error("variable_scalar_no_current_frame: engine.current_frame_pk is unset — engine:run_frame must set it before dispatch")
	end

	local db   = engine.cvm
	local data = engine.data

	assert(db:exec('savepoint variable_scalar_assign;') == 0, db:errmsg())

	local ok, err = pcall(function()
		-- add_scalar dispatches on type(value) and routes to the right
		-- scalar_* column (scalar_string / scalar_number / scalar_bool /
		-- scalar_null).
		local scalar_pk = data:add_scalar(value_atom.v, role_pk)

		-- Get-or-create the frame's own scope hash (scopes[0] under
		-- the b/p/s + scopes convention). Returns the pk directly.
		local own_scope_pk = data:ensure_own_scope(frame_pk, role_pk)

		-- Bind (or rebind) the variable name to the scalar. On rebind
		-- the schema's after-update mark trigger inserts the old child
		-- into needs_trace so the walker's drain can sweep it.
		data:upsert_ref(own_scope_pk, name, scalar_pk)

		-- Mark the current frame as mid-dispatch. Set last so a
		-- resume-mid-savepoint can't observe frame_gc=1 without the
		-- writes it signals. The walker's next tick sees frame_gc=1 and
		-- runs its GC pass before advancing frame_stmt_idx.
		data:mark_frame_gc(frame_pk)
	end)

	if not ok then
		db:exec('rollback to savepoint variable_scalar_assign;')
		db:exec('release savepoint variable_scalar_assign;')
		error(err, 0)
	end

	assert(db:exec('release savepoint variable_scalar_assign;') == 0, db:errmsg())

	return true
end


return VariableScalar
