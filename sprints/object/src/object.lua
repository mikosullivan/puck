--[[
{
	"module": "object",
	"role": "Lua-side implementation of Caspian's built-in Object class — the root of the Caspian class hierarchy. Wraps a Caspian object row as a lightweight Lua handle carrying the row's pk, the engine reference, and a raw-db shortcut. Method surfaces (regular methods, `.obj` cross-cutting namespace) live as placeholder tables that grow as the sprint spec's each method.",
	"exports": {
		"new":      "(engine, pk) -> object — constructor; stores pk + engine on a fresh instance and caches engine.cvm as `db` for hot-path use",
		"methods":  "table of overridable per-instance methods (empty in this sketch) — populated over the sprint's method-implementation passes",
		"obj":      "the non-overridable `.obj` cross-cutting namespace catalog (empty in this sketch); dispatched via the engine's `.obj` fast-path, not via the class chain"
	},
	"depends_on": [],
	"status": "sketch — constructor + fields land; method bodies still to come"
}
]]

--[[
# Object (Caspian class)

Lua-side implementation of Caspian's Object class. Every Caspian
value's platters end here; a method call that walks the platters all
the way down without a match either hits an Object method or raises
method-not-found.

**Two Object files, one system.**

- `production/src/engine/cvm/sqlite/object.lua` — the ROW WRAPPER.
  Wraps any `objects` row with `bucket` / `platters` accessors. Used by
  the engine to hand Caspian rows to Lua code as Lua tables.
- THIS FILE — the CASPIAN CLASS IMPLEMENTATION. Provides the method
  bodies Caspian source calls into when dispatch resolves against
  Object. A single seeded `objects` row (the Object class-row itself)
  hooks into this module via its `engine_class = 'object'` column.

The wrapper and the class implementation are separate concerns that
happen to share a name because both are "Object" in the informal
sense. Keep them mentally apart.

**Instance shape.** Three fields, one hop each:

- `pk`     — the object_pk this Lua wrapper stands in for.
- `engine` — reference to the owning engine. Provides everything upstream:
  owner_role, current-process pk, prepared-statement cache, whatever else.
- `db`     — cached copy of `engine.cvm`. The raw sqlite3 handle. Hot-path
  shortcut so method bodies can call `self.db:nrows(...)` without
  reaching through `engine` on every call.

All three fields are set at construction and treated as stable for the
wrapper's lifetime. Two wrappers compare `==` iff they hold the same pk
under the same engine — same object in the same world.

**Registration.** At bootstrap the engine seeds the Object class-row
and calls into this module to populate its method surface. TBD
exactly what the registration hook looks like — sprint decides once
the .new / platters machinery is real.

**Sketch state.** Constructor + fields land here. `methods` and `obj`
tables are empty placeholders. Real bodies land as the sprint
progresses.
]]

local object = {}
object.__index = object

--[[
## Constructor

`object.new(engine, pk)` builds a fresh Lua wrapper for the Caspian
object identified by `pk` under the given `engine`. The wrapper stashes
the engine, the pk, and a cached raw-db handle (`engine.cvm`) for
hot-path use.

No side effects — nothing gets read from or written to the database
here. The wrapper is a Lua-side handle; whether the pk names a row
that actually exists is up to the caller to know or check.
]]
function object.new(engine, pk)
	return setmetatable({
		pk     = pk,
		engine = engine,
		db     = engine.cvm,
	}, object)
end

--[[
## Equality

`a == b` is true iff both wrappers hold the same pk under the same
engine. Same pk across different engines is a different Caspian
object (different db, different world), so both fields participate
in the comparison.
]]
function object.__eq(a, b)
	return a.pk == b.pk and a.engine == b.engine
end

--[[
## Instance methods

The regular per-instance method surface. Callers reach these as
`$obj.<name>` — dispatch walks the platters, and when the walk
reaches Object it consults this table.

Overridable — a class above Object in the platters can shadow any of
these names.
]]
object.methods = {}

--[[
## `obj` namespace

The cross-cutting namespace every instance carries — `$obj.obj.<name>`.
Per the spec at [built-in-classes/object/methods](https://puck.uno/requirements/built-in-classes/object/methods/),
these are non-overridable — no class in the platters can shadow
them. Dispatched via a separate path from regular method resolution.
]]
object.obj = {}


return object
