--[[
{
	"module": "obj",
	"role": "Lua-side implementation of the `.obj` agent — the sub-object every Caspian value returns when `.obj` is called on it. Inherits from `object`; provides the constructor that materializes the agent's row in the CVM (engine_class='obj') along with its bucket and a `target` ref back at the parent object. `obj.methods` holds Caspian-level catalog methods; the dispatcher calls `obj.methods[<name>](agent)` when the walk lands on the engine-class layer.",
	"exports": {
		"new":         "(engine, target_pk) -> obj wrapper — inserts the agent row + bucket + target ref in one savepoint, returns a Lua handle carrying the agent's pk",
		"methods":     "table of Caspian-level catalog methods on the agent",
		"methods.pk":  "(self) -> object_pk of a fresh scalar_string row whose value is the target's pk (a UUID). Reads the target via the agent's bucket, then INSERTs a scalar row whose scalar_string column carries the UUID and whose owner_role inherits from the target. Was previously called `.id` in the spec; renamed."
	},
	"depends_on": ["object"],
	"status": "sketch — constructor + row materialization land; first catalog method (.pk) attached"
}
]]

--[[
# obj (the .obj agent)

Lua-side implementation of the agent Caspian returns from `$foo.obj`.
Every `.obj` access constructs a fresh agent (per the spec at
[built-in-classes/object/methods](https://puck.uno/requirements/built-in-classes/object/methods/) —
"Fresh per access, no caching"), so this constructor runs often.

**Row shape.** The agent is an ordinary `objects` row with
`engine_class = 'obj'`. `engine_class` sits at the very bottom of the
dispatch chain (below the primitive class if one exists); the
dispatcher consults the Lua module registered under that name — this
module — after the shadow / platters / primitive-class walk fails to
resolve. Agents don't carry platters or a shadow today, so the walk
starts at the engine-class layer and ends there. Nothing schema-side
forbids adding platters or a shadow later — the rule is purely how
the dispatcher orders its lookups.

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


--[[
## Caspian-level catalog

Method bodies the dispatcher calls into when a method lookup on an
agent lands on the engine-class layer. Convention: each entry is a
Lua function whose first argument is the agent wrapper.

The dispatcher will call these as `obj.methods[name](agent)`. Inside a
method body, `self.pk` is the agent's own pk; `self.db` is the raw
sqlite handle.
]]
obj.methods = {}

--[[
### `.pk` — the target's pk (as a scalar_string)

Returns a fresh scalar row whose `scalar_string` column carries the
target's `object_pk` (a UUID). Every Caspian value IS a row, so the
UUID that .pk semantically produces has to be materialized as a row
rather than returned as a raw Lua string — the return value threads
through the frame's rv and eventually up to the cap's rv slot, both
of which want an object_pk.

Was called `.id` in the earlier spec draft at
[built-in-classes/object/methods](https://puck.uno/requirements/built-in-classes/object/methods/);
renamed to `.pk` to name what it actually is (a database primary key,
a UUID) rather than the abstract "identity" framing.

Two SQL statements per call, both cached as prepared statements per
engine:

1. Read the target's pk. Walk agent → bucket (key='b') → target
   (key='target').
2. Materialize a fresh scalar_string row whose `scalar_string`
   column carries the target's pk. Owner_role inherits from the
   target so the value belongs to whoever the receiver belongs to.

The returned row's own `object_pk` is DIFFERENT from the target's
pk — the UUID is stored as a value, not as a database reference.
]]
local READ_PK_SQL = "select r2.child as pk from refs r1 "
	.. "join refs r2 on r2.parent = r1.child "
	.. "where r1.parent = ? "
	.. "and r1.key = 'b' "
	.. "and r2.key = 'target'"

local MATERIALIZE_SQL = "insert into objects (base, scalar_string, owner_role) "
	.. "select 'o', ?1, owner_role "
	.. "from objects where object_pk = ?1 "
	.. "returning object_pk"

-- Weak-keyed caches for the two statements. One cache per SQL so
-- they can evolve independently.
local _read_stmts        = setmetatable({}, {__mode = 'k'})
local _materialize_stmts = setmetatable({}, {__mode = 'k'})

local function get_read_stmt(engine)
	local stmt = _read_stmts[engine]

	if not stmt then
		stmt = engine.cvm:prepare(READ_PK_SQL)
		_read_stmts[engine] = stmt
	end

	return stmt
end

local function get_materialize_stmt(engine)
	local stmt = _materialize_stmts[engine]

	if not stmt then
		stmt = engine.cvm:prepare(MATERIALIZE_SQL)
		_materialize_stmts[engine] = stmt
	end

	return stmt
end

function obj.methods.pk(self)
	-- Step 1: read the target's pk.
	local read_stmt = get_read_stmt(self.engine)
	read_stmt:bind_values(self.pk)

	local target_pk

	for row in read_stmt:nrows() do
		target_pk = row.pk
	end

	read_stmt:reset()

	if not target_pk then
		error("obj_pk_no_target: agent " .. tostring(self.pk) .. " has no target ref")
	end

	-- Step 2: materialize the target_pk as a scalar_string row.
	local scalar_stmt = get_materialize_stmt(self.engine)
	scalar_stmt:bind_values(target_pk)

	local scalar_pk

	for row in scalar_stmt:nrows() do
		scalar_pk = row.object_pk
	end

	scalar_stmt:reset()

	return scalar_pk
end


return obj
