--[[
{
	"module": "object",
	"role": "Sketch of the Lua-side implementation of Caspian's built-in Object class — the root of the Caspian class hierarchy. Not the row-wrapper at production/src/engine/cvm/sqlite/object.lua (which provides bucket/stack accessors for any objects row); this module IS the engine-provided class implementation that a seeded Caspian Object class-row references via engine_class = 'object'. Method tables are empty for this pass — the file exists so the sprint has something to grow into.",
	"exports": {
		"methods":  "table of instance methods (empty in this sketch) — populated over the sprint's method-implementation passes",
		"obj":      "the cross-cutting `.obj` namespace catalog (empty in this sketch); non-overridable per the spec"
	},
	"depends_on": [],
	"status": "sketch — surface reserved, no method bodies yet"
}
]]

--[[
# Object (Caspian class)

Lua-side implementation of Caspian's Object class. Every Caspian
value's class stack ends here; a method call that walks the stack all
the way down without a match either hits an Object method or raises
method-not-found.

**Two Object files, one system.**

- `production/src/engine/cvm/sqlite/object.lua` — the ROW WRAPPER.
  Wraps any `objects` row with `bucket` / `stack` accessors. Used by
  the engine to hand Caspian rows to Lua code as Lua tables.
- THIS FILE — the CASPIAN CLASS IMPLEMENTATION. Provides the method
  bodies Caspian source calls into when dispatch resolves against
  Object. A single seeded `objects` row (the Object class-row itself)
  hooks into this module via its `engine_class = 'object'` column.

The wrapper and the class implementation are separate concerns that
happen to share a name because both are "Object" in the informal
sense. Keep them mentally apart.

**Registration.** At bootstrap the engine seeds the Object class-row
and calls into this module to populate its method surface. TBD
exactly what the registration hook looks like — sprint decides once
the .new / class-stack machinery is real.

**Sketch state.** Everything below is placeholder. Empty tables and
no method bodies. Real bodies land as the sprint progresses.
]]

--[[
## Instance methods

The regular per-instance method surface. Callers reach these as
`$obj.<name>` — dispatch walks the class stack, and when the walk
reaches Object it consults this table.

Overridable — a class above Object in the stack can shadow any of
these names.
]]
local methods = {}

--[[
## `obj` namespace

The cross-cutting namespace every instance carries — `$obj.obj.<name>`.
Per the spec at [built-in-classes/object/methods](https://puck.uno/requirements/built-in-classes/object/methods/),
these are non-overridable — no class higher in the stack can shadow
them. Dispatched via a separate path from regular method resolution.
]]
local obj = {}

--[[
## Module export
]]
return {
	methods = methods,
	obj     = obj,
}
