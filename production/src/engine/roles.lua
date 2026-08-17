--[[
{
	"module": "roles",
	"role": "Role class + creation for CVM. A Role is a small object with a name, held as a value on a node in state.roles' Trivet tree. Roles identify who owns currently-executing code; every frame on state.call_stack carries a role reference, and every entry in state.objects carries a role recording who owns it. `roles.new(name)` mints a fresh Role; state.new() calls it during bootstrap to seed the initial tree with engine + user.",
	"exports": {
		"new": "(name: string) -> Role"
	}
}
]]

--[[
# Roles

A Role is an identity that owns currently-executing code. V1 boots with
two — `engine` (the interpreter itself) and `user` (the program) — plus
one per engine-provided faucet, plus one per loaded remote library as
programs run. Each frame on `state.call_stack` carries a role; each
entry in `state.objects` carries a role recording who owns the value.

`roles.new(name)` creates a fresh Role. The Role instance is what sits
on each node of `state.roles`' Trivet tree — see
[state.lua](../engine/state.lua) for how the boot process wires the
initial tree (engine at the root, user as its child).

Role names are **opaque identifiers**. `"user"`, `"engine"`,
`"markdown.uno/render"` — the engine treats these as opaque strings
throughout, never parsing them or deriving meaning from their contents.
Readable names are a convention; two loaded libraries could in principle
use arbitrary-looking keys (`"r0"`, `"r1"`) and the runtime would work
identically.

Currently Roles are bare `{name = ...}` tables (with a metatable so
they're identifiable as Roles). Per-role metadata (trust webs,
capability grants, etc.) grows onto the Role table as those features
land.
]]

local M = {}

local Role = {}
Role.__index = Role

--[[
## The Role constructor

`roles.new(name)` creates a fresh Role with the given name. `name` is
an opaque string identifier — the engine treats role names as opaque
identifiers throughout.
]]
function M.new(name)
	return setmetatable({name = name}, Role)
end

return M
