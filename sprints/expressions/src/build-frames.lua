#!/usr/bin/env lua5.4
--[[
Sprint runner: process the source

    $foo = 1

    if $foo
        $bar = 2
    end

end-to-end via Larry, observing every frame lifecycle event through
debug_log entries seeded by trace triggers on the `objects` table.

Approach:

1. Construct Larry (Engine subclass with test conveniences).
2. Install trace triggers on `objects` INSERT / DELETE and on `refs`
   INSERT / DELETE that append lines to debug_log describing each
   mutation.
3. Register a minimum-viable `if_handler` on the engine — the
   current engine has no built-in handler for the `{if: {...}}`
   atom shape. Enough to make the sample program run end-to-end.
4. Load the source and run.
5. Print debug_log entries in order, plus the surviving `objects`
   rows at the end.

The if_handler is walking-skeleton-shortcut: it dispatches action
statements INLINE in the current frame rather than spawning a
nested frame. Sufficient for the demo; NOT the sprint's target
design, which spawns a nested frame per closure body.

Invoke from anywhere:

    lua5.4 sprints/expressions/src/build-frames.lua   -- from repo root
    lua5.4 build-frames.lua                           -- from src dir
]]

local script_dir = arg[0]:match('^(.*)/') or '.'
local repo_root  = script_dir .. '/../../..'
local home       = os.getenv('HOME') or ''

package.path = repo_root .. '/production/src/engine/?.lua;'
	.. repo_root .. '/production/src/engine/?/init.lua;'
	.. repo_root .. '/production/tests/main/lua/engine/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local Larry = require('larry')

local SOURCE = [[
$x = 1
$y = 2

if $x
	$result = 'same'
else
	$result = 'different'
end
]]

-- ------------------------------------------------------------
-- Trace triggers: log every objects / refs mutation to debug_log,
-- scoped to the current process cap (via current_process_pk()).
-- ------------------------------------------------------------
local TRACE_TRIGGERS = [[
create trigger sprint_log_object_insert
after insert on objects
when current_process_pk() is not null
begin
	insert into debug_log (note) values (
		'INSERT objects  pk=' || substr(new.object_pk, 1, 8)
		|| '  base=' || new.base
		|| coalesce('  control=' || new.control, '')
		|| coalesce('  frame_ast=' || substr(new.frame_ast, 1, 40), '')
		|| coalesce('  frame_process_cap=' || new.frame_process_cap, '')
		|| coalesce('  scalar_number=' || cast(new.scalar_number as text), '')
		|| coalesce('  scalar_string=' || new.scalar_string, '')
		|| coalesce('  role_core=' || new.role_core, '')
	);
end;

create trigger sprint_log_object_delete
after delete on objects
when current_process_pk() is not null
begin
	insert into debug_log (note) values (
		'DELETE objects  pk=' || substr(old.object_pk, 1, 8)
		|| '  base=' || old.base
		|| coalesce('  control=' || old.control, '')
	);
end;

create trigger sprint_log_ref_insert
after insert on refs
when current_process_pk() is not null
begin
	insert into debug_log (note) values (
		'INSERT refs     parent=' || substr(new.parent, 1, 8)
		|| '  child=' || substr(new.child, 1, 8)
		|| coalesce('  key=' || new.key, '')
		|| '  idx=' || new.idx
	);
end;

create trigger sprint_log_ref_delete
after delete on refs
when current_process_pk() is not null
begin
	insert into debug_log (note) values (
		'DELETE refs     parent=' || substr(old.parent, 1, 8)
		|| '  child=' || substr(old.child, 1, 8)
		|| coalesce('  key=' || old.key, '')
		|| '  idx=' || old.idx
	);
end;
]]

-- ------------------------------------------------------------
-- Minimum-viable if_handler.
--
-- Matches `[{if: {conditions, else?}}, ...]` rows. Under the current
-- production CaspM, that's what the transpiler + normalizer emit
-- for `if X then Y end` / `if X then Y else Z end`.
--
-- Walking-skeleton shortcut: dispatches action statements INLINE in
-- the current frame rather than spawning a nested frame. Enough to
-- make the sample program run end-to-end for demonstration; NOT the
-- sprint's target design.
--
-- Truthiness check: uses a raw SQL query against the frame_scoped_vars
-- view to look up the test var's value pk; treats any populated pk
-- as truthy (a placeholder — proper truthiness reads the scalar
-- value and checks against null / false).
-- ------------------------------------------------------------

local function extract_body(action_or_else)
	-- Handles both shapes: {cl: {pm, bd}} (closure) and bare arrays
	-- (which the ternary rewrite produces).
	if type(action_or_else) == 'table' then
		if type(action_or_else.cl) == 'table' and type(action_or_else.cl.bd) == 'table' then
			return action_or_else.cl.bd
		end
		if action_or_else[1] ~= nil then
			return {action_or_else}
		end
	end

	return nil
end

