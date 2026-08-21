--[[
{
	"module": "handlers.variable-scalar",
	"role": "Handler subclass for the CaspM assignment pattern that binds a scalar value to a bare local name — the `$x = 1` shape. Matches `row[1].in == 'as'`; unpacks the target name (row[2]) and the value atom (row[3]); calls `frame:set_local_to_scalar` on `engine.current_frame` to write the binding. Declines any other row shape (returns false); raises on value-atom shapes not yet supported.",
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
4. Call `frame:set_local_to_scalar(name, value)`. `frame:set_local_to_scalar` and `cvm:add_scalar` under it dispatch on the Lua type of the value — string / number / boolean / nil each route to the right scalar_* column. This handler doesn't need to know or say which scalar type it's storing.

Returns `true` on successful execute. Any raise from `set_local_to_scalar` propagates through dispatch to `run_row`.
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

	-- The current frame is set by engine:run_frame before dispatch.
	local frame = engine.current_frame

	if not frame then
		error("variable_scalar_no_current_frame: engine.current_frame is unset — engine:run_frame must set it before dispatch")
	end

	-- Pass the value verbatim. frame:set_local_to_scalar → cvm:add_scalar
	-- dispatches on type(value) and routes to the right scalar_* column.
	frame:set_local_to_scalar(name, value_atom.v)

	return true
end


return VariableScalar
