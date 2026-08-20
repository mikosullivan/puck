--[[
{
	"module": "frame",
	"role": "Class attached to `objects` rows with `primitive = 'f'`. Under the scopes design (see requirements/cvm/sqlite/scopes), the frame's bucket holds a `scopes` key pointing at an ArrayPrimitive; scopes[0] is the frame's own locals hash for this call, scopes[1..] are captured scopes from closures (once those land). Adds `own_scope` (read-only accessor for scopes[0]), `ensure_own_scope` (get-or-create), and `set_local_to_scalar` (specialized write path for `$name = <scalar>` assignments).",
	"inherits_from": "object",
	"exports": {
		"new":                 "(engine, row) -> frame — constructor",
		"own_scope":           "() -> object — the frame's own scope hash (scopes[0]); nil if not yet created (read-only)",
		"ensure_own_scope":    "() -> object — the frame's own scope hash, materializing bucket → scopes → scopes[0] on first call",
		"set_local_to_scalar": "(name, scalar_type, scalar_value) — specialized write path for `$name = <primitive scalar>`"
	},
	"depends_on": ["cvm.object", "lsqlite3 (for SQLITE_ROW)"],
	"status": "V0.1"
}
]]

--[[
# Frame

The class attached to every `objects` row with `primitive = 'f'` — a frame, an instance of a call. Distinct from a function or closure: those are plain `primitive = 'o'` objects that store their CaspM in a bucket entry. When one is called, the engine creates a fresh `primitive = 'f'` row and copies the CaspM into its `ast` column. The function object stays where it is; the frame is a separate row with the code it's actually running.

Frames are destroyed when finished — the walker's advance-with-gc UPDATE cascade-sweeps any child (marker or completed nested call); when a frame's own ast is exhausted its parent's next advance cascade-sweeps it in turn. See [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle) for the full walkthrough. Closures capture the locals hash directly (not the frame).

**Scopes.** The frame's bucket holds a `scopes` key pointing at an ArrayPrimitive:

- `scopes[0]` — this frame's OWN scope hash. Where `set_local_to_scalar` writes.
- `scopes[1]`, `scopes[2]`, ... — captured scopes from an enclosing closure, if any.

`own_scope` / `ensure_own_scope` deal specifically with scopes[0]. Multi-scope lookup (walk from scopes[0] outward for variable resolution) lands with the closure work.

Inherits from `object` — picks up the `bucket` accessor for free.
]]
local sqlite = require('lsqlite3')
local object = require("cvm.sqlite.object")

-- Cached at module load; avoids a `sqlite.ROW` global lookup per step check.
local SQLITE_ROW = sqlite.ROW


local frame = setmetatable({}, {__index = object})
frame.__index = frame

--[[
## Constructing a frame

`frame.new(engine, row)` uses `object._wrap` — the shared row-as-instance helper — with `frame` as the metatable. Going through `_wrap` (rather than calling `object.new`) skips `object.new`'s primitive-based dispatch, so a frame row loaded via `engine:object_by_pk` doesn't recurse into `object.new → frame.new → object.new → …`.
]]
function frame.new(engine, row)
	if row.primitive ~= 'f' then
		error(
			"frame_new_not_a_frame_row: expected primitive='f', got '" ..
			tostring(row.primitive) .. "' (pk " ..
			tostring(row.object_pk) .. ")"
		)
	end

	return object._wrap(frame, engine, row)
end

--[[
## `_get_array_child_at` — internal helper: array element by idx

Looks up the child of the ref where `parent = ?` and `idx = ?`. Sprint-scoped inline SQL; if the array-by-idx access pattern proves permanent, this belongs on the engine as a prepared statement (`cvm.get_ref_child_by_idx`) alongside the existing `get_ref_child`.
]]
local function _get_array_child_at(db, parent_pk, idx)
	local stmt = db:prepare('select child from refs where parent = ? and idx = ?')
	stmt:bind_values(parent_pk, idx)

	local child_pk

	if stmt:step() == SQLITE_ROW then
		child_pk = stmt:get_value(0)
	end

	stmt:finalize()

	return child_pk
end

