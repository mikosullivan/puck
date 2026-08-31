--[[
{
	"module": "classes.boolean",
	"role": "Boolean primitive class. Every scalar_bool-holding row IS a Boolean instance. Overrides Object's identity-based `==` / `!=` with value equality. Stringifies to 'true' or 'false' via `to_s`.",
	"exports": {
		"name":    "'Boolean' — the class name",
		"parent":  "the Object class descriptor — Boolean inherits from Object",
		"methods": "hash keyed by method name; values are Lua functions with signature (frame, self_pk, ...arg_pks) -> result_pk"
	},
	"depends_on": ["classes.object"],
	"status": "V0.1 — value-based ==, !=, to_s"
}
]]

--[[
# `classes.boolean`

Primitive class for Caspian booleans.

**Storage.** The `scalar_bool` column holds 1 for true, 0 for false (SQLite integers). The class treats 1 as truthy.

**Method overrides:**

- `to_s` — reads scalar_bool; returns `"true"` or `"false"` as a fresh scalar_string.
- `==` — value equality. If `other` isn't a bool, returns false.
- `!=` — mirror.
]]

local Object = require('classes.object')


local Boolean = {
	name    = 'Boolean',
	parent  = Object,
	methods = {},
}


--[[
## `Boolean:to_s` — render as 'true' or 'false'

Reads `scalar_bool` (1 for true, 0 for false) and produces the
corresponding string as a fresh scalar_string.
]]
function Boolean.methods.to_s(frame, self_pk)
	local val = frame.engine.data:get_scalar_bool(self_pk)
	local str = (val == 1) and 'true' or 'false'
	return frame.engine.data:add_scalar(str, frame.owner_role)
end


--[[
## `Boolean:==` — value equality against another boolean

`self` is guaranteed a Boolean (mc dispatched here). If `other` isn't
a bool, `get_scalar_bool(other_pk)` returns nil; the comparison
collapses to false.
]]
Boolean.methods['=='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_bool(self_pk)
	local other_val = data:get_scalar_bool(other_pk)
	return data:add_scalar(self_val == other_val, frame.owner_role)
end


--[[
## `Boolean:!=` — negated value equality
]]
Boolean.methods['!='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_bool(self_pk)
	local other_val = data:get_scalar_bool(other_pk)
	return data:add_scalar(self_val ~= other_val, frame.owner_role)
end


return Boolean
