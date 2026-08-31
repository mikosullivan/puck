--[[
{
	"module": "classes.number",
	"role": "Number primitive class. Every scalar_number-holding row IS a Number instance; class-of is inferred from `scalar_number IS NOT NULL` (the row classifier). Overrides Object's identity-based `==` / `!=` with value equality — since add_scalar doesn't intern, two Number rows can hold the same value with different pks and would otherwise compare unequal. Overrides `to_s` to render the number as its shortest reasonable string form.",
	"exports": {
		"name":    "'Number' — the class name",
		"parent":  "the Object class descriptor — Number inherits from Object",
		"methods": "hash keyed by method name; values are Lua functions with signature (frame, self_pk, ...arg_pks) -> result_pk"
	},
	"depends_on": ["classes.object"],
	"status": "V0.1 — value-based ==, !=, to_s"
}
]]

--[[
# `classes.number`

Primitive class for Caspian numbers.

**How the class-of is decided.** A row is-a Number when its `scalar_number` column is populated (per the schema's at-most-one-scalar-column invariant). The row classifier — one column read on the `objects` row — is enough; no stack walk, no DB round-trip for a class lookup.

**Method overrides:**

- `to_s` — reads the numeric value and formats via `string.format('%g', v)` (shortest reasonable representation: integer-valued numbers render without a trailing `.0`; fractional numbers render with as few digits as round-trip needs).
- `==` — value equality. Reads scalar_number on both operands; if `other` isn't a number, returns false (mixed-type comparison always false at this class; a value-cross-type Number/String/Bool equality is Object's identity fallback via the class chain, and even then only true when they're the same row).
- `!=` — value inequality, mirrors `==`.

**Storage note.** The schema stores numbers with REAL affinity, so integer inputs come back as floats. `%g` formatting hides the storage detail from the string output.
]]

local Object = require('classes.object')


local Number = {
	name    = 'Number',
	parent  = Object,
	methods = {},
}


--[[
## `Number:to_s` — render as a decimal string

`%g` prints integer-valued numbers without a trailing `.0` (so `42.0`
comes out as `"42"`) and fractional numbers with the shortest round-trip
representation. Result is a fresh scalar_string.
]]
function Number.methods.to_s(frame, self_pk)
	local val = frame.engine.data:get_scalar_number(self_pk)
	return frame.engine.data:add_scalar(
		string.format('%g', val),
		frame.owner_role
	)
end


--[[
## `Number:==` — value equality against another number

`self` is guaranteed a Number (mc dispatched here). If `other` isn't a
number, `get_scalar_number(other_pk)` returns nil; `nil == val` is
false in Lua, so the comparison collapses to false without a separate
type check. Result is a fresh scalar_bool.
]]
Number.methods['=='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_number(self_pk)
	local other_val = data:get_scalar_number(other_pk)
	return data:add_scalar(self_val == other_val, frame.owner_role)
end


--[[
## `Number:!=` — negated value equality

Complement of `==`. Mixed-type comparisons return true here (a Number
and a non-Number are `!=`).
]]
Number.methods['!='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_number(self_pk)
	local other_val = data:get_scalar_number(other_pk)
	return data:add_scalar(self_val ~= other_val, frame.owner_role)
end


return Number
