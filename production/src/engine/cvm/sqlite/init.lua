--[[
{
	"module": "cvm",
	"role": "Data-access layer for a CVM connection. Owns the SQLite handle, preps every statement upfront, and exposes cached-statement methods (object_by_pk, frame_by_pk, plus the add_* / get_* family) so callers work in objects/pks rather than raw SQL. Sits above `object` and `frame` — the CVM constructs them today; whether it will also call into them, and how, is still open (see the 'Open questions' block in the docstring). Not to be confused with the top-level Caspian runtime at `src/engine/engine.lua`; this file is the CVM's internal object-store, required as `require('cvm.sqlite')`.",
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
		"upsert_ref":    "(parent_pk, key, child_pk) -> ref_pk — insert OR update on conflict (parent, key); on update, the schema's after-update mark trigger inserts the old child into needs_trace",
		"get_ref_child": "(parent_pk, key) -> child object_pk or nil — hash lookup by key",
		"mark_frame_gc": "(object_pk) — sets gc=1 on the frame; the mid-dispatch signal for the walker's next GC pass",
		"drain_needs_trace": "(process_pk) — sweeps every needs_trace mark for process_pk. Each marked object is either unmarked (still reachable — in uspace or has an incoming ref) or reaped (unreachable — no incoming refs; DELETE cascades outgoing refs, which fire the mark trigger on their children). Loops until the worklist is empty."
	},
	"policy": "CVM DB access goes through dedicated per-statement methods only — no ad-hoc db:exec / db:nrows / db:prepare. Each cached SQL is its own method on the cvm class. Every statement the cvm uses is prepared upfront in cvm.new(); methods just fetch the cached handle, bind, execute, reset. Single-column reads use stmt:step + stmt:get_value(0) to skip nrows()'s per-row table allocation; full-row reads (object_by_pk) stay on nrows() so callers get every column at once.",
	"performance": "Every method on this class is on a hot path. Once the dispatch loop lands (see the open questions in the docstring), most will fire on every statement dispatch; any cycle saved multiplies across the whole running program.",
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# CVM (data-access layer)

The data-access layer for a CVM connection — required as `require('cvm.sqlite')`
(this file is `src/engine/cvm/sqlite/init.lua`, so Lua's require system
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
local object = require("cvm.sqlite.object")

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

	-- add_bucket / add_stack: insert a bare hash / array with the
	-- target's owner_role, then link via a refs row. See the method
	-- bodies below. Under the ownership-via-refs design, the collection
	-- has no back-reference to its owner — the whole link lives in refs.
	self.stmt_add_bucket_insert = db:prepare(
		"insert into objects (primitive, owner_role) " ..
		"select 'h', owner_role from objects where object_pk = ? " ..
		"returning object_pk"
	)

	self.stmt_add_stack_insert = db:prepare(
		"insert into objects (primitive, owner_role) " ..
		"select 'a', owner_role from objects where object_pk = ? " ..
		"returning object_pk"
	)

	-- Existing-child lookups for add_bucket / add_stack — if the owner
	-- already has a hash-child (its bucket) or an array-child (its stack)
	-- we return that rather than inserting a duplicate (which the
	-- refs_owner_at_most_one_hash_and_one_array trigger would reject).
	self.stmt_find_hash_child = db:prepare(
		"select r.child from refs r " ..
		"join objects c on c.object_pk = r.child " ..
		"where r.parent = ? and c.primitive = 'h'"
	)

	self.stmt_find_array_child = db:prepare(
		"select r.child from refs r " ..
		"join objects c on c.object_pk = r.child " ..
		"where r.parent = ? and c.primitive = 'a'"
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

	-- add_frame: bare frame insert. Callers wire up the anchor
	-- (parent_frame for nested; process=1 for a cap) separately.
	self.stmt_add_frame = db:prepare(
		"insert into objects (primitive, ast, stmt_idx, owner_role) " ..
		"values ('f', ?, 0, ?) returning object_pk"
	)

	self.stmt_add_ref = db:prepare(
		"insert into refs (parent, child, key, idx) " ..
		"values (?1, ?2, ?3, coalesce((select max(idx) + 1 from refs where parent = ?1), 0)) " ..
		"returning ref_pk"
	)

	-- upsert_ref: insert a hash ref, OR update its child if a ref with
	-- the same (parent, key) already exists. On update, the trigger
	-- `refs_mark_needs_trace_after_child_update` inserts the old child
	-- into needs_trace so GC can reason about it later. Same idx-
	-- computation clause as add_ref — redundant on the conflict branch
	-- (idx isn't mutated) but keeps the insert path correct.
	self.stmt_upsert_ref = db:prepare(
		"insert into refs (parent, child, key, idx) " ..
		"values (?1, ?2, ?3, coalesce((select max(idx) + 1 from refs where parent = ?1), 0)) " ..
		"on conflict(parent, key) do update set child = excluded.child " ..
		"returning ref_pk"
	)

	self.stmt_get_ref_child = db:prepare(
		"select child from refs where parent = ? and key = ?"
	)

	self.stmt_mark_frame_gc = db:prepare(
		"update objects set gc = 1 where object_pk = ?"
	)

	-- drain_needs_trace: the four prepared statements the drain loop
	-- issues per marked object. `list_marks` pulls every mark for a
	-- given process; the drain then iterates and, per object, checks
	-- (a) uspace membership and (b) incoming refs to decide unmark vs
	-- reap. See drain_needs_trace() below.
	self.stmt_list_marks = db:prepare(
		"select object_pk from needs_trace where process_pk = ?"
	)
	self.stmt_object_in_uspace = db:prepare(
		"select 1 from uspace where object_pk = ?"
	)
	self.stmt_object_has_incoming_ref = db:prepare(
		"select 1 from refs where child = ? limit 1"
	)
	self.stmt_unmark_needs_trace = db:prepare(
		"delete from needs_trace where process_pk = ? and object_pk = ?"
	)
	self.stmt_reap_object = db:prepare(
		"delete from objects where object_pk = ?"
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
## `add_bucket` — get-or-create the owner's bucket, return its pk

Returns the given owner's bucket — the one HashPrimitive that owner
holds as a refs child. If the owner already has a hash-child, returns
that pk (calling `add_bucket` twice on the same owner is idempotent).
Otherwise: INSERT a plain HashPrimitive with the owner's `owner_role`,
add a `refs` row linking owner → bucket (key null; the child's
primitive disambiguates bucket from stack), return the new pk.

Ownership under the current schema is a normal refs row from owner to
collection — no dedicated `bucket_pk` / `bucket_for` columns. The
`refs_owner_at_most_one_hash_and_one_array` trigger caps a
non-container parent at one hash-child. See
[ownership](https://puck.uno/requirements/cvm/sqlite/ownership).

Used by `object:bucket` as the lazy-create branch of the accessor.
]]
function cvm:add_bucket(for_object_pk)
	-- Return existing hash-child if any.
	local find = self.stmt_find_hash_child
	find:bind_values(for_object_pk)

	local existing

	if find:step() == SQLITE_ROW then
		existing = find:get_value(0)
	end

	find:reset()
	if existing then return existing end

	-- Otherwise insert a bare hash and link via refs.
	local insert = self.stmt_add_bucket_insert
	insert:bind_values(for_object_pk)
	insert:step()
	local bucket_pk = insert:get_value(0)
	insert:reset()

	self:add_ref(for_object_pk, nil, bucket_pk)

	return bucket_pk
end

--[[
## `add_stack` — get-or-create the owner's stack, return its pk

Parallel to `add_bucket`, on the array side. Returns the owner's one
array-child ref (its stack) if present; otherwise inserts an
ArrayPrimitive with the owner's `owner_role`, links via refs, and
returns the new pk. Idempotent per owner.
]]
function cvm:add_stack(for_object_pk)
	local find = self.stmt_find_array_child
	find:bind_values(for_object_pk)

	local existing

	if find:step() == SQLITE_ROW then
		existing = find:get_value(0)
	end

	find:reset()
	if existing then return existing end

	local insert = self.stmt_add_stack_insert
	insert:bind_values(for_object_pk)
	insert:step()
	local stack_pk = insert:get_value(0)
	insert:reset()

	self:add_ref(for_object_pk, nil, stack_pk)

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

INSERTs a bare `objects` row with `primitive = 'f'`, `stmt_idx = 0`,
the given `ast` and `owner_role`. Callers wire up the frame's anchor
after the fact — either `parent_frame = <parent>` for a nested frame
(via a follow-up UPDATE) or `process = 1` for a cap frame at the top
of a call stack. See [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle)
and [ownership](https://puck.uno/requirements/cvm/sqlite/ownership) for the
lifecycle rules.
]]
function cvm:add_frame(ast, owner_role_pk)
	local stmt = self.stmt_add_frame
	stmt:bind_values(ast, owner_role_pk)
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
## `upsert_ref` — INSERT a hash ref OR update its child if it already exists

Like `add_ref`, but if a ref with the same `(parent_pk, key)` already
exists the schema's UNIQUE constraint gets absorbed into an
`ON CONFLICT DO UPDATE SET child = excluded.child`. On the update
branch, the after-update mark trigger inserts the OLD child into
`needs_trace` so GC can decide what to do with it.

Used by the variable-scalar handler for rebinds like `$x = 2` on top
of an existing `$x = 1`. On first assignment this is behaviourally
identical to `add_ref`; on rebind it swaps the child without a
delete-then-insert round trip.

Returns the ref_pk in both branches via `RETURNING ref_pk`.
]]
function cvm:upsert_ref(parent_pk, key, child_pk)
	local stmt = self.stmt_upsert_ref
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

--[[
## `mark_frame_gc` — flag a frame as mid-dispatch (gc = 1)

Sets `gc = 1` on the target frame's objects row. The row-handler for
`$var = <scalar>` (and eventually other in-frame mutations) calls
this after its writes to signal that the frame is mid-dispatch and
the walker must run its GC pass before the next statement.

Replaces the older marker-frame pattern where the routine pushed an
empty child frame as the "mid-dispatch signal" — under the current
cycle, `gc = 1` on the frame itself carries that signal directly, no
scratch row needed.
]]
function cvm:mark_frame_gc(object_pk)
	local stmt = self.stmt_mark_frame_gc
	stmt:bind_values(object_pk)
	stmt:step()
	stmt:reset()
end

--[[
## `drain_needs_trace` — sweep every mark for a process, unmarking or reaping

Walks the current process's `needs_trace` worklist and, per marked
object, either unmarks (still reachable) or reaps (unreachable). Loops
until the process's worklist is empty. Runs the walking-skeleton's
stand-in for a proper reachability trace — cheap and correct for the
acyclic graphs the language can build today; the cycle case lands
with the real Bacon-Rajan trace-and-sweep pass in a later sprint.

**Per marked object:**

1. **Uspace check.** If the object appears in the `uspace` view (roles,
   `persistent = 1` rows, process caps), it's still anchored — unmark and
   move on.
2. **Incoming refs check.** If any `refs` row points at the object as
   `child`, someone still owns it — unmark and move on.
3. **Reap.** Otherwise the object is unreachable. DELETE the objects row.
   The schema's cascades take care of the fallout:
   - Outgoing refs (`parent = object_pk`) cascade-delete; each fires
     `refs_mark_needs_trace_after_delete`, adding fresh marks to the
     worklist for the reaped object's children.
   - The `needs_trace` row for this object cascade-deletes too
     (`object_pk` FK on delete cascade) — no explicit unmark needed.

The outer loop re-fetches the worklist after each pass so newly-added
marks from cascades are picked up. Convergence: every iteration either
reaps at least one row (strict progress toward empty) or unmarks all
remaining rows (also strict progress).

**Called by the walker** between each dispatched statement (so the
schema's `frames_gc_reset_requires_empty_needs_trace` guard doesn't
trip on the auto-null that fires with the advance) and after
`run_frame`'s tail reap (so the process's graph is fully swept before
the walker returns to its caller).

**Cycles are out of scope.** Two objects mutually referencing each
other with no external ref would both unmark under step 2 above,
leaving them alive as an unreachable pair. The walking-skeleton
grammar can't construct such a state; a real trace-and-sweep pass
lands when it can.
]]
function cvm:drain_needs_trace(process_pk)
	while true do
		-- Fetch the current worklist for this process.
		local list = self.stmt_list_marks
		list:bind_values(process_pk)

		local pks = {}

		for row in list:nrows() do
			table.insert(pks, row.object_pk)
		end

		list:reset()

		if #pks == 0 then break end

		for _, pk in ipairs(pks) do
			local reachable = false

			-- Uspace membership beats an incoming-ref check.
			local u = self.stmt_object_in_uspace
			u:bind_values(pk)

			if u:step() == SQLITE_ROW then
				reachable = true
			end

			u:reset()

			if not reachable then
				local r = self.stmt_object_has_incoming_ref
				r:bind_values(pk)

				if r:step() == SQLITE_ROW then
					reachable = true
				end

				r:reset()
			end

			if reachable then
				-- Unmark. The DELETE on needs_trace does not cascade
				-- to objects — the objects row stays where it is.
				local um = self.stmt_unmark_needs_trace
				um:bind_values(process_pk, pk)
				um:step()
				um:reset()
			else
				-- Reap. Deleting the objects row cascade-deletes its
				-- outgoing refs (each firing the after-delete mark on
				-- their children) and cascade-deletes the needs_trace
				-- row itself (via the object_pk FK).
				local rp = self.stmt_reap_object
				rp:bind_values(pk)
				rp:step()
				rp:reset()
			end
		end
	end
end

return cvm
