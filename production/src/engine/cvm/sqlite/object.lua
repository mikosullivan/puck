--[[
{
	"module": "object",
	"role": "Root wrapper class in the frames-as-objects design. Every `objects` row loaded via engine:object_by_pk gets wrapped through here: `control = 'f'` rows wrap as `frame` (which inherits from `object`); every other row wraps as `object` itself. Provides the `bucket` and `stack` accessors that lazily materialize the owner's bucket / stack on first access. All DB access is composed on the engine; this class does not touch self.db directly.",
	"exports": {
		"new":    "(engine, row) -> object — constructor; stamps the metatable on the row table itself (row-as-instance)",
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
the `objects` row it wraps (a Lua table with columns as fields). The
row table itself becomes the instance — `_wrap` stamps the metatable
directly on it — so every column is reachable as `self.<column>`
(`self.object_pk`, `self.bucket_pk`, `self.owner_role`, and so on)
without a separate copy step.

Callers get one via `engine:object_by_pk(pk)`, which fetches the row
and passes it here.

**Class dispatch is on `row.control`.** `control = 'f'` wraps as
`frame`; every other row (including functions and closures,
which are plain `'o'` objects with their CaspM in the bucket) wraps
as a plain `object`. The schema's `frame_ast` column is biconditional with
`control = 'f'`, so "is this a frame?" and "does this row carry
executable code" are the same structural question — answered at
row-write time, not inferred by the wrapper. What distinguishes an
on-stack frame from a popped-but-captured one is whether the stack
coordinates (`process`, `idx`, `frame_stmt_idx`) are set — a runtime
question the class answers with its methods, not class dispatch.

The internal `_wrap` helper does the actual metatable set + engine
lift, reusing the row table itself as the instance.

**Row-as-instance.** `_wrap` stamps the metatable directly onto `row`
rather than allocating a fresh table and copying columns across.
lsqlite3's `nrows()` yields a brand-new table each iteration — the
row is never shared with anyone else — so mutating it in place is
safe. Saves one table allocation plus ≈15 hashmap inserts on every
uncached wrap. Requires no `objects` column named `engine`; verified
against the schema.
]]
local function _wrap(mt, engine, row)
	row.engine = engine
	return setmetatable(row, mt)
end

-- Every row wraps as a plain `object`. There used to be a
-- control-based dispatch branch that wrapped `control='f'` rows as a
-- `frame` subclass, but the frame class ended up carrying no
-- frame-specific behavior (its methods moved to CVM as plain
-- functions taking pks). A frame subclass gets re-introduced when
-- frame-specific wrapper behavior actually earns it — memoization
-- keyed on frame identity, say. Until then, one wrapper class.
function object.new(engine, row)
	return _wrap(object, engine, row)
end

-- Expose the internal helper so any future subclass can build the
-- wrapped object without re-entering `object.new`.
object._wrap = _wrap

--[[
## `bucket` — the object's bucket, lazily created

Returns the object's bucket wrapped as an object. Creates the bucket
on first call; returns the cached wrapper thereafter.

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

**Wrapper memoized on `self._bucket`.** The bucket row never changes
identity — same pk forever, and there's no operation that reassigns
a target's bucket. So the wrapper is cached on `self._bucket` on the
first call, and every subsequent call short-circuits to a single
field lookup + return. Skips the SELECT, skips `object.new`, skips
`_wrap`'s column-lift loop — this is the hot-path win.

**No writes on the memoized path.** After first materialization
`self.bucket_pk` is also set, so even if the wrapper cache were ever
missed (it isn't, in the current design) the `if not pk` guard would
still prevent a duplicate INSERT.

**Callers: hoist the wrapper out of tight loops.** The returned
wrapper is stable — same identity every call — so callers that hit
`.bucket` inside a hot loop should cache it once in a local:

    local bucket = obj:bucket()
    for i = 1, n do
        bucket:whatever()
    end

That skips the metatable method lookup + Lua call frame on every
iteration — the ≈46 ns/call floor `object:bucket()` bottoms out at
after wrapper memoization. This method can't shave that from its
side; the loop is the caller's to tighten.

**Access is gated elsewhere.** `.bucket` gives you the bucket if
you're allowed to have it. Whether you're allowed lives in Caspian's
access-control layer, not here. This method assumes permission has
already been granted.
]]
function object:bucket()
	local bucket = self._bucket
	if bucket then return bucket end

	local cvm = self.engine.data
	local pk  = self.bucket_pk

	if not pk then
		pk = cvm:add_bucket(self.object_pk)
		self.bucket_pk = pk
	end

	bucket = cvm:object_by_pk(pk)
	self._bucket = bucket
	return bucket
end

--[[
## `stack` — the object's stack, lazily created

Parallel to `bucket`, on the array side. Returns the object's stack —
an ArrayPrimitive with `stack_for` pointing at this object — wrapped
as an object. Creates the stack on first call; returns the cached
wrapper thereafter.

Same composition as `bucket`:

- `engine:add_stack(self.object_pk)` — INSERTs the ArrayPrimitive with
  `stack_for = self.object_pk`, returning the new stack's `object_pk`.
  The stack's `owner_role` is derived from `self`'s row by the engine
  method. The `objects_denormalize_stack` trigger fires inside the same
  statement and sets `self`'s `stack_pk`.
- `engine:object_by_pk(self.stack_pk)` — wraps the row as an
  ArrayPrimitive object.

**Wrapper memoized on `self._stack`.** Same hot-path optimization as
`bucket`: the stack row never changes identity, so the wrapper is
cached on `self._stack` on the first call and every subsequent call
short-circuits to a single field lookup + return.

**Callers: hoist the wrapper out of tight loops.** Same guidance as
`bucket` — cache the result in a local once and reuse it across the
loop rather than calling `.stack` every iteration.

**Access is gated elsewhere.** Same discipline as `bucket` — this
method assumes permission has already been granted.
]]
function object:stack()
	local stack = self._stack
	if stack then return stack end

	local cvm = self.engine.data
	local pk  = self.stack_pk

	if not pk then
		pk = cvm:add_stack(self.object_pk)
		self.stack_pk = pk
	end

	stack = cvm:object_by_pk(pk)
	self._stack = stack
	return stack
end

return object
