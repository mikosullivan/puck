--[[
{
	"module": "larry",
	"role": "Sprint-scoped Engine subclass for the first-variable sprint. Boots on the sprint's copy of `schema.sql` and prepends the sprint dir to `package.path` so any `require('cvm.frame')` or `require('handlers.variable-scalar')` resolves to sprint copies (under `sprints/first-variable/cvm/` and `sprints/first-variable/handlers/`) rather than shipping. Also overrides `run` — shipping's `run` uses prepared statements against the removed `processes` table and `process_pk` column, so a fresh sprint-scoped run path is needed. When the design ships, the sprint copies get promoted into shipping and this whole tree goes away.",
	"exports": {
		"new": "(opts?) -> Larry — same signature as Engine.new; auto-wires opts.cvm.schema_path to the sprint schema when omitted",
		"run": "() -> hash — end-to-end runner against the sprint schema. Seeds cap + frame 0, walks frame 0's ast with advance-with-gc per statement, then advances the cap to sweep frame 0 and reach terminal shape. Returns a hash with `complete = 1`."
	},
	"depends_on": ["engine", "cvm", "cjson", "cvm.open"],
	"status": "sprint-scoped delegation subclass with intercepted frame.lua and handlers.variable-scalar; own run for sprint schema"
}
]]

--[[
# `larry` (first-variable sprint)

A Larry is an Engine, plus whatever the sprint has fiddled with. Sprint copies of files that need modification live under `sprints/first-variable/cvm/` and `sprints/first-variable/handlers/`; Larry prepends the sprint dir to `package.path` at module-load time so any `require('cvm.frame')` or `require('handlers.variable-scalar')` resolves to the sprint version first, falling through to shipping for anything not copied.

**Sprint focus: variable storage via `scopes`.** The current shipping [frame.lua](../../src/engine/cvm/frame.lua) puts a `locals` hash directly under the frame's bucket. This sprint replaces that with a `scopes` ArrayPrimitive: `bucket → scopes → [own_locals_hash, ...]`. First entry (`scopes[0]`) is the frame's own locals; further entries are captured scopes (from closures, once those land). See [closures.md](closures.md) for the design.

**Boots on the sprint schema.** `Larry.new()` defaults `opts.cvm.schema_path` to the sprint's `schema.sql` sibling, so a Larry runs against the invariants this sprint has landed (cap-as-frame, advance-with-gc, scopes convention, hash-key identifier rule).

**Own `run` method.** Shipping's `Engine:run` prepares statements against columns and tables the sprint schema no longer has (`process_pk`, `processes`). Those prepares silently fail in Engine.new, leaving nil slots in `self.stmts`. Larry provides its own `run` that seeds a cap frame (`primitive='f'`, `process=1`, `ast='[]'`), pushes frame 0 under it, walks frame 0's ast with the sprint's advance-with-gc pattern, then advances the cap to sweep frame 0 and reach terminal state.
]]


-- Locate this file's directory so we can (a) find the sibling schema
-- and (b) prepend the sprint's require path.
local function this_dir()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	return this_file:match('(.*/)') or './'
end


-- Prepend the sprint's require path BEFORE loading Engine (or any of
-- the cvm.* or handlers.* modules). Once a module lands in
-- `package.loaded` it's cached; the ordering below guarantees the
-- first resolution of `require('cvm.frame')` or
-- `require('handlers.variable-scalar')` — whoever triggers it — hits
-- the sprint copy.
local _sprint_dir = this_dir()
package.path = _sprint_dir .. '?.lua;'
	.. _sprint_dir .. '?/init.lua;'
	.. package.path


local sqlite = require('lsqlite3')
local cjson  = require('cjson')
local Engine = require('engine')
local cvm    = require('cvm.open')
local Cvm    = require('cvm')

local sqlite_row = sqlite.ROW


local function sprint_schema_path()
	return this_dir() .. 'schema.sql'
end


local Larry = setmetatable({}, {__index = Engine})
Larry.__index = Larry


