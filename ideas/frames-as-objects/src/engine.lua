--[[
{
	"module": "engine",
	"role": "Top-level runtime that drives a CVM. One engine per open DB connection. Owns the SQLite handle, tracks the current process, dispatches frames on that process's stack, and shuts down when nothing is left to run. Sits above `object` and `frame` — the engine constructs them and calls their methods rather than being one itself.",
	"exports": {
		"new":           "(db) -> engine — constructor; binds an lsqlite3 handle",
		"object_by_pk":  "(pk) -> object — canonical pk-to-object load; nil if no row",
		"add_bucket":    "(for_object_pk) -> new bucket's object_pk — INSERTs a HashPrimitive owned by the target's owner_role",
		"add_scalar":    "(scalar_type, scalar_value, owner_role_pk) -> new scalar's object_pk",
		"add_hash":      "(owner_role_pk) -> new HashPrimitive's object_pk — plain hash, no bucket_for set",
		"add_ref":       "(parent_pk, key, child_pk) -> new ref_pk — auto-computes the next idx for parent",
		"get_ref_child": "(parent_pk, key) -> child object_pk or nil — hash lookup by key"
	},
	"policy": "Engine DB access goes through dedicated per-statement methods only — no ad-hoc db:exec / db:nrows / db:prepare. Each cached SQL is its own method on the engine class; each method lazily preps and caches its prepared statement on the instance.",
	"performance": "Every method on this class runs on hot paths — most fire on every statement dispatch — and any cycle saved multiplies across the whole running program.",
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# Engine

The top-level runtime that drives a CVM. One engine per open DB
connection. Owns the SQLite handle, tracks the current process,
dispatches frames on that process's stack, and shuts down when nothing
is left to run. Sits above `object` and `frame` — constructs them and
calls their methods rather than being one of them.

**Policy: DB access via cached-statement methods only.** No ad-hoc
`db:exec`, no inline `db:nrows`, no `db:prepare` scattered through
engine code. Each SQL the engine needs is its own method on the engine
class, and each of those methods lazily caches its prepared statement
on the instance. The rule buys reuse (every SQL prepared once per
instance), one source of truth per statement (each SQL lives in
exactly the method that returns its prepared handle), and testable-
in-isolation methods (each can be called on a fresh engine against a
test DB with no cross-statement setup).

**Every method on this page must be as efficient as possible** — these
are hot paths, most run on every statement dispatch, and any cycle
saved multiplies out across the whole running program.
]]

local object = require("object")

local engine = {}
engine.__index = engine

--[[
## Constructing an engine

`engine.new(db)` takes an already-open lsqlite3 handle — with
`foreign_keys` and `recursive_triggers` pragmas already enabled per the
CVM's per-connection rules — and wraps it as an engine instance. Each
cached-statement method (`object_by_pk`, `add_bucket`, ...) lazily
populates its own `self.stmt_<name>` field on first use, so there's
nothing to preallocate here.
]]
function engine.new(db)
	local self = setmetatable({}, engine)
	self.db = db
	return self
end

--[[
## `object_by_pk` — canonical pk-to-object load

Takes a primary key and returns the corresponding objects row wrapped
as an object. `nil` if no row exists for that pk.

Caller-side:

    local obj = engine:object_by_pk(pk)

The lazy-prepare + bind + iterate + reset dance lives inside the
method. `stmt:reset()` runs on every call — required by lsqlite3 for
reusable prepared statements, without it the next `bind_values` on the
same handle raises.

**Cache field: `self.stmt_object_by_pk`.** First call preps and stores;
subsequent calls skip that block and go straight to bind. The `stmt_`
prefix keeps the field name from colliding with the method itself.

`object.new(self, row)` wraps the row as an object instance —
dispatch to the right class (HashPrimitive, ArrayPrimitive, scalar)
and any per-pk caching live inside `object.new` itself.
]]
function engine:object_by_pk(pk)
	if not self.stmt_object_by_pk then
		self.stmt_object_by_pk = self.db:prepare(
			"select * from objects where object_pk = ?"
		)
	end

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

**Cache field: `self.stmt_add_bucket`.** Same lazy-prepare pattern as
`object_by_pk` — one INSERT with SELECT + RETURNING gets parsed once
per engine instance and reused across every bucket creation
thereafter.
]]
function engine:add_bucket(for_object_pk)
	if not self.stmt_add_bucket then
		self.stmt_add_bucket = self.db:prepare(
			"insert into objects (primitive, bucket_for, owner_role) " ..
			"select 'h', ?1, owner_role from objects where object_pk = ?1 " ..
			"returning object_pk"
		)
	end

	local stmt = self.stmt_add_bucket
	stmt:bind_values(for_object_pk)
	local bucket_pk

	for r in stmt:nrows() do
		bucket_pk = r.object_pk
	end

	stmt:reset()
	return bucket_pk
