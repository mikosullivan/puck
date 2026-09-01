--[[
{
	"module": "classes.string",
	"role": "String primitive class. Every scalar_string-holding row IS a String instance. Overrides Object's identity-based `==` / `!=` with value equality. `to_s` on a String is a no-op — it returns the receiver itself, since a String's string representation IS the string. `length` returns byte length (`#str`) as a scalar_number — codepoint-aware measurement comes later as a separate method.",
	"exports": {
		"name":    "'String' — the class name",
		"parent":  "the Object class descriptor — String inherits from Object",
		"methods": "hash keyed by method name; values are Lua functions with signature (frame, self_pk, ...arg_pks) -> result_pk"
	},
	"depends_on": ["classes.object"],
	"status": "V0.1 — value-based ==, !=, identity to_s"
}
]]

--[[
# `classes.string`

Primitive class for Caspian strings.

**Method overrides:**

- `to_s` — returns `self_pk` unchanged. A String's string representation is itself; no new scalar needed. Under a future scalar-interning pass this becomes identical to what a fresh add_scalar would produce anyway, but returning self skips even that lookup.
- `==` — value equality on the string payload. If `other` isn't a string, returns false.
- `!=` — mirror.
- `length` — byte length via `#str`. ASCII-safe (returns character count when the string is pure ASCII); for multibyte UTF-8 returns bytes, not codepoints. Codepoint measurement can arrive as a distinct method (`code_length` / `codepoints` / etc.) when UTF-8-aware string handling lands.
]]

local Object = require('classes.object')


local String = {
	name    = 'String',
	parent  = Object,
	methods = {},
}


--[[
## `String:to_s` — return self

The receiver IS its own string representation. Returning `self_pk`
skips the round-trip through `add_scalar`; the value the caller ends
up with is identical to `self`.
]]
function String.methods.to_s(frame, self_pk)
	return self_pk
end


--[[
## `String:==` — value equality against another string

`self` is guaranteed a String (mc dispatched here). If `other` isn't
a string, `get_scalar_string(other_pk)` returns nil; the comparison
collapses to false.
]]
String.methods['=='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_string(self_pk)
	local other_val = data:get_scalar_string(other_pk)
	return data:add_scalar(self_val == other_val, frame.owner_role)
end


--[[
## `String:!=` — negated value equality
]]
String.methods['!='] = function(frame, self_pk, other_pk)
	local data = frame.engine.data
	local self_val  = data:get_scalar_string(self_pk)
	local other_val = data:get_scalar_string(other_pk)
	return data:add_scalar(self_val ~= other_val, frame.owner_role)
end


--[[
## `String:length` — byte length of the string

Returns `#str` — Lua's `#` operator on the scalar_string payload,
which gives BYTE length, not codepoint count. For ASCII strings the
two agree (`'foo'` → 3). For strings with multibyte UTF-8 codepoints
they diverge (`'é'` → 2 bytes, 1 codepoint). Codepoint-based length
lands as a separate method (`code_length` or similar) once UTF-8-
aware string work is a real concern; `length` is the raw storage-
level measurement for now.

Result is a fresh scalar_number.
]]
function String.methods.length(frame, self_pk)
	local str = frame.engine.data:get_scalar_string(self_pk)
	return frame.engine.data:add_scalar(#str, frame.owner_role)
end


return String
