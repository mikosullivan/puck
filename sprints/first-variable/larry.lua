--[[
{
	"module": "larry",
	"role": "Sprint-scoped Engine subclass for the first-variable sprint. Boots on the sprint's copy of `schema.sql` and intercepts `require('cvm.frame')` so it resolves to the sprint's copy of frame.lua (under `sprints/first-variable/cvm/`) rather than the shipping one. Overrides land in the sprint copies; when the design ships, they get promoted into shipping and this whole tree goes away.",
	"exports": {
		"new": "(opts?) -> Larry — same signature as Engine.new; auto-wires opts.cvm.schema_path to the sprint schema when omitted"
	},
	"depends_on": ["engine", "cvm.open"],
	"status": "sprint-scoped delegation subclass with intercepted frame.lua; scopes overrides pending"
}
]]

--[[
# `larry` (first-variable sprint)

A Larry is an Engine, plus whatever the sprint has fiddled with. Sprint copies of files that need modification live under `sprints/first-variable/cvm/`, and Larry prepends that directory to `package.path` at module-load time so `require('cvm.frame')` (and any other `cvm.<name>` we copy in) resolves to the sprint version first, falling through to shipping for anything not copied.

**Sprint focus: variable storage via `scopes`.** The current Engine (via shipping [frame.lua](../../src/engine/cvm/frame.lua)) puts a `locals` hash directly under the frame's bucket. This sprint replaces that with a `scopes` ArrayPrimitive: `bucket → scopes → [own_locals_hash, ...]`. First entry (`scopes[0]`) is the frame's own locals; further entries are captured scopes (from closures, once those land). See [closures.md](closures.md) for the design.

**Boots on the sprint schema.** `Larry.new()` defaults `opts.cvm.schema_path` to the sprint's `schema.sql` sibling, so a Larry runs against the invariants this sprint is exploring (drop-and-replace, one-child-per-parent, +1 stmt_idx, etc.). A caller who passes an explicit `opts.cvm` gets exactly what they specified — the auto-wiring only fills a gap, never overrides.
]]


-- Locate this file's directory so we can (a) find the sibling schema
-- and (b) prepend the sprint's require path.
local function this_dir()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	return this_file:match('(.*/)') or './'
end


-- Prepend the sprint's require path BEFORE loading Engine (or any of
-- the cvm.* modules). Once a module lands in `package.loaded` it's
-- cached; the ordering below guarantees the first resolution of
-- `require('cvm.frame')` — whoever triggers it — hits the sprint copy.
local _sprint_dir = this_dir()
package.path = _sprint_dir .. '?.lua;'
	.. _sprint_dir .. '?/init.lua;'
	.. package.path


local Engine = require('engine')
local cvm    = require('cvm.open')


local function sprint_schema_path()
	return this_dir() .. 'schema.sql'
end


local Larry = setmetatable({}, {__index = Engine})
Larry.__index = Larry


--[[
## `Larry.new` — construct a Larry instance

Delegates to `Engine.new(opts)` and rewraps the returned instance's metatable so the identity is Larry. When `opts.cvm` is omitted (or omits `schema_path`), auto-wires the sprint schema so the CVM connection installs the sprint's invariants instead of the shipping ones.

Method resolution on the returned instance:

- Larry-defined methods win first (via `Larry.__index = Larry`).
- Then Engine methods (via Larry's own metatable, `__index = Engine`).
- Then anything in Engine's own `__index` chain.
]]
function Larry.new(opts)
	opts = opts or {}
	opts.cvm = opts.cvm or {}

	if opts.cvm.schema_path == nil then
		opts.cvm.schema_path = sprint_schema_path()
	end

	local larry = Engine.new(opts)

	return setmetatable(larry, Larry)
end


return Larry
