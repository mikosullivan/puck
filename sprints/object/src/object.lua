--[[
{
	"module": "object",
	"role": "Lua-side implementation of Caspian's built-in Object class — the root of the Caspian class hierarchy. Wraps a Caspian object row as a lightweight Lua handle carrying the row's pk, the engine reference, and a raw-db shortcut. Method surfaces (regular methods, `.obj` cross-cutting namespace) live as placeholder tables that grow as the sprint spec's each method.",
	"exports": {
		"new":      "(engine, pk) -> object — constructor; stores pk + engine on a fresh instance and caches engine.cvm as `db` for hot-path use",
		"methods":  "table of Object's Caspian-level methods (empty in this sketch) — populated over the sprint's method-implementation passes. Same shape sibling classes use: `<class_module>.methods[<method_name>](receiver)` is how the dispatcher will call in."
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
wrapper's lifetime.

**Registration.** At bootstrap the engine seeds the Object class-row
and calls into this module to populate its method surface. TBD
exactly what the registration hook looks like — sprint decides once
the .new / platters machinery is real.

**Sketch state.** Constructor + fields land here. `methods` is an
empty placeholder. Real bodies land as the sprint progresses.
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
## Method catalog

Caspian-level method bodies for the Object class. The dispatcher
resolves `$obj.<name>` by walking the receiver's dispatch chain; when
the walk lands on Object, it looks up `object.methods[<name>]` and
invokes it with the receiver as the first argument.

Overridable — a class above Object in the platters can shadow any of
these names.
]]
object.methods = {}


return object