--[[
## `Larry.new` — construct a Larry instance

Delegates to `Engine.new(opts)` and rewraps the returned instance's metatable so the identity is Larry. When `opts.cvm` is omitted (or omits `schema_path`), auto-wires the sprint schema so the CVM connection installs the sprint's invariants instead of the shipping ones.

Also wraps the raw db handle in a `cvm` data-access instance (`cvm.new(handle)`) and stashes it on `self.data`. Larry's `run` (and any sprint-scoped write path) uses `self.data:object_by_pk`, `self.data:add_scalar`, etc. — the wrapper that exposes objects/pks rather than raw SQL.

Method resolution on the returned instance:

- Larry-defined methods win first (via `Larry.__index = Larry`).
- Then Engine methods (via Larry's own metatable, `__index = Engine`).
- Then anything in Engine's own `__index` chain.
]]
function Larry.new(opts)
	opts = opts or {}
	opts.cvm = opts.cvm or {}

	if opts.cvm.schema_path == nil then
		opts.cvm.schema_path = sprint_schema_path()
	end

	local larry = Engine.new(opts)
	larry.data  = Cvm.new(larry.cvm)

	-- Sprint override: shipping's add_bucket / add_stack write via a
	-- `bucket_for` / `stack_for` column on the collection, which the
	-- sprint schema has dropped. Under the sprint design ownership of a
	-- bucket / stack is a normal refs row from the owner to the
	-- collection — no dedicated columns anywhere. Rewrite the two
	-- methods here: if the owner already has a hash-child (or
	-- array-child), return it; else INSERT the collection with
	-- inherited owner_role and add a refs row from owner to it.
	local db = larry.cvm

	local stmt_find_owner_hash_child = db:prepare(
		"select r.child from refs r " ..
		"join objects c on c.object_pk = r.child " ..
		"where r.parent = ? and c.primitive = 'h'"
	)

	local stmt_find_owner_array_child = db:prepare(
		"select r.child from refs r " ..
		"join objects c on c.object_pk = r.child " ..
		"where r.parent = ? and c.primitive = 'a'"
	)

	local stmt_insert_hash_with_inherited_role = db:prepare(
		"insert into objects (primitive, owner_role) " ..
		"select 'h', owner_role from objects where object_pk = ? " ..
		"returning object_pk"
	)

	local stmt_insert_array_with_inherited_role = db:prepare(
		"insert into objects (primitive, owner_role) " ..
		"select 'a', owner_role from objects where object_pk = ? " ..
		"returning object_pk"
	)

	function larry.data:add_bucket(for_object_pk)
		-- Return existing if the owner already has a hash-child.
		stmt_find_owner_hash_child:bind_values(for_object_pk)
		local existing

		if stmt_find_owner_hash_child:step() == sqlite_row then
			existing = stmt_find_owner_hash_child:get_value(0)
		end

		stmt_find_owner_hash_child:reset()
		if existing then return existing end

		-- Otherwise insert the hash and add the owner→bucket ref.
		stmt_insert_hash_with_inherited_role:bind_values(for_object_pk)
		stmt_insert_hash_with_inherited_role:step()
		local bucket_pk = stmt_insert_hash_with_inherited_role:get_value(0)
		stmt_insert_hash_with_inherited_role:reset()

		self:add_ref(for_object_pk, nil, bucket_pk)

		return bucket_pk
	end

	function larry.data:add_stack(for_object_pk)
		stmt_find_owner_array_child:bind_values(for_object_pk)
		local existing

		if stmt_find_owner_array_child:step() == sqlite_row then
			existing = stmt_find_owner_array_child:get_value(0)
		end

		stmt_find_owner_array_child:reset()
		if existing then return existing end

		stmt_insert_array_with_inherited_role:bind_values(for_object_pk)
		stmt_insert_array_with_inherited_role:step()
		local stack_pk = stmt_insert_array_with_inherited_role:get_value(0)
		stmt_insert_array_with_inherited_role:reset()

		self:add_ref(for_object_pk, nil, stack_pk)

		return stack_pk
	end

	return setmetatable(larry, Larry)
end


--[[
## `Larry:run` — sprint-scoped end-to-end runner

Runs the loaded CaspM program (`self.caspm`, populated by `engine:load(source)`) end-to-end against the sprint schema. Steps:

1. **Seed the cap.** Insert a frame row with `primitive='f'`, `process=1`, `ast='[]'`, `stmt_idx=0`, no parent. Its `object_pk` IS the process identity.
2. **Seed frame 0** under the cap. Insert a frame row with `primitive='f'`, the JSON-encoded CaspM in `ast`, `stmt_idx=0`, `parent_frame=cap_pk`.
3. **Walk frame 0's ast.** Per statement:
	- Set `self.current_frame` to the wrapped frame 0 (so handlers can reach it).
	- Dispatch the row through the handler chain via `self:run_row(row)`.
	- Advance: `UPDATE frame 0 SET stmt_idx = stmt_idx + 1, gc = 1` — cascades any marker child.
	- Reset: `UPDATE frame 0 SET gc = null` — completes the gc cycle.
4. **Close the process.** After the ast is exhausted:
	- Advance cap: `UPDATE cap SET stmt_idx = 1, gc = 1` — cascades frame 0. Frame 0's BEFORE-DELETE triggers mark its bucket / stack `needs_trace = 1` via the owner-side rules on `bucket_pk` / `stack_pk`.
	- Reset cap: `UPDATE cap SET gc = null` — cap is now terminal (stmt_idx=1, gc=null, no children).
5. **Return** a hash `{complete = 1, cap_pk = cap_pk}` — the completion signal is derivable from the cap's terminal shape; the cap_pk is included so tests can inspect post-run state.

**GC not wired here.** Marking the cap `needs_trace = 1` and running the trace-and-sweep pass would land with GC integration; the sprint stops at "cap reaches terminal state." The cap and any needs_trace-marked orphans persist after `run` returns.

**Precondition.** `self.caspm` must be populated (via `engine:load(source)`); missing raises `engine:run() called before engine:load()` (same message shipping uses).
]]
function Larry:run()
	if not self.caspm then
		error("engine:run() called before engine:load(); no program to execute")
	end

	local db      = self.cvm
	local user_pk = self.data:object_by_pk(
		(function()
			for row in db:nrows("select object_pk from objects where core_role = 'u'") do
				return row.object_pk
			end
		end)()
	).object_pk

	-- 1. Seed the cap.
	local cap_pk

	local cap_stmt = db:prepare(
		"insert into objects (primitive, process, ast, stmt_idx, owner_role) " ..
		"values ('f', 1, '[]', 0, ?) returning object_pk"
	)
	cap_stmt:bind_values(user_pk)

	for row in cap_stmt:nrows() do
		cap_pk = row.object_pk
	end

	cap_stmt:finalize()

	-- 2. Seed frame 0 under the cap.
	local frame_0_pk
	local ast_json = cjson.encode(self.caspm)

	local frame_stmt = db:prepare(
		"insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) " ..
		"values ('f', ?, 0, ?, ?) returning object_pk"
	)
	frame_stmt:bind_values(ast_json, cap_pk, user_pk)

	for row in frame_stmt:nrows() do
		frame_0_pk = row.object_pk
	end

	frame_stmt:finalize()

	self.caspm = nil

	-- 3. Walk frame 0's ast.
	local ast = cjson.decode(ast_json)
	local i   = 0

	while i < #ast do
		self.current_frame = self.data:object_by_pk(frame_0_pk)

		self:run_row(ast[i + 1])

		-- Advance + set gc=1 in one UPDATE. Cascades the marker child
		-- pushed by the handler.
		db:exec(string.format(
			"update objects set stmt_idx = %d, gc = 1 where object_pk = '%s'",
			i + 1, frame_0_pk
		))

		-- Complete the gc cycle. No children remain (marker was
		-- cascade-swept), so the gc-reset trigger passes.
		db:exec(string.format(
			"update objects set gc = null where object_pk = '%s'",
			frame_0_pk
		))

		i = i + 1
	end

	self.current_frame = nil

	-- 4. Close the process. Cap advances 0→1 with gc=1; cascade
	-- sweeps frame 0 (its gc is null — delete rule passes; cap's gc
	-- is 1 — child-delete rule passes). Frame 0's cascade drops the
	-- bucket via bucket_for FK; ref-deletes mark orphan targets
	-- needs_trace=1.
	db:exec(string.format(
		"update objects set stmt_idx = 1, gc = 1 where object_pk = '%s'",
		cap_pk
	))

	-- Reset cap gc — cap is now terminal.
	db:exec(string.format(
		"update objects set gc = null where object_pk = '%s'",
		cap_pk
	))

	return {complete = 1, cap_pk = cap_pk}
end


return Larry
