# Object class (Lua-side)

~~~vibecode
{"vibecode": {
	"doc": "ideas_object_class",
	"role": "working notes for the Lua engine's Object class — the type that represents every Caspian object during execution. Covers the field shape (id, role, src, bucket, stack — matching the JSON serialization directly so post-V1 export is a plain walk), the constructor/factory split, registration in state.objects, and how first-class Caspian citizens like Roles are built on top of it. Companion to ideas/drinian-spec for the surrounding state hash and to requirements/cvm/objects for the Caspian-facing shape this Lua class implements.",
	"status": "spitballing 2026-08-07 — field shape and creation pattern proposed; not yet in code"
}}
~~~

Companion to [drinian-spec](https://www.puck.uno/ideas/drinian-spec/). The Caspian-facing spec at [mvm/objects](https://www.puck.uno/requirements/cvm/objects) describes what an object IS from the developer's perspective (bucket / stack / platter / role / src). This doc covers how the Lua engine REPRESENTS one during execution: the class, the factory, the mutation surface.

## What every Caspian object carries

Per [mvm/objects](https://www.puck.uno/requirements/cvm/objects), every live Caspian object has:

- **`id`** — string from `state.sequence` (e.g., `"7"`, `"42"`)
- **`role`** — **role ID** (a string from `state.sequence`) identifying the role that owns this object. Roles don't inherently have names — `"engine"` and `"user"` are just human labels on the role's `.bucket.name`; the role's IDENTITY is its ID. The `role` field on any object holds another object's ID (the role's), just like every other cross-object reference in CVM.
- **`src`** — optional `[src_key, line]` tuple for the birth site
- **`bucket`** — hash of user-facing key-value pairs
- **`stack`** — ordered array of platters (each a hash carrying `class` + optional flags)

**Divergence from the current requirements/cvm/objects examples.** Those examples show `"role": "user"` — the role's name string. Under the design here that becomes `"role": "<id-of-the-user-role-object>"` — the ID. Names on roles are for inspection and diagnostics; identity is by ID everywhere else in CVM, and role ownership should be no different. Requirements/cvm/objects needs a sweep to match.

## The Lua Object class

One Lua class represents every Caspian object. Instances are plain tables with a metatable; the visible field shape matches the JSON serialization directly, so post-V1 snapshot export is a plain walk with no re-marshaling.

~~~lua
Object = {}
Object.__index = Object

function Object.new(id, role_id)
	return setmetatable({
		id     = id,
		role   = role_id,   -- ID of the role that owns this object
		src    = nil,       -- populated when the birth site is known
		bucket = {},
		stack  = {},
	}, Object)
end
~~~

The instance IS the source of truth for the object. `state.objects[id]` holds the same table by reference — no double-storage, no shadow. Every mutation (writing bucket entries, pushing platters, updating src) happens on the instance and is visible through both access paths.

## Creation

Two entry points at the module level:

- **`object.new(id, role_id)`** — builds an unregistered Object. Useful in tests, or when staging an object before deciding whether to register it.
- **`object.create(state, role_id)`** — the standard factory. Allocates a fresh ID from `state.sequence:next()`, constructs the Object with `role_id` as its owner, inserts it in `state.objects`, returns it.

~~~lua
function M.create(state, role_id)
	local id  = state.sequence:next()
	local obj = M.new(id, role_id)
	state.objects[id] = obj
	return obj
end
~~~

`role_id` must be an existing role's ID — typically obtained by reading `%call.role`'s ID inside a running frame, or (during boot) by holding a reference to the role Object being built up. The class platter that identifies WHAT the object is (`{class = "core:role"}`, `{class = "core:string"}`, etc.) is pushed onto `obj.stack` separately — `object.create` just makes the empty shell.

## Applied to Roles

Roles become full Objects on this base. The engine role is a special case (chicken-and-egg — see below); every other role is created with an existing role as its owner:

~~~lua
function roles.new(state, name, owner_role_id)
	local obj = object.create(state, owner_role_id)
	table.insert(obj.stack, {class = 'core:role'})
	obj.bucket.name = name
	return obj
end
~~~

Every Role gets a sequence-allocated `.id`, an entry in `state.objects`, and a `core:role` class platter on its stack. The Trivet tree in `state.roles` still holds these Role Objects as node values (unchanged from today's structure); the difference is each Role now has an ID and is looked up like anything else in `state.objects`. The role's human name lives in `obj.bucket.name` for inspectors and diagnostics; identity is by `.id`.

## The engine role's own role

Every object entry in `state.objects` carries a `role` field holding its owner's role ID (see [Object ownership](https://www.puck.uno/requirements/cvm/#object-ownership)). So does the engine role itself, which is the very first Object created during boot — and has no pre-existing role to point at. Two ways to resolve the chicken-and-egg:

- **Self-owned.** The engine role's `role` field holds its OWN ID. Bootstrap allocates the ID from the sequence, constructs the Object with `role = <that same ID>`, and inserts it in `state.objects`. Subsequent roles get owned by whichever role loaded / spawned them (user by engine, libraries by whoever loaded them).
- **A synthetic bootstrap role.** Introduce an extra `'bootstrap'` role that owns the engine role, then engine role owns everything else. Adds a role.

Self-owned is simpler and matches how `engine` is already positioned as the root of the Trivet tree. Boot sketch:

~~~lua
-- Special path for the very first role: allocate its ID up front,
-- then use that ID as its own owner.
local engine_id  = state.sequence:next()
local engine_obj = Object.new(engine_id, engine_id)   -- self-owned
table.insert(engine_obj.stack, {class = 'core:role'})
engine_obj.bucket.name = 'engine'
state.objects[engine_id] = engine_obj

-- Every other role: takes an owner role ID.
local user_obj = roles.new(state, 'user', engine_id)  -- owned by engine
~~~

## Bucket and stack mutation

Plain field access for V1 — no getter/setter methods, no wrapper. Callers write `obj.bucket.name = 'engine'` or `table.insert(obj.stack, platter)` directly.

Reasons:
- Matches the JSON serialization shape one-to-one.
- Keeps the Lua-side surface minimal until a specific mutation pattern earns dedicated method sugar.
- The engine's own dispatch code walks `obj.stack` and reads `obj.bucket` uniformly — accessor methods would just be pass-throughs.

Sugar (e.g., `obj:push_platter(class_name)`) can land later if patterns repeat enough to warrant it.
