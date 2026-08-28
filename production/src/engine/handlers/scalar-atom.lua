--[[
{
	"module": "handlers.scalar-atom",
	"role": "Core handler for scalar-value atoms — CaspM rows of shape `[{v: LITERAL}]` (a one-element array whose head atom carries a single Caspian scalar). On match, materializes the literal as a scalar in the CVM, binds it as the currently-walking frame's `rv` (via the bucket's `rv` ref), and marks the frame's gc. The row shape a value-evaluation frame carries — e.g., the child frame under frame 0 that evaluates `[{v:1}]` for the RHS of `$x = 1`.",
	"exports": {
		"new":    "() -> ScalarAtom",
		"handle": "(frame, row, restart?) -> true when the row is `{v: X}`; false otherwise"
	},
	"depends_on": ["handler"],
	"status": "V0.1"
}
]]

--[[
# `handlers.scalar-atom`

Core handler for scalar-value atoms.

**Shape matched.** A CaspM row whose head atom is a value atom — `[{v: LITERAL}]`. Statement rows are uniformly arrays with a head atom at `row[1]` (method_call rows carry an envelope at `row[2]` too; value-atom rows are the one-element case). Examples of the matched shape: `[{v: 1}]`, `[{v: 'foo'}]`, `[{v: true}]`, `[{v: null_sentinel}]`. The literal can be any value the CVM's `add_scalar` accepts.

**Not matched.** Method_call rows (`[{cmd:'mc'}, envelope]`) — `row[1].v` is nil, decline. Other atom heads (`[{var: NAME}]`, `[{sys: NAME}]`) — no `v` key on `row[1]`, decline.

**On match.** Four committed side effects wrapped in a savepoint:

1. `data:add_scalar(literal, frame.owner_role)` — materialize the scalar in the CVM.
2. `data:add_bucket(frame.object_pk)` — ensure the frame has a bucket. Idempotent: returns the existing bucket if one exists.
3. `data:upsert_ref(bucket_pk, 'rv', scalar_pk)` — bind the bucket's `rv` slot to the scalar. This IS the frame's return value; when this frame reaps, `frames_child_delete_propagates_rv` copies the ref up to the parent's bucket.
4. `data:mark_frame_gc(frame.object_pk)` — flip `frame_gc = 1`. The walker's per-statement `advance` requires gc for the schema's `frames_advance_requires_gc` trigger to accept the increment.

**Why the savepoint.** Four separate writes; if any raises mid-sequence the savepoint rolls back the partial state, leaving the frame either fully-bound or untouched.

**Position in the stock chain.** After `ProcessStop` and before/after `MainHandler` — the row shapes don't overlap at `row[1]` (value atoms have `row[1].v`, method_calls have `row[1].cmd == 'mc'`), so ordering is cosmetic. Registered after `ProcessStop` in stock order (see [handlers/init.lua](init.lua)).
]]
local Handler = require('handler')


local ScalarAtom = setmetatable({}, {__index = Handler})
ScalarAtom.__index = ScalarAtom


function ScalarAtom.new()
	return setmetatable(Handler.new(), ScalarAtom)
end


--[[
## `set_rv_on_frame` — the four-write body

Materializes the value as a scalar, ensures the frame's bucket exists, binds the bucket's `rv` ref to the scalar, marks gc. All four inside a savepoint so a mid-write raise leaves no partial state.
]]
local function set_rv_on_frame(frame, value)
	local db   = frame.engine.cvm
	local data = frame.engine.data

	assert(db:exec('savepoint scalar_atom_set_rv;') == 0, db:errmsg())

	local ok, err = pcall(function()
		local scalar_pk = data:add_scalar(value, frame.owner_role)
		local bucket_pk = data:add_bucket(frame.object_pk)
		data:upsert_ref(bucket_pk, 'rv', scalar_pk)
		data:mark_frame_gc(frame.object_pk)
	end)

	if not ok then
		db:exec('rollback to savepoint scalar_atom_set_rv;')
		db:exec('release savepoint scalar_atom_set_rv;')
		error(err, 0)
	end

	assert(db:exec('release savepoint scalar_atom_set_rv;') == 0, db:errmsg())
end


--[[
## `ScalarAtom:handle` — match `[{v: X}]` and set rv

Row's head atom is a value atom when `row[1]` is a hash with a `v` key. Method_call rows have `row[1].cmd == 'mc'` (no `v` key), so they decline here.

On match, sets the frame's rv to the atom's literal and returns true.
]]
function ScalarAtom:handle(frame, row, restart)
	local head = row[1]

	if type(head) ~= 'table' or head.v == nil then
		return false
	end

	set_rv_on_frame(frame, head.v)

	return true
end


return ScalarAtom
