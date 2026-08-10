--[[
{
	"module": "state",
	"role": "Constructor for the MVM state hash — the single top-level table every field of Caspian's execution state lives inside. Builds an empty-but-shaped hash with all fields present at their empty representation, so downstream modules can populate slots without checking for existence. Roles are held as a Trivet tree (n-ary via trivet.lua); the shared ID counter is a Sequence object (sequence.lua); every other field starts as an empty hash / array. Bootstraps the roles tree with `engine` at the root and `user` as engine's child — the two roles V1 always starts with.",
	"exports": {
		"new": "() -> state hash"
	},
	"related_specs": "requirements/mvm/ for the state hash's purpose and V1.0 scope; requirements/mvm/objects for the objects hash's per-object shape; requirements/mvm/references for the reference / GC model; ideas/drinian-spec/ for design questions surfaced during implementation before promotion to requirements."
}
]]

--[[
# MVM state

Every field the Caspian runtime tracks lives inside the state hash this
module constructs. `state.new()` returns a fresh, empty-but-shaped hash;
`engine.new()` calls it once at construction and stashes the result on
the engine.

The interpreter reads and writes runtime state only through this hash's
interface. Working state — intermediate expression results, arguments
being marshaled, return values in flight — stays outside. See
[MVM § V1.0 scope](https://www.puck.uno/requirements/mvm/#v1-0-scope)
for the discipline this module enforces at the structural level.

V1.0 is in-memory only. No export API, no snapshot/revive, no HTTP
`promise()`. The shape is fixed with serialization in mind so those
capabilities can land as pure additions without a runtime overhaul.
]]

local trivet   = require('trivet')
local sequence = require('sequence')
local roles    = require('roles')

local M = {}

--[[
## State constructor

`state.new()` returns a fresh MVM state hash. Every top-level field is
present with its empty representation, so downstream code can insert / walk
/ read without existence checks. Bootstrap details:

- **`roles`** — a Trivet tree whose node values are [Role](../engine/roles.lua)
  instances. Bootstrapped with `engine` at the root and `user` as engine's
  only child (see [roles.lua](../engine/roles.lua) for what a Role is).
  Every additional role (loaded library, faucet, delegation target) becomes
  a child of whichever existing role loaded / spawned it. Trivet owns the
  tree mechanics — walking, adding children, ancestry checks; see
  [trivet.lua](../engine/trivet.lua) for the API.
- **`srcs`** — empty hash. `engine:load` inserts entries as source files
  and URL-loaded libraries are registered.
- **`objects`** — empty hash. Every live object's record lives here,
  keyed by object ID from the shared sequence counter. See
  [MVM § Objects](https://www.puck.uno/requirements/mvm/objects).
- **`references`** — empty hash. Every reference-class object's pointer
  lives here (bare `ref_id → target_id` pairs). GC traces from uspace
  roots through this hash. See
  [MVM § References](https://www.puck.uno/requirements/mvm/references).
- **`call_stack`** — empty array. `engine:run` pushes the root
  `top_level` frame here as the first act of execution. In-flight
  exceptions land as elements with `action: "exception"` alongside
  frames.
- **`gc_errors`** — empty array. Only grows if an `on_close` handler
  raises during collection.
- **`asts`** — empty hash. `engine:load` inserts the top-level
  program's CaspM tree here on first load; class-definition machinery
  inserts method bodies as they land. Each entry carries the CaspM tree
  plus the `src_key` for the file it came from, so value-birth `src`
  stamps stay cheap.
- **`sequence`** — a fresh [Sequence](../engine/sequence.lua) instance.
  Every allocation site (object, reference, hash-element, src key, ast
  key) draws an ID via `state.sequence:next()`. First call returns
  `"1"`; subsequent calls return `"2"`, `"3"`, and so on. Handles the
  string-integer increment internally so the counter grows past `2^53`
  without precision loss.
]]
function M.new()
	local role_tree = trivet.new(roles.new('engine'))
	role_tree:create_child(roles.new('user'))

	return {
		roles      = role_tree,
		srcs       = {},
		objects    = {},
		references = {},
		call_stack = {},
		gc_errors  = {},
		asts       = {},
		sequence   = sequence.new(),
	}
end

return M
