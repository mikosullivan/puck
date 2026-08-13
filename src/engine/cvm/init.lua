--[[
{
	"module": "cvm",
	"role": "Data-access layer for a CVM connection. Owns the SQLite handle, preps every statement upfront, and exposes cached-statement methods (object_by_pk, frame_by_pk, plus the add_* / get_* family) so callers work in objects/pks rather than raw SQL. Sits above `object` and `frame` — the CVM constructs them today; whether it will also call into them, and how, is still open (see the 'Open questions' block in the docstring). Not to be confused with the top-level Caspian runtime at `src/engine/engine.lua`; this file is the CVM's internal object-store, required as `require('cvm')`.",
	"exports": {
		"new":           "(db) -> cvm — constructor; binds an lsqlite3 handle and preps every statement upfront",
		"object_by_pk":  "(pk) -> object — canonical pk-to-object load; nil if no row",
		"frame_by_pk":   "(pk) -> frame — retrieves the row and asserts primitive='f'; raises frame_by_pk_not_found if no such row, frame_by_pk_not_a_frame if the row isn't a frame",
		"add_bucket":    "(for_object_pk) -> new bucket's object_pk — INSERTs a HashPrimitive owned by the target's owner_role",
		"add_stack":     "(for_object_pk) -> new stack's object_pk — INSERTs an ArrayPrimitive owned by the target's owner_role",
		"add_scalar":    "(scalar_type, scalar_value, owner_role_pk) -> new scalar's object_pk",
		"add_hash":      "(owner_role_pk) -> new HashPrimitive's object_pk — plain hash, no bucket_for set",
		"add_array":     "(owner_role_pk) -> new ArrayPrimitive's object_pk — plain array, no stack_for set",
		"add_frame":     "(ast, process_pk, owner_role_pk) -> new frame's object_pk — INSERTs a primitive='f' row with stmt_idx=0",
		"add_ref":       "(parent_pk, key, child_pk) -> new ref_pk — auto-computes the next idx for parent",
		"get_ref_child": "(parent_pk, key) -> child object_pk or nil — hash lookup by key"
	},
	"policy": "CVM DB access goes through dedicated per-statement methods only — no ad-hoc db:exec / db:nrows / db:prepare. Each cached SQL is its own method on the cvm class. Every statement the cvm uses is prepared upfront in cvm.new(); methods just fetch the cached handle, bind, execute, reset. Single-column reads use stmt:step + stmt:get_value(0) to skip nrows()'s per-row table allocation; full-row reads (object_by_pk) stay on nrows() so callers get every column at once.",
	"performance": "Every method on this class is on a hot path. Once the dispatch loop lands (see the open questions in the docstring), most will fire on every statement dispatch; any cycle saved multiplies across the whole running program.",
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# CVM (data-access layer)

The data-access layer for a CVM connection — required as `require('cvm')`
(this file is `src/engine/cvm/init.lua`, so Lua's require system
resolves the bare namespace to this module). Owns the SQLite handle,
preps every statement upfront, and exposes cached-statement methods
(`object_by_pk`, `add_bucket`, `add_stack`, `add_scalar`, `add_hash`,
`add_array`, `add_ref`, `get_ref_child`). Sits above `object` and
`frame` — the CVM constructs them today via `object_by_pk`.

**Not to be confused with `src/engine/engine.lua`.** That file is
Caspian's top-level runtime — what a host imports and calls "the
engine." This file is the CVM's internal object-store, an
implementation detail below the runtime.

## Open questions — not yet built

- **Frame dispatch.** How does a frame-object's `ast` advance
  statement by statement? What's the loop shape — engine-owned, frame-
  owned, or trampoline? What pushes a new frame onto the stack; what
  pops one when it finishes; what marks a frame "done"?
- **Shutdown.** When does the engine decide there's nothing left to
  run and stop? Empty stack on the current process? All processes
  drained? Explicit engine.close call?
- **Direction of composition.** The current class only *provides*
  methods for object/frame to call. Any runtime that dispatches will
  need the CVM to *call into* frame methods too — whether that
  reverses the composition, adds a separate driver class, or lives as
  a top-level loop outside the CVM class is open.

**Policy: DB access via cached-statement methods only.** No ad-hoc
`db:exec`, no inline `db:nrows`, no `db:prepare` scattered through CVM
code. Each SQL the CVM needs is its own method on this class, and every
one of those statements is prepared upfront in `cvm.new()`. Method
bodies are just fetch-cached-handle + bind + execute + reset — no
per-call check for "is it prepared yet." A prepare-time error (typo,
schema mismatch) surfaces at construction, not later when the affected
method first fires.

**Read shape drives the API.** Single-column reads — the six `add_*`
methods that RETURNING one pk, plus `get_ref_child` — use
`stmt:step()` + `stmt:get_value(0)` to fetch the one value they need.
That skips the per-row table lsqlite3's `nrows()` allocates, plus the
string-keyed column lookup, on every call. Full-row reads like
`object_by_pk` stay on `nrows()` because the wrapper wants every
column at once and the row table becomes the wrapper's own storage
via `object._wrap`.

**Every method on this page must be as efficient as possible.** Once
the dispatch loop lands (see the open questions above), most of these
fire on every statement dispatch; any cycle saved multiplies out
across the whole running program.
]]

local sqlite = require("lsqlite3")
local object = require("cvm.object")

-- Cache the ROW status constant into a local. Compared against
-- inside every single-column read path (`stmt:step()` returns
-- `sqlite.ROW` or `sqlite.DONE`); reading it once at module load
-- beats a `sqlite.ROW` global lookup on every hit.
local SQLITE_ROW = sqlite.ROW

local cvm = {}
cvm.__index = cvm

--[[
## Constructing a CVM instance

`cvm.new(db)` takes an already-open lsqlite3 handle — with
`foreign_keys` and `recursive_triggers` pragmas already enabled per the
CVM's per-connection rules — and wraps it as a CVM instance.

Every prepared statement the CVM will use gets prepped right here.
The block below is the CVM's complete SQL manifest — one grep away
for anyone auditing the surface. Any prepare-time error (typo,
schema-vs-SQL mismatch) fails now, at construction, rather than
surfacing later on first call to the affected method.

After `cvm.new` returns, every `self.stmt_<name>` field is
guaranteed present. Method bodies don't need to check.
]]
function cvm.new(db)
	local self = setmetatable({}, cvm)
	self.db = db

	self.stmt_object_by_pk = db:prepare(
		"select * from objects where object_pk = ?"
	)

	self.stmt_add_bucket = db:prepare(
		"insert into objects (primitive, bucket_for, owner_role) " ..
		"select 'h', ?1, owner_role from objects where object_pk = ?1 " ..
		"returning object_pk"
	)

	self.stmt_add_stack = db:prepare(
		"insert into objects (primitive, stack_for, owner_role) " ..
		"select 'a', ?1, owner_role from objects where object_pk = ?1 " ..
		"returning object_pk"
	)

	self.stmt_add_scalar = db:prepare(
		"insert into objects (primitive, scalar_type, scalar_value, owner_role) " ..
		"values ('o', ?, ?, ?) returning object_pk"
	)

	self.stmt_add_hash = db:prepare(
		"insert into objects (primitive, owner_role) values ('h', ?) returning object_pk"
	)

	self.stmt_add_array = db:prepare(
		"insert into objects (primitive, owner_role) values ('a', ?) returning object_pk"
	)

	self.stmt_add_frame = db:prepare(
		"insert into objects (primitive, ast, process, stmt_idx, owner_role) " ..
		"values ('f', ?, ?, 0, ?) returning object_pk"
	)

	self.stmt_add_ref = db:prepare(
		"insert into refs (parent, child, key, idx) " ..
		"values (?1, ?2, ?3, coalesce((select max(idx) + 1 from refs where parent = ?1), 0)) " ..
		"returning ref_pk"
	)

	self.stmt_get_ref_child = db:prepare(
		"select child from refs where parent = ? and key = ?"
	)

	return self
end

--[[
## `object_by_pk` — canonical pk-to-object load

Takes a primary key and returns the corresponding objects row wrapped
as an object. `nil` if no row exists for that pk.

Caller-side:

    local obj = cvm:object_by_pk(pk)

`stmt:reset()` runs on every call — required by lsqlite3 for reusable
prepared statements; without it the next `bind_values` on the same
handle raises.

`object.new(self, row)` wraps the row as an object instance. Class
dispatch is primitive-based: `row.primitive == 'f'` wraps as `frame`;
every other primitive wraps as a plain `object`. No per-pk cache — a
fresh wrapper is built each call. Per-instance memoization for the
`bucket`, `stack`, and `locals` accessors lives on the wrappers
themselves (`self._bucket`, `self._stack`, `self._locals`).
]]
function cvm:object_by_pk(pk)
	local stmt = self.stmt_object_by_pk
	stmt:bind_values(pk)
	local row

	for r in stmt:nrows() do
		row = r
	end

	stmt:reset()

	if not row then
		return nil
	end

	return object.new(self, row)
end

--[[
## `frame_by_pk` — retrieve and assert primitive='f'

Retrieval-with-check for callers that expect a frame. Composes on
`object_by_pk` for the fetch, then asserts `primitive == 'f'` before
returning. Raises specific errors if the row doesn't exist or isn't
a frame.

**Why an assertion, not just a call.** During the walking-skeleton
phase, "the engine has a pk it believes is a frame" is a load-bearing
assumption that isn't yet backed by a type system. Any code path that
retrieves what it expects to be a frame should call `frame_by_pk`
rather than `object_by_pk` — the extra CPU cycles (one comparison + a
branch) are cheap insurance against a mis-typed pk silently wrapping
as a plain object and then failing cryptically on a `:locals()` call.

Once the design settles and the callers are all provably-correct,
this can be relaxed. Not yet.
]]
function cvm:frame_by_pk(pk)
	local obj = self:object_by_pk(pk)

	if obj == nil then
		error("frame_by_pk_not_found: no objects row with pk " .. tostring(pk))
	end

	if obj.primitive ~= 'f' then
		error(
			"frame_by_pk_not_a_frame: pk " .. tostring(pk) ..
			" has primitive '" .. tostring(obj.primitive) .. "', expected 'f'"
		)
	end

	return obj
end

--[[
## `add_bucket` — INSERT a bucket, return its pk

INSERTs a HashPrimitive as the bucket for a given owner and returns
the new bucket's `object_pk`. Used by `object:bucket` as the lazy-
create branch of the object's `bucket` accessor.

**Derives `owner_role` from the target.** The `insert ... select`
reads the `owner_role` off the target row and uses it for the new
bucket. Callers don't pass an owner_role; the bucket naturally
inherits the ownership of the object it's a bucket for.

**Uses SQLite `RETURNING`** to hand the new bucket's `object_pk` back
in the same round trip. The pk is generated by the default expression
on `objects.object_pk` (a UUID via `randomblob`); RETURNING captures
it as it lands.

**Also fires the `objects_denormalize_bucket` trigger** inside the
same statement. The trigger updates the target row's `bucket_pk`
column to the new bucket's `object_pk` — the value RETURNING gives
back equals what the target's `bucket_pk` becomes. Callers don't have
to re-read the target row to learn its new `bucket_pk`.
]]
function cvm:add_bucket(for_object_pk)
	local stmt = self.stmt_add_bucket
	stmt:bind_values(for_object_pk)
	stmt:step()
	local bucket_pk = stmt:get_value(0)
	stmt:reset()
	return bucket_pk
end

--[[
## `add_stack` — INSERT a stack, return its pk

Parallel to `add_bucket`, on the array side. INSERTs an ArrayPrimitive
as the stack for a given owner and returns the new stack's `object_pk`.
Used by `object:stack` as the lazy-create branch of the stack accessor.

Same shape as `add_bucket`:

- `insert ... select` reads `owner_role` off the target row.
- `RETURNING object_pk` hands the new pk back in the same round trip.
- The `objects_denormalize_stack` trigger fires inside the same
  statement and sets the target row's `stack_pk` column.
]]
function cvm:add_stack(for_object_pk)
	local stmt = self.stmt_add_stack
	stmt:bind_values(for_object_pk)
	stmt:step()
	local stack_pk = stmt:get_value(0)
	stmt:reset()
	return stack_pk
end

--[[
## `add_scalar` — INSERT a scalar objects row, return its pk

Creates a scalar objects row (`primitive = 'o'`, `scalar_type` and
`scalar_value` set) owned by the caller-supplied role. Returns the new
row's `object_pk` via `RETURNING`.

Used by `frame:set_local_to_scalar` and any other write path that
materializes a primitive value inside the object graph.
]]
function cvm:add_scalar(scalar_type, scalar_value, owner_role_pk)
	local stmt = self.stmt_add_scalar
	stmt:bind_values(scalar_type, scalar_value, owner_role_pk)
	stmt:step()
	local scalar_pk = stmt:get_value(0)
	stmt:reset()
	return scalar_pk
end

--[[
## `add_hash` — INSERT a standalone HashPrimitive, return its pk

Creates a plain HashPrimitive (`primitive = 'h'`) owned by the given
role, with no `bucket_for` set. This is the "just a hash" case —
distinct from `add_bucket`, which creates a HashPrimitive AS an
object's bucket via the `bucket_for` FK.

Used by `frame:ensure_locals` when the locals hash needs to be
materialized on first assignment.
]]
function cvm:add_hash(owner_role_pk)
	local stmt = self.stmt_add_hash
	stmt:bind_values(owner_role_pk)
	stmt:step()
	local hash_pk = stmt:get_value(0)
	stmt:reset()
	return hash_pk
end

--[[
## `add_array` — INSERT a standalone ArrayPrimitive, return its pk

Parallel to `add_hash`, on the array side. Creates a plain
ArrayPrimitive (`primitive = 'a'`) owned by the given role, with no
`stack_for` set — a standalone array, not any object's stack.

Same shape as `add_hash`: one INSERT with `RETURNING object_pk`.
]]
function cvm:add_array(owner_role_pk)
	local stmt = self.stmt_add_array
	stmt:bind_values(owner_role_pk)
	stmt:step()
	local array_pk = stmt:get_value(0)
	stmt:reset()
	return array_pk
end

--[[
## `add_frame` — INSERT a frame row, return its pk

INSERTs an `objects` row with `primitive = 'f'` and the frame's stack
coordinates: `ast` (the CaspM tree the frame will dispatch), `process`
(the process pk this frame belongs to, if it's frame 0 — sub-frames
carry `frame_parent` instead), and `stmt_idx = 0` (starting at the
first statement). `owner_role` is caller-supplied.

Push-a-frame semantics (which pk goes in `process` vs `frame_parent`,
transaction wrapping, etc.) belong in the runtime layer above this
method — `create_frame_0.lua` for the fresh-case flow, similar for
sub-frame pushes when those land.

**Set by the write path elsewhere.** `bucket_pk` and `stack_pk` are
not set here — a frame that ends up needing locals materializes its
bucket lazily via `object:bucket`, same as any other bucket owner.
]]
function cvm:add_frame(ast, process_pk, owner_role_pk)
	local stmt = self.stmt_add_frame
	stmt:bind_values(ast, process_pk, owner_role_pk)
	stmt:step()
	local frame_pk = stmt:get_value(0)
	stmt:reset()
	return frame_pk
end

--[[
## `add_ref` — INSERT a ref row, return its ref_pk

Inserts a row into `refs` binding `key` to `child_pk` under `parent_pk`.
The `idx` column (insertion order for hash iteration) is auto-computed
via `coalesce((select max(idx) + 1 from refs where parent = ?1), 0)` —
first ref for a given parent gets `idx = 0`, subsequent ones increment.

Uses `RETURNING ref_pk` to hand the new ref's autoincrement pk back in
the same round trip.
]]
function cvm:add_ref(parent_pk, key, child_pk)
	local stmt = self.stmt_add_ref
	stmt:bind_values(parent_pk, child_pk, key)
	stmt:step()
	local ref_pk = stmt:get_value(0)
	stmt:reset()
	return ref_pk
end

--[[
## `get_ref_child` — look up a ref's child by (parent, key)

Returns the `child` object_pk for the ref with the given `parent` and
`key`, or `nil` if no such ref exists. The `unique (parent, key)`
schema constraint guarantees at most one match.

Used wherever the engine needs a hash-lookup by key — `frame:ensure_locals`
checks whether `bucket['locals']` exists via this method, and any read
path for `$var` in a locals hash will use it too.
]]
function cvm:get_ref_child(parent_pk, key)
	local stmt = self.stmt_get_ref_child
	stmt:bind_values(parent_pk, key)
	local child_pk

	if stmt:step() == SQLITE_ROW then
		child_pk = stmt:get_value(0)
	end

	stmt:reset()
	return child_pk
end

return cvm
