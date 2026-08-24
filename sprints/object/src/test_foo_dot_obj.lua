#!/usr/bin/env lua5.4

--[[
{
	"module": "test_foo_dot_obj",
	"role": "End-to-end run of `$foo = 'bar'` + `$foo.obj.pk` through Larry with the sprint's MethodCall handler registered. The whole program runs through real dispatch: VariableScalar handles the assignment, MethodCall handles the fc-shape row for $foo.obj.pk, dispatch's .obj fast-path constructs the agent, dispatch's engine_class layer routes .pk to obj.methods.pk, the returned scalar lands in frame 0's rv, and frame 0's reap fires frames_child_delete_propagates_rv which lifts the rv to the cap. No manual DB manipulation.",
	"invoke": "lua5.4 sprints/object/src/test_foo_dot_obj.lua",
	"status": "sprint tests — end-to-end via real dispatch, no simulated pieces"
}
]]

local home = os.getenv('HOME') or ''
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = 'sprints/object/src/?.lua;'
	.. 'production/src/engine/?.lua;'
	.. 'production/src/engine/?/init.lua;'
	.. 'production/tests/main/lua/engine/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path

local Larry      = require('larry')
local MethodCall = require('method_call')


-- ------------------------------------------------------------
-- Assertion helpers
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
-- Setup
-- ------------------------------------------------------------

print("== end-to-end: $foo = 'bar'  →  $foo.obj.pk ==")

local e = Larry.new()
e:add_handler(MethodCall.new())


-- ------------------------------------------------------------
-- Run the program to completion
-- ------------------------------------------------------------

e:load("$foo = 'bar'\n$foo.obj.pk")

local result = e:run()

assert_eq(result.complete, 1, "program completed cleanly")


-- ------------------------------------------------------------
-- Verify the cap ended up with an rv slot
-- ------------------------------------------------------------

local cap_pk = result.cap_pk

if cap_pk then
	pass("cap_pk returned from run()")
else
	fail("cap_pk returned from run()", 'result.cap_pk is nil')
	os.exit(1)
end

-- The cap should have a bucket (materialized by propagate-rv when
-- frame 0 reaped with a non-null rv).
local cap_bucket_pk

for r in e.cvm:nrows(
	"select r.child from refs r "
	.. "join objects b on b.object_pk = r.child "
	.. "where r.parent = '" .. cap_pk .. "' and b.base = 'h'"
) do
	cap_bucket_pk = r.child
end

if cap_bucket_pk then
	pass("cap has a bucket")
else
	fail("cap has a bucket", "no hash-child of the cap found")
	os.exit(1)
end

-- The bucket should have an rv ref
local rv_pk = scalar(e.cvm,
	"select child from refs where parent = '" .. cap_bucket_pk
	.. "' and key = 'rv'")

if rv_pk then
	pass("cap's bucket has an rv ref")
else
	fail("cap's bucket has an rv ref", "no rv ref found")
	os.exit(1)
end


-- ------------------------------------------------------------
-- Verify the rv is a scalar_string carrying a UUID as VALUE
-- ------------------------------------------------------------

local rv_row = first(e.cvm,
	"select base, control, scalar_string, scalar_number, scalar_bool, scalar_null "
	.. "from objects where object_pk = '" .. rv_pk .. "'")

assert_eq(rv_row and rv_row.base,           'o',  "rv row base='o'")
assert_eq(rv_row and rv_row.control,        nil,  "rv row control is null")
assert_eq(rv_row and rv_row.scalar_number,  nil,  "rv row scalar_number is null")
assert_eq(rv_row and rv_row.scalar_bool,    nil,  "rv row scalar_bool is null")
assert_eq(rv_row and rv_row.scalar_null,    nil,  "rv row scalar_null is null")

local rv_string = rv_row and rv_row.scalar_string

if rv_string then
	pass("rv row's scalar_string is populated")
else
	fail("rv row's scalar_string is populated", "scalar_string is nil")
	os.exit(1)
end

-- The scalar_string should be UUID-shaped: 36 chars, 4 dashes at
-- positions 9, 14, 19, 24 (0-based).
if #rv_string == 36
	and rv_string:sub(9, 9)  == '-'
	and rv_string:sub(14, 14) == '-'
	and rv_string:sub(19, 19) == '-'
	and rv_string:sub(24, 24) == '-'
then
	pass("rv scalar_string is UUID-shaped (36 chars, 4 dashes)")
else
	fail("rv scalar_string is UUID-shaped (36 chars, 4 dashes)",
		'got: ' .. tostring(rv_string))
end

-- The scalar's own object_pk is different from the UUID it carries.
-- Proves the UUID is stored as VALUE (in scalar_string), not as a
-- database reference to the target row.
if rv_pk ~= rv_string then
	pass("rv row's own object_pk differs from its scalar_string (value, not reference)")
else
	fail("rv row's own object_pk differs from its scalar_string",
		"rv_pk == rv_string means we accidentally stored a reference")
end


-- ------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------

print()
print(string.format("  %d passed, %d failed", passed, failed))

if failed > 0 then
	os.exit(1)
end
