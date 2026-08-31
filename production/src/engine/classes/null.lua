--[[
{
	"module": "classes.null",
	"role": "Null primitive class. Every scalar_null-holding row IS a Null instance. All nulls are equal (there is conceptually one 'null value'), so `==` returns true for any two nulls regardless of pk. Stringifies to 'null'.",
	"exports": {
		"name":    "'Null' — the class name",
		"parent":  "the Object class descriptor — Null inherits from Object",
		"methods": "hash keyed by method name; values are Lua functions with signature (frame, self_pk, ...arg_pks) -> result_pk"
	},
	"depends_on": ["classes.object"],
	"status": "V0.1 — all-nulls-are-equal ==, mirror !=, to_s"
}
]]

--[[
# `classes.null`

Primitive class for Caspian null.

**Semantic.** Null is a distinct value (the `u` type in the scalars view — an explicit null, not "no scalar assigned"). All null instances represent the same value; two nulls compare equal regardless of pk.

**Method overrides:**

- `to_s` — always returns the string `"null"`.
- `==` — true if `other` is also a null, false otherwise.
- `!=` — mirror.
]]

local Object = require('classes.object')


local Null = {
	name    = 'Null',
	parent  = Object,
	methods = {},
}


--[[
## `Null:to_s` — always 'null'

No scalar read needed — the receiver's identity as a Null is enough.
Produces a fresh scalar_string carrying `"null"`.
]]
function Null.methods.to_s(frame, self_pk)
	return frame.engine.data:add_scalar('null', frame.owner_role)
end


--[[
## `Null:==` — true iff other is also a null

`self` is guaranteed a Null. Other is-a-null iff `get_scalar_null`
returns non-nil (the schema marks null scalars with scalar_null = 1;
non-null rows have scalar_null NULL).
]]
Null.methods['=='] = function(frame, self_pk, other_pk)
	local other_is_null = (frame.engine.data:get_scalar_null(other_pk) ~= nil)
	return frame.engine.data:add_scalar(other_is_null, frame.owner_role)
end


--[[
## `Null:!=` — negated

True iff other is NOT a null.
]]
Null.methods['!='] = function(frame, self_pk, other_pk)
	local other_is_null = (frame.engine.data:get_scalar_null(other_pk) ~= nil)
	return frame.engine.data:add_scalar(not other_is_null, frame.owner_role)
end


return Null
