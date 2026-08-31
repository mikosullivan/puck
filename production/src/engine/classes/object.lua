--[[
{
	"module": "classes.object",
	"role": "The root of the Caspian class hierarchy. Every Caspian class inherits from Object; every Caspian value is-a Object. Provides the minimal set of methods every object responds to at dispatch time — identity equality (`==`), inequality (`!=`), and default stringification (`to_s`). Registered on the engine at construction as `engine.classes.Object` (Lua-side registry — primitive classes have no corresponding `objects` row; the row classifier infers class from `scalar_*` columns on primitive instances). The general mc dispatcher (not yet built) will walk class chains up to Object for method resolution when a subclass doesn't override.",
	"exports": {
		"name":    "'Object' — the class name",
		"parent":  "nil — Object is the root, no parent",
		"methods": "hash keyed by method name; values are Lua functions with signature (frame, self_pk, ...arg_pks) -> result_pk"
	},
	"depends_on": [],
	"status": "V0.1 — minimal method set (==, !=, to_s); mc dispatch integration lands separately"
}
]]

--[[
# `classes.object`

The root class of the Caspian class hierarchy.

**Not the same as** `cvm.sqlite.object` (that's the Lua-side wrapper for `objects` DB rows — engine plumbing that has nothing to do with the Caspian class hierarchy). Different module, different responsibility.

**Class descriptor shape.**

- `name` — the class's user-visible name.
- `parent` — the class this one inherits from (a class descriptor), or `nil` for the root.
- `methods` — a hash from method name (string) to Lua function. Each function takes `(frame, self_pk, ...arg_pks)` and returns a `result_pk` (an object_pk pointing at whatever object represents the method's return value). The `frame` argument gives methods access to `frame.engine.data` for CVM operations and `frame.owner_role` for new-object ownership.

**Lua-side registry, no DB row (for primitive classes).** The design principle "every Caspian object has a corresponding record object" applies to VALUE objects — an instance of Number, a hash, a user instance, all have DB rows. Primitive CLASSES (Object, Number, String, Boolean, Null) don't: at dispatch time the row classifier infers a receiver's class from its `scalar_*` columns (Number from `scalar_number IS NOT NULL`, etc.), and the class descriptor itself lives Lua-side in `engine.classes[NAME]`. Seeding a placeholder row per primitive class would clutter the DB without carrying any information the columns don't already convey. User-defined classes are different — their methods live as Caspian closures, not Lua functions, and they'll need real DB rows to hang that state on. That machinery lands with the user-class work.

**Where methods live.** For core classes (this file, plus future Number / String / Bool / Frame / Callable), method implementations are Lua functions in the `methods` table. For user-defined classes (once we can define them from Caspian source), each method's value will be a Caspian closure body (an ast) instead of a Lua function; the mc dispatcher distinguishes by inspecting the value's type.

**"Cheat" boundary.** The Object class deliberately reaches into `frame.engine.data` for CVM writes (`add_scalar`, etc.). This couples the class implementation to the CVM, which the design principle nominally wants separated — but as a low-priority nudge, not a rule. Coupling here is the pragmatic path.
]]

local Object = {
	name    = 'Object',
	parent  = nil,
	methods = {},
}

--[[
## `Object:==` — identity equality

Two objects are `==` when their `object_pk`s match. Returns a fresh scalar_bool.

This is intentionally identity, not structural equality. Subclasses that want value-equality (Number, String) override — for example, `1 == 1.0` should compare number values, not object_pks. Object's default is the last line of defense: two unrelated objects are equal iff they're the same object.
]]
Object.methods['=='] = function(frame, self_pk, other_pk)
	return frame.engine.data:add_scalar(self_pk == other_pk, frame.owner_role)
end

--[[
## `Object:!=` — negated identity equality

Complement of `==`. Same pk-identity check, negated.
]]
Object.methods['!='] = function(frame, self_pk, other_pk)
	return frame.engine.data:add_scalar(self_pk ~= other_pk, frame.owner_role)
end

--[[
## `Object:to_s` — default string representation

Returns `#<Object PK>` as a fresh scalar_string. Subclasses override with type-specific representations — Number returns `"42"`, String returns its content, etc.

Callers that want something more meaningful implement a class-specific override; this is the fallback so `.to_s` is always answerable on every object.
]]
function Object.methods.to_s(frame, self_pk)
	return frame.engine.data:add_scalar(
		'#<Object ' .. tostring(self_pk) .. '>',
		frame.owner_role
	)
end


return Object
