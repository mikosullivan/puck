--[[
{
	"module": "object",
	"role": "Root class in the frames-as-objects design. Anything that participates in the object graph — hash primitives, array primitives, scalars, frames — inherits from `object`. Provides the `bucket` accessor that lazily materializes an owner's bucket on first access. All DB access is composed on the engine; this class does not touch self.db directly.",
	"exports": {
		"new":    "(engine, row) -> object — constructor; lifts row columns onto self",
		"bucket": "() -> object — the object's bucket, lazily created on first call"
	},
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# Object

The root class in the frames-as-objects design. Anything that
participates in the object graph — hash primitives, array primitives,
scalars, frames — inherits from `object`.

**Composes on the engine.** No direct DB access. Every read or write
routes through cached prepared-statement methods on the engine
(`engine:object_by_pk`, `engine:add_bucket`, ...) — so this class stays
pure "wrap a row + expose methods on it" and the engine owns the SQL.
]]

local object = {}
object.__index = object

--[[
## Constructing an object

`object.new(engine, row)` takes the engine that owns this object and
the `objects` row it wraps (a Lua table with columns as fields). It
lifts every column onto `self` so method bodies read them as
`self.<column>` — `self.object_pk`, `self.bucket_pk`, `self.owner_role`,
and so on.

Callers get one via `engine:object_by_pk(pk)`, which fetches the row
and passes it here. Dispatching to a specific subclass (HashPrimitive,
ArrayPrimitive, scalar, frame) based on `row.primitive` — and any
per-pk caching so mutations propagate — lives inside this constructor
too, though that piece isn't spec'd yet.
]]
function object.new(engine, row)
	local self = setmetatable({}, object)
	self.engine = engine

	for k, v in pairs(row) do
		self[k] = v
	end

	return self
end

--[[
## `bucket` — the object's bucket, lazily created

Returns the object's bucket wrapped as an object. Creates the bucket
on first call; returns the cached one thereafter.

The whole flow composes on two engine methods:

- `engine:add_bucket(self.object_pk)` — INSERT the HashPrimitive with
  `bucket_for = self.object_pk`, returning the new bucket's
  `object_pk`. The bucket's `owner_role` is derived from `self`'s row
  by the engine method — no need to pass it. The
  `objects_denormalize_bucket` trigger fires inside the same statement
  and sets `self`'s `bucket_pk` column; the returned pk equals what
  `self.bucket_pk` becomes.
- `engine:object_by_pk(self.bucket_pk)` — wrap the row as a
  HashPrimitive object. Callers do `bucket['locals']` on the return,
  which needs a hash-indexable object, not a bare pk string.

**Idempotent by design.** After the first call materializes the
bucket, `self.bucket_pk` is set, so subsequent calls skip the
`if not self.bucket_pk` block and go straight to `object_by_pk`. No
wasted writes, no duplicate INSERTs.

**Access is gated elsewhere.** `.bucket` gives you the bucket if
you're allowed to have it. Whether you're allowed lives in Caspian's
access-control layer, not here. This method assumes permission has
already been granted.
]]
function object:bucket()
	if not self.bucket_pk then
		self.bucket_pk = self.engine:add_bucket(self.object_pk)
	end

	return self.engine:object_by_pk(self.bucket_pk)
end

return object
