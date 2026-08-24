--[[
{
	"module": "obj",
	"role": "Lua-side implementation of the `.obj` agent — the sub-object every Caspian value returns when `.obj` is called on it. Inherits from `object`; provides the constructor that materializes the agent's row in the CVM (engine_class='obj') along with its bucket and a `target` ref back at the parent object. Method bodies for the `.obj.*` namespace catalog (truthy?, classes, id, jail, etc.) will attach to this module over subsequent passes.",
	"exports": {
		"new": "(engine, target_pk) -> obj wrapper — inserts the agent row + bucket + target ref in one savepoint, returns a Lua handle carrying the agent's pk"
	},
	"depends_on": ["object"],
	"status": "sketch — constructor + row materialization land; catalog methods still to come"
}
]]

--[[
# obj (the .obj agent)

Lua-side implementation of the agent Caspian returns from `$foo.obj`.
Every `.obj` access constructs a fresh agent (per the spec at
[built-in-classes/object/methods](https://puck.uno/requirements/built-in-classes/object/methods/) —
"Fresh per access, no caching"), so this constructor runs often.

**Row shape.** The agent is an ordinary `objects` row with
`engine_class = 'obj'`. The dispatcher, when it sees a method call
on a row with engine_class set, consults the Lua module registered
under that name — this module — for method resolution. No platters,
no shadow.

**Bucket.** Small, one entry:

- `target` → the parent object being agented for.

`target` lives in the agent's bucket as a keyed ref. Method bodies
that need to reach the parent read it via `self.db:nrows("select
child from refs where parent = ? and key = 'target'")` (or the
equivalent through a helper).

**Owner.** Agent + bucket inherit `owner_role` from the target — the
agent belongs to whoever the target belongs to.

**Atomicity.** The four inserts (agent row, bucket row, agent → bucket
ref keyed 'b', bucket → target ref keyed 'target') land inside a
single savepoint. Either the agent is fully wired or nothing gets
written.
]]

local object = require('object')

local obj = setmetatable({}, {__index = object})
obj.__index = obj

--[[
## Constructor

`obj.new(engine, target_pk)` materializes a fresh agent for the object
identified by `target_pk` under the given `engine`, and returns a Lua
wrapper carrying the agent's pk.

Steps, all inside one savepoint:

1. Look up the target's `owner_role` (agent + bucket inherit it).
2. Insert the agent row: `base='o'`, `engine_class='obj'`,
   `owner_role` from step 1.
3. Insert the bucket row: `base='h'`, same owner_role.
4. Link bucket to agent: refs row `(agent_pk, bucket_pk, 'b', 0)`.
5. Link target to bucket: refs row `(bucket_pk, target_pk, 'target', 0)`.

Missing target (no row with the given pk) raises `obj_new_target_missing`.
Any DB failure inside the savepoint rolls the whole thing back and
re-raises with the underlying sqlite error message.
]]
function obj.new(engine, target_pk)
	local db = engine.cvm

	-- Look up the target's owner_role. Also confirms the target exists.
	local target_owner
	for row in db:nrows("select owner_role from objects where object_pk = '" .. target_pk .. "'") do
		target_owner = row.owner_role
	end

	if not target_owner then
		error("obj_new_target_missing: no objects row with pk '" .. tostring(target_pk) .. "'")
	end

	assert(db:exec('savepoint obj_new;') == 0, db:errmsg())

	local ok, agent_pk_or_err = pcall(function()
		local agent_pk

		for row in db:nrows(
			"insert into objects (base, engine_class, owner_role) "
			.. "values ('o', 'obj', '" .. target_owner .. "') "
			.. "returning object_pk"
		) do
			agent_pk = row.object_pk
		end

		local bucket_pk

		for row in db:nrows(
			"insert into objects (base, owner_role) "
			.. "values ('h', '" .. target_owner .. "') "
			.. "returning object_pk"
		) do
			bucket_pk = row.object_pk
		end

		assert(db:exec(
			"insert into refs (parent, child, key, idx) "
			.. "values ('" .. agent_pk .. "', '" .. bucket_pk .. "', 'b', 0)"
		) == 0, db:errmsg())

		assert(db:exec(
			"insert into refs (parent, child, key, idx) "
			.. "values ('" .. bucket_pk .. "', '" .. target_pk .. "', 'target', 0)"
		) == 0, db:errmsg())

		return agent_pk
	end)

	if not ok then
		db:exec('rollback to savepoint obj_new;')
		db:exec('release savepoint obj_new;')
		error(agent_pk_or_err)
	end

	assert(db:exec('release savepoint obj_new;') == 0, db:errmsg())

	return setmetatable({
		pk     = agent_pk_or_err,
		engine = engine,
		db     = db,
	}, obj)
end


return obj
