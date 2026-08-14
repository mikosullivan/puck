--[[
{
	"module": "handlers.variable-scalar",
	"role": "Stub Handler subclass for variable-scalar assignment (the `$x = 1` shape). Currently always returns true — placeholder while the actual matching + execution logic gets written. Registered as a stock handler in handlers/init.lua so engine.new() includes it in every fresh engine's row_handlers chain.",
	"exports": {
		"new":    "() -> VariableScalar",
		"handle": "(engine, row) -> true — always, for now"
	},
	"status": "stub — always returns true"
}
]]

--[[
# `handlers.variable-scalar`

Handler subclass for the CaspM assignment pattern that binds a scalar value to a bare local name — the `$x = 1` shape.

**Currently a stub.** `:handle` always returns true, regardless of what row it's given. That's a placeholder; the real matching logic (recognize `{"in": "as"}` row heads, unpack the target name and value atom, call the CVM primitives — `add_scalar` + `ensure_locals` + `add_ref` via `set_local_to_scalar`) lands in follow-on work.

**Side effect of always-true:** once registered as a stock handler, every dispatched row gets claimed by this handler — including rows it doesn't actually understand. That masks the `unrecognized_caspm` fallback for other shapes until this handler learns to be picky. Acceptable for the current sprint scope; the real matching logic comes with the actual assignment implementation.
]]
local Handler = require('handler')

local VariableScalar = setmetatable({}, {__index = Handler})
VariableScalar.__index = VariableScalar

--[[
## `VariableScalar.new` — construct

Standard subclass pattern: build a base Handler instance, re-wrap with the subclass metatable.
]]
function VariableScalar.new()
	return setmetatable(Handler.new(), VariableScalar)
end

--[[
## `VariableScalar:handle` — always returns true (stub)

Placeholder implementation. Will grow into a real match-and-execute when the assignment logic lands.
]]
function VariableScalar:handle(engine, row)
	return true
end

return VariableScalar
