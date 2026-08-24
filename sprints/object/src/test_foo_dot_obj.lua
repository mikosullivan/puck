#!/usr/bin/env lua5.4

--[[
{
	"module": "test_foo_dot_obj",
	"role": "End-to-end walk of `$foo = 'bar'` then $foo.obj + $foo.obj.pk. Runs the assignment through the production engine (transpiler + normalizer + VariableScalar handler), halts on %process.stop, finds $foo's pk from the scope chain, then calls obj.new(engine, foo_pk) to materialize the agent, then calls obj.methods.pk(agent) to exercise the first catalog method and verifies it returns $foo's pk. Temp triggers on objects + refs inserts mirror every write obj.new does into debug_log; the process log at the end reads as a step-by-step trace of both the agent construction and the .pk call.",
	"invoke": "lua5.4 sprints/object/src/test_foo_dot_obj.lua",
	"status": "sprint tests"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'sprints/object/src/?.lua;'
	.. 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local engine_mod = require('engine')
local obj        = require('obj')


-- ------------------------------------------------------------
-- Assertion helpers (same shape as the other sprint tests)
-- ------------------------------------------------------------

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(string.format("  \27[32mok\27[0m   %s", label))
end

local function fail(label, why)
	failed = failed + 1
	print(string.format("  \27[31mFAIL\27[0m %s", label))
	print(string.format("       %s", why))
end

local function assert_eq(actual, expected, label)
	if actual == expected then
		pass(label)
	else
		fail(label, string.format('expected %s, got %s', tostring(expected), tostring(actual)))
	end
end

local function scalar(db, sql)
	for r in db:rows(sql) do
		return r[1]
	end
	return nil
end

local function first(db, sql)
	for r in db:nrows(sql) do
		return r
	end
	return nil
end


-- ------------------------------------------------------------
-- Test
-- ------------------------------------------------------------

print("== $foo = 'bar'  →  $foo.obj  →  $foo.obj.pk ==")

local e = engine_mod.new()

-- ---- Step 1: run the assignment, halt after ------------------
e:load("$foo = 'bar'\n%process.stop")

local result = e:run()

assert_eq(result.stopped, 1, "%process.stop halted the run")

-- ---- Step 2: find $foo's pk via the scope chain --------------

local foo_pk = scalar(e.cvm,
	"select r.child from refs r where r.key = 'foo'")

if foo_pk then
	pass("$foo's scope ref found (key='foo')")
else
	fail("$foo's scope ref found (key='foo')", 'no ref with key=foo')
	os.exit(1)
end

local foo_row = first(e.cvm,
	"select base, scalar_string from objects "
	.. "where object_pk = '" .. foo_pk .. "'")

assert_eq(foo_row and foo_row.base,          'o',   "$foo row base='o'")
assert_eq(foo_row and foo_row.scalar_string, 'bar', "$foo carries scalar_string='bar'")

-- ---- Step 3: install observability triggers ------------------
-- Mirror every objects and refs INSERT into debug_log so the log at
-- the end reads as a step-by-step trace of what obj.new did. Installed
-- AFTER the process cap already exists (from %process.stop's halt)
-- so debug_log's `current_process_pk()` DEFAULT resolves cleanly.

e.cvm:exec([[
	create temp trigger t_log_objects_insert
	after insert on objects
	begin
		insert into debug_log (note) values (
			'obj-new insert objects: pk='
			|| substr(new.object_pk, 1, 8)
			|| ' base=' || new.base
			|| ' control=' || coalesce(new.control, 'null')
			|| ' engine_class=' || coalesce(new.engine_class, 'null')
		);
	end;

	create temp trigger t_log_refs_insert
	after insert on refs
	begin
		insert into debug_log (note) values (
			'obj-new insert refs: parent='
			|| substr(new.parent, 1, 8)
			|| ' child=' || substr(new.child, 1, 8)
			|| ' key=' || coalesce(new.key, 'null')
			|| ' idx=' || new.idx
		);
	end;
]])

-- Marker line so the log clearly separates before / after obj.new.
e.cvm:exec("insert into debug_log (note) values ('---- calling obj.new ----');")

-- ---- Step 4: call obj.new(engine, foo_pk) --------------------

local agent = obj.new(e, foo_pk)

assert_eq(type(agent.pk), 'string', "obj.new returned a wrapper with a pk")

-- ---- Step 5: verify the agent's row -------------------------

local agent_row = first(e.cvm,
	"select base, control, engine_class, owner_role "
	.. "from objects where object_pk = '" .. agent.pk .. "'")

assert_eq(agent_row and agent_row.base,         'o',   "agent base='o'")
assert_eq(agent_row and agent_row.control,      nil,   "agent control is null")
assert_eq(agent_row and agent_row.engine_class, 'obj', "agent engine_class='obj'")

-- ---- Step 6: verify the bucket + target ref -----------------

local bucket_pk = scalar(e.cvm,
	"select child from refs where parent = '" .. agent.pk .. "' and key = 'b'")

if bucket_pk then
	pass("agent → bucket via key='b'")
else
	fail("agent → bucket via key='b'", 'no b-ref found')
end

local target_pk = scalar(e.cvm,
	"select child from refs where parent = '" .. (bucket_pk or '') .. "' and key = 'target'")

assert_eq(target_pk, foo_pk, "bucket → target points at $foo")

-- ---- Step 7: call obj.methods.pk(agent) — the first catalog method ----
-- Simulates what the dispatcher will do when it sees `$foo.obj.pk`:
-- fast-path returns the agent, then the walker resolves `.pk` against
-- the agent's engine-class layer, which lands in obj.methods.pk.

e.cvm:exec("insert into debug_log (note) values ('---- calling .obj.pk ----');")

local returned_pk = obj.methods.pk(agent)

e.cvm:exec(
	"insert into debug_log (note) values ("
	.. "'.obj.pk returned: ' || substr('" .. tostring(returned_pk) .. "', 1, 8)"
	.. ");"
)

assert_eq(returned_pk, foo_pk, "$foo.obj.pk returned $foo's pk")


-- ------------------------------------------------------------
-- Dump the process log for review
-- ------------------------------------------------------------

print()
print("== process log ==")

for r in e.cvm:nrows(
	"select entry_pk, note from debug_log "
	.. "where note like 'obj-new%' "
	.. "or note like '.obj.pk%' "
	.. "or note like '---- calling%' "
	.. "order by entry_pk"
) do
	print(string.format("  #%d  %s", r.entry_pk, r.note))
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format("  %d passed, %d failed", passed, failed))

if failed > 0 then
	os.exit(1)
end