end

--[[
## `add_scalar` — INSERT a scalar objects row, return its pk

Creates a scalar objects row (`primitive = 'o'`, `scalar_type` and
`scalar_value` set) owned by the caller-supplied role. Returns the new
row's `object_pk` via `RETURNING`.

Used by `frame:set_local_to_scalar` and any other write path that
materializes a primitive value inside the object graph.

Cache field: `self.stmt_add_scalar`.
]]
function engine:add_scalar(scalar_type, scalar_value, owner_role_pk)
	if not self.stmt_add_scalar then
		self.stmt_add_scalar = self.db:prepare(
			"insert into objects (primitive, scalar_type, scalar_value, owner_role) " ..
			"values ('o', ?, ?, ?) returning object_pk"
		)
	end

	local stmt = self.stmt_add_scalar
	stmt:bind_values(scalar_type, scalar_value, owner_role_pk)
	local scalar_pk

	for r in stmt:nrows() do
		scalar_pk = r.object_pk
	end

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

Cache field: `self.stmt_add_hash`.
]]
function engine:add_hash(owner_role_pk)
	if not self.stmt_add_hash then
		self.stmt_add_hash = self.db:prepare(
			"insert into objects (primitive, owner_role) values ('h', ?) returning object_pk"
		)
	end

	local stmt = self.stmt_add_hash
	stmt:bind_values(owner_role_pk)
	local hash_pk

	for r in stmt:nrows() do
		hash_pk = r.object_pk
	end

	stmt:reset()
	return hash_pk
end

--[[
## `add_ref` — INSERT a ref row, return its ref_pk

Inserts a row into `refs` binding `key` to `child_pk` under `parent_pk`.
The `idx` column (insertion order for hash iteration) is auto-computed
via `coalesce((select max(idx) + 1 from refs where parent = ?1), 0)` —
first ref for a given parent gets `idx = 0`, subsequent ones increment.

Uses `RETURNING ref_pk` to hand the new ref's autoincrement pk back in
the same round trip.

Cache field: `self.stmt_add_ref`.
]]
function engine:add_ref(parent_pk, key, child_pk)
	if not self.stmt_add_ref then
		self.stmt_add_ref = self.db:prepare(
			"insert into refs (parent, child, key, idx) " ..
			"values (?1, ?2, ?3, coalesce((select max(idx) + 1 from refs where parent = ?1), 0)) " ..
			"returning ref_pk"
		)
	end

	local stmt = self.stmt_add_ref
	stmt:bind_values(parent_pk, child_pk, key)
	local ref_pk

	for r in stmt:nrows() do
		ref_pk = r.ref_pk
	end

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

Cache field: `self.stmt_get_ref_child`.
]]
function engine:get_ref_child(parent_pk, key)
	if not self.stmt_get_ref_child then
		self.stmt_get_ref_child = self.db:prepare(
			"select child from refs where parent = ? and key = ?"
		)
	end

	local stmt = self.stmt_get_ref_child
	stmt:bind_values(parent_pk, key)
	local child_pk

	for r in stmt:nrows() do
		child_pk = r.child
	end

	stmt:reset()
	return child_pk
end

return engine
