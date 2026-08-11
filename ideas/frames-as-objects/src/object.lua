--[[
{
	"module": "object",
	"role": "Root class in the frames-as-objects design. Anything that participates in the object graph — hash primitives, array primitives, scalars, frames — inherits from `object`. Provides the `bucket` accessor that lazily materializes an owner's bucket on first access. All DB access is composed on the engine; this class does not touch self.db directly.",
	"exports": {
		"new":    "(engine, row) -> object — constructor; lifts row columns onto self",
		"bucket": "() -> object — the object's bucket, lazily created on first call",
		"stack":  "() -> object — the object's stack, lazily created on first call"
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
and passes it here.

**Class dispatch is on `row.ast`.** Under the frames-as-objects design
a frame is any objects row with a non-null `ast` — there's no separate
callable/frame split. If `row.ast` is present, `object.new` hands off
to `frame.new` so the returned wrapper carries the frame class's
methods (`locals`, ...). Otherwise it wraps as a plain `object`.

The internal `_wrap` helper does the actual metatable set + column
lift. `frame.new` reuses it to avoid re-entering `object.new` (which
would loop forever on any frame row).
]]
local function _wrap(mt, engine, row)
	local self = setmetatable({}, mt)
	self.engine = engine

	for k, v in pairs(row) do
		self[k] = v
	end

	return self
end

function object.new(engine, row)
	if row.ast ~= nil then
		local frame = require("frame")
		return frame.new(engine, row)
	end

	return _wrap(object, engine, row)
end

-- Expose the internal helper so `frame.new` (and any future subclass)
-- can build the wrapped object without re-entering `object.new`'s
-- dispatch branch.
object._wrap = _wrap

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

--[[
## `stack` — the object's stack, lazily created

Parallel to `bucket`, on the array side. Returns the object's stack —
an ArrayPrimitive with `stack_for` pointing at this object — wrapped
as an object. Creates the stack on first call; returns the cached one
thereafter.

Same composition as `bucket`:

- `engine:add_stack(self.object_pk)` — INSERTs the ArrayPrimitive with
  `stack_for = self.object_pk`, returning the new stack's `object_pk`.
  The stack's `owner_role` is derived from `self`'s row by the engine
  method. The `objects_denormalize_stack` trigger fires inside the same
  statement and sets `self`'s `stack_pk`.
- `engine:object_by_pk(self.stack_pk)` — wraps the row as an
  ArrayPrimitive object.

**Idempotent by design.** After the first call materializes the
stack, `self.stack_pk` is set, so subsequent calls skip the
`if not self.stack_pk` block. No wasted writes.

**Access is gated elsewhere.** Same discipline as `bucket` — this
method assumes permission has already been granted.
]]
function object:stack()
	if not self.stack_pk then
		self.stack_pk = self.engine:add_stack(self.object_pk)
	end

	return self.engine:object_by_pk(self.stack_pk)
end

return object
