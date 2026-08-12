--[[
{
	"module": "frame",
	"role": "Class representing a call frame under the frames-as-objects design. Inherits from `object` — picks up the `bucket` accessor for free. Adds `locals` (read-only accessor), `ensure_locals` (get-or-create), and `set_local_to_scalar` (specialized write path for scalar-RHS assignments like `$x = 1`).",
	"inherits_from": "object",
	"exports": {
		"new":                 "(engine, row) -> frame — constructor",
		"locals":              "() -> object — the frame's locals hash; nil if it hasn't been created yet (read-only)",
		"ensure_locals":       "() -> object — the frame's locals hash, materializing it on first call",
		"set_local_to_scalar": "(name, scalar_type, scalar_value) — specialized routine for `$name = <primitive scalar>`"
	},
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# Frame

A class representing a call frame under the frames-as-objects design.
Inherits from `object`, so it picks up the `bucket` accessor for free.
Adds `locals` (read-only), `ensure_locals` (get-or-create), and
`set_local_to_scalar` (the specialized write path for scalar-RHS
assignments like `$x = 1`). Every local variable in the frame is a
key in the locals hash — a HashPrimitive stored inside the frame's
bucket under the key `locals`.
]]

--[[
## Inheriting from `object`

Single inheritance via Lua's metatable chain. `frame` starts as an
empty table whose metatable delegates lookups to `object` — that's
what `setmetatable({}, {__index = object})` sets up. Any method not
defined directly on `frame` (like `bucket`) resolves via `object`.
`frame.__index = frame` then makes `frame` itself the index for its
own instances, so `frame:locals()` and friends resolve on the wrapper.
]]
local object = require("object")

local frame = setmetatable({}, {__index = object})
frame.__index = frame

--[[
## Constructing a frame

`frame.new(engine, row)` uses `object._wrap` — the shared
metatable-set-and-lift-columns helper — with `frame` as the metatable.
Going through `_wrap` (rather than calling `object.new`) skips
`object.new`'s ast-based dispatch branch, so a frame row loaded via
`engine:object_by_pk` doesn't recurse into `object.new → frame.new
→ object.new → …`.
]]
function frame.new(engine, row)
	return object._wrap(frame, engine, row)
end

--[[
## `locals` — the frame's locals hash (read-only)

Returns the frame's locals hash — a HashPrimitive stored inside the
frame's bucket under the key `locals`. `nil` if it hasn't been created
yet.

Composes on the inherited `bucket` accessor and on
`engine:get_ref_child`: get the bucket (which materializes it on first
access), then look up the child of the ref where `parent = bucket` and
`key = 'locals'`.

**Read-only.** `locals` doesn't create the locals hash — it only
returns whatever's stored under `bucket['locals']`. On a fresh frame,
before anything has been assigned, that entry doesn't exist yet and
this returns `nil`. For the get-or-create variant, see `ensure_locals`.

**Wrapper memoized on `self._locals`.** Same treatment as
`object:bucket`. The locals hash's identity never changes once it
exists — the ref planted under `bucket['locals']` is immutable and
points at one specific hash forever — so the wrapper is cached on
`self._locals` on the first successful return and every subsequent
call short-circuits to a single field lookup. `ensure_locals` writes
into the same cache field, so calling one after the other doesn't
re-run the fetch. **Negative results are not cached** — on a fresh
frame `locals()` returns nil without setting `_locals`, so a later
call after `ensure_locals` populates it will still see the new hash.
]]
function frame:locals()
	local locals = self._locals
	if locals then return locals end

	local engine = self.engine
	local bucket = self:bucket()
	local locals_pk = engine:get_ref_child(bucket.object_pk, 'locals')

	if not locals_pk then
		return nil
	end

	locals = engine:object_by_pk(locals_pk)
	self._locals = locals
	return locals
end

--[[
## `ensure_locals` — get-or-create the frame's locals hash

Returns the frame's locals hash, materializing it on first call. On
every subsequent call, returns the same hash — the ref planted under
`bucket['locals']` makes the lookup idempotent.

Composes on three engine methods:

- `engine:get_ref_child(bucket.object_pk, 'locals')` — is there already
  a `locals` entry in the bucket?
- `engine:add_hash(self.owner_role)` — if not, create a fresh
  HashPrimitive owned by the same role that owns the frame.
- `engine:add_ref(bucket.object_pk, 'locals', locals_pk)` — bind that
  new hash under the key `locals` inside the bucket.

The write path (`set_local_to_scalar`, and any other future write
routine) calls this before adding the actual variable binding. The
first-variable walkthrough spells it out step by step —
[frame.locals ensure the locals hash](https://www.puck.uno/ideas/frames-as-objects/examples/first-variable/#framelocals-ensure-the-locals-hash).

**Wrapper memoized on `self._locals`** — shared with `frame:locals`.
Once the hash exists, both accessors short-circuit through the same
cache field. `set_local_to_scalar` calls `ensure_locals` for every
binding; after the first, the whole `bucket + get_ref_child + wrap`
chain collapses to one field lookup.
]]
function frame:ensure_locals()
	local locals = self._locals
	if locals then return locals end

	local engine = self.engine
	local bucket = self:bucket()
	local bucket_pk = bucket.object_pk
	local locals_pk = engine:get_ref_child(bucket_pk, 'locals')

	if not locals_pk then
		locals_pk = engine:add_hash(self.owner_role)
		engine:add_ref(bucket_pk, 'locals', locals_pk)
	end

	locals = engine:object_by_pk(locals_pk)
	self._locals = locals
	return locals
end

--[[
## `set_local_to_scalar` — specialized routine for `$name = <scalar>`

Handles the single, specific case of a scalar-RHS assignment to a
local variable in this frame — e.g. `$x = 1`, `$name = 'alice'`,
`$flag = true`. Not a general-purpose "set a local" method. Per the
first-variable walkthrough's design intent, each shape of assignment
(scalar RHS, name-lookup RHS, function-call RHS, closure RHS,
attribute-target LHS, ...) gets its own routine — trying to unify
them prematurely picks the wrong abstraction.

Three composed engine/frame calls:

1. `engine:add_scalar(scalar_type, scalar_value, self.owner_role)` —
   materialize the scalar as a new objects row, owned by the same role
   as the frame.
2. `self:ensure_locals()` — get-or-create the frame's locals hash.
3. `engine:add_ref(locals.object_pk, name, scalar_pk)` — bind the
   variable name to the scalar inside the locals hash.

**Fresh-binding only.** The `unique (parent, key)` constraint on
`refs` means calling this with a `name` that's already bound in the
locals hash fails the ref insert. Reassignment is a separate
specialized routine (not yet written).

**Long name deliberate.** `set_local` or `assign` would be inviting
call sites to reach for this method when their RHS isn't actually a
primitive scalar. `set_local_to_scalar` signals the specialization at
the point of use.
]]
function frame:set_local_to_scalar(name, scalar_type, scalar_value)
	local scalar_pk = self.engine:add_scalar(scalar_type, scalar_value, self.owner_role)
	local locals = self:ensure_locals()

	self.engine:add_ref(locals.object_pk, name, scalar_pk)
end

return frame