local function evaluate_test_truthy(engine, frame_pk, test_atom)
	-- Only handles {var: "name"} tests. Look up the var in scope;
	-- treat any populated value_pk as truthy.
	if type(test_atom) ~= 'table' or test_atom.var == nil then
		error("if_handler_unsupported_test: only {var:'x'} tests supported for now; got " .. tostring(test_atom))
	end

	local stmt = engine.cvm:prepare(
		"select value_pk from frame_scoped_vars where frame_pk = ? and var_name = ? limit 1"
	)
	stmt:bind_values(frame_pk, test_atom.var)

	local value_pk
	for row in stmt:nrows() do
		value_pk = row.value_pk
	end
	stmt:reset()
	stmt:finalize()

	return value_pk ~= nil
end

local IfHandler = {}
IfHandler.__index = IfHandler

function IfHandler.new()
	return setmetatable({}, IfHandler)
end

function IfHandler:handle(engine, row)
	if type(row[1]) ~= 'table' or type(row[1]['if']) ~= 'table'
			or type(row[1]['if'].conditions) ~= 'table' then
		return false
	end

	local if_atom = row[1]['if']
	local frame   = engine.current_frame

	engine.cvm:exec(
		"insert into debug_log (note) values ('IF-HANDLER  entering, "
		.. #if_atom.conditions .. " condition(s)"
		.. (if_atom['else'] ~= nil and ', has else' or ', no else') .. "')"
	)

	local action_body = nil

	for _, cond in ipairs(if_atom.conditions) do
		local truthy = evaluate_test_truthy(engine, frame.object_pk, cond.test)

		engine.cvm:exec(
			"insert into debug_log (note) values ('IF-HANDLER  test var="
			.. (cond.test.var or '?') .. " -> "
			.. (truthy and 'truthy' or 'falsy') .. "')"
		)

		if truthy then
			action_body = extract_body(cond.action)
			break
		end
	end

	if action_body == nil and if_atom['else'] ~= nil then
		engine.cvm:exec(
			"insert into debug_log (note) values ('IF-HANDLER  falling to else')"
		)
		action_body = extract_body(if_atom['else'])
	end

	if action_body ~= nil then
		for _, stmt in ipairs(action_body) do
			engine:run_row(stmt)
		end
	end

	-- Ensure gc=1 so the outer walker can advance past this if row —
	-- if action_body was nil or its inline dispatches didn't mark gc,
	-- we mark it here explicitly.
	engine.data:mark_frame_gc(frame.object_pk)

	return true
end

-- ------------------------------------------------------------
-- Run.
-- ------------------------------------------------------------

local larry = Larry.new()

-- Install trace triggers BEFORE running. Triggers only fire when a
-- process cap is set (via the current_process_pk() guard in each
-- trigger's WHEN clause), so schema-apply-time inserts don't get
-- logged.
assert(larry.cvm:exec(TRACE_TRIGGERS) == 0, larry.cvm:errmsg())

larry:add_handler(IfHandler.new())

print('==================================================')
print('source')
print('==================================================')
print(SOURCE)

print('==================================================')
print('running')
print('==================================================')

local ok, err = pcall(function()
	larry:load(SOURCE)
	larry:run()
end)

if not ok then
	print('RUN FAILED: ' .. tostring(err))
end

print()

-- ------------------------------------------------------------
-- Dump debug_log entries in insertion order.
-- ------------------------------------------------------------
print('==================================================')
print('debug_log entries (chronological)')
print('==================================================')

local n = 0

for row in larry.cvm:nrows(
	"select entry_pk, note from debug_log order by entry_pk"
) do
	n = n + 1
	print(string.format('%3d. %s', row.entry_pk, row.note))
end

if n == 0 then
	print('(none)')
end

print()

-- ------------------------------------------------------------
-- Dump surviving objects at the end.
-- ------------------------------------------------------------
print('==================================================')
print('objects (survivors after run)')
print('==================================================')

for row in larry.cvm:nrows([[
	select object_pk, base, control, role_core, scalar_number, scalar_string,
	       frame_process_cap, frame_stmt_idx, frame_gc
	from objects
	order by base, control nulls first, object_pk
]]) do
	local parts = {
		'pk=' .. row.object_pk:sub(1, 8),
		'base=' .. row.base,
	}
	if row.control        then table.insert(parts, 'control=' .. row.control) end
	if row.role_core      then table.insert(parts, 'role_core=' .. row.role_core) end
	if row.scalar_number  then table.insert(parts, 'scalar_number=' .. row.scalar_number) end
	if row.scalar_string  then table.insert(parts, 'scalar_string=' .. row.scalar_string) end
	if row.frame_process_cap then table.insert(parts, 'process_cap=' .. row.frame_process_cap) end
	if row.frame_stmt_idx then table.insert(parts, 'stmt_idx=' .. row.frame_stmt_idx) end

	print('  ' .. table.concat(parts, '  '))
end