--[[
## `own_scope` — the frame's own scope hash (read-only)

Returns the hash at `scopes[0]` — the frame's own locals for this call. `nil` if the scopes chain hasn't been created yet.

Path: bucket → `'scopes'` (ArrayPrimitive) → idx=0 (HashPrimitive).

**Read-only.** `own_scope` doesn't create anything — it only returns whatever's at the end of the chain. On a fresh frame, before anything has been assigned, the chain doesn't exist yet and this returns `nil`. For the get-or-create variant, see `ensure_own_scope`.

**Wrapper memoized on `self._own_scope`.** The scope hash's identity never changes once it exists — the ref at scopes[0] is immutable and points at one specific hash forever — so the wrapper is cached on first successful return. `ensure_own_scope` writes into the same cache field, so calling one after the other doesn't re-run the fetch.
]]
function frame:own_scope()
	local own = self._own_scope
	if own then return own end

	local engine = self.engine
	local bucket = self:bucket()

	local scopes_pk = engine:get_ref_child(bucket.object_pk, 'scopes')
	if not scopes_pk then return nil end

	local own_pk = _get_array_child_at(engine.db, scopes_pk, 0)
	if not own_pk then return nil end

	own = engine:object_by_pk(own_pk)
	self._own_scope = own

	return own
end

--[[
## `ensure_own_scope` — get-or-create the frame's own scope hash

Returns the frame's own scope hash (scopes[0]), materializing the chain on first call:

1. Get or create the frame's `scopes` ArrayPrimitive, hung off the bucket under key `'scopes'`.
2. Get or create the own scope HashPrimitive at `scopes[0]` (array append with the first entry lands at idx 0).

Idempotent — subsequent calls short-circuit through `self._own_scope`.
]]
function frame:ensure_own_scope()
	local own = self._own_scope
	if own then return own end

	local engine = self.engine
	local bucket = self:bucket()
	local bucket_pk = bucket.object_pk

	-- Get or create the scopes array.
	local scopes_pk = engine:get_ref_child(bucket_pk, 'scopes')
	if not scopes_pk then
		scopes_pk = engine:add_array(self.owner_role)
		engine:add_ref(bucket_pk, 'scopes', scopes_pk)
	end

	-- Get or create the own_scope hash at scopes[0].
	local own_pk = _get_array_child_at(engine.db, scopes_pk, 0)
	if not own_pk then
		own_pk = engine:add_hash(self.owner_role)
		-- Array-style append: key=nil, idx auto-computed. First entry lands at idx=0.
		engine:add_ref(scopes_pk, nil, own_pk)
	end

	own = engine:object_by_pk(own_pk)
	self._own_scope = own

	return own
end

--[[
## `set_local_to_scalar` — specialized routine for `$name = <scalar>`

Writes a fresh binding to the frame's own scope (scopes[0]) and marks the current frame `gc = 1`. All atomic inside `SAVEPOINT set_local_to_scalar`.

Four composed writes:

1. `engine:add_scalar(scalar_type, scalar_value, self.owner_role)` — materialize the scalar.
2. `self:ensure_own_scope()` — get-or-create bucket → scopes → scopes[0].
3. `engine:upsert_ref(own_scope.object_pk, name, scalar_pk)` — bind (or rebind) the variable name to the scalar in the own scope hash. On rebind the schema's after-update mark trigger inserts the old child into `needs_trace` so the walker's drain can sweep it.
4. `engine:mark_frame_gc(self.object_pk)` — set the current frame's `gc = 1`. That flag IS the mid-dispatch signal; the walker's next tick runs the GC pass before advancing. No child marker row is created — the earlier "push an empty child frame" pattern is retired under the current cycle.

**Rebind supported.** The upsert path lets `$x = 2` on top of an existing `$x = 1` land as a single UPDATE of the existing ref's `child` column. The old scalar goes into `needs_trace` via the after-update mark trigger, the walker's drain sweeps it, and the ref now points at the new scalar.

**Long name deliberate.** `set_local` or `assign` would be inviting call sites to reach for this method when their RHS isn't actually a primitive scalar. `set_local_to_scalar` signals the specialization at the point of use.
]]
function frame:set_local_to_scalar(name, scalar_type, scalar_value)
	local db = self.engine.db

	db:exec('savepoint set_local_to_scalar;')

	local ok, err = pcall(function()
		local scalar_pk = self.engine:add_scalar(scalar_type, scalar_value, self.owner_role)
		local own_scope = self:ensure_own_scope()
		self.engine:upsert_ref(own_scope.object_pk, name, scalar_pk)

		-- Mark the current frame as mid-dispatch. Set last so a
		-- resume-mid-savepoint can't observe gc=1 without the writes
		-- it signals. The walker's next tick sees gc=1 and runs its
		-- GC pass before advancing stmt_idx.
		self.engine:mark_frame_gc(self.object_pk)
	end)

	if not ok then
		db:exec('rollback to savepoint set_local_to_scalar;')
		db:exec('release savepoint set_local_to_scalar;')
		error(err)
	end

	db:exec('release savepoint set_local_to_scalar;')
end

return frame
