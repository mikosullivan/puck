--[[
{
	"spec": "test_initialize_process",
	"role": "Tests for `cvm.initialize_process`. Verifies the one-INSERT process creation: returns a non-nil UUID pk; creates exactly one processes row; returned pk names that row; pk is a text UUID (36-char string); two calls create two distinct rows with distinct pks.",
	"status": "walking-skeleton"
}
]]

--[[
# `test_initialize_process`

Behavioural tests for the `initialize_process(db) -> process_pk` routine at [src/engine/cvm/initialize_process.lua](https://puck.uno/src/engine/cvm/initialize_process.lua). One INSERT into `processes` with the text-UUID default fired by `default values`, returned via `RETURNING`.
]]

local h                  = require('helpers')
local cvm                = require('cvm.open')
local initialize_process = require('cvm.initialize_process')

h.test('initialize_process returns a non-nil pk', function()
	local db = cvm.open()
	local pk = initialize_process(db)
	h.assert_true(pk ~= nil, 'initialize_process returned nil')
	db:close()
end)

h.test('initialize_process creates exactly one processes row', function()
	local db = cvm.open()
	initialize_process(db)

	local count

	for row in db:nrows('select count(*) as n from processes') do
		count = row.n
	end

	h.assert_eq(count, 1, 'expected exactly one processes row after one call')
	db:close()
end)

h.test('initialize_process — returned pk names the row just inserted', function()
	local db = cvm.open()
	local returned = initialize_process(db)

	local from_table

	for row in db:nrows('select process_pk from processes') do
		from_table = row.process_pk
	end

	h.assert_eq(returned, from_table, "returned pk should equal the row's process_pk")
	db:close()
end)

h.test('initialize_process — returned pk is a text UUID (36-char string)', function()
	local db = cvm.open()
	local pk = initialize_process(db)
	h.assert_eq(type(pk), 'string', 'process_pk should be text')
	h.assert_eq(#pk, 36, 'process_pk should be a 36-char UUID string')
	db:close()
end)

h.test('initialize_process — two calls create two distinct rows with distinct pks', function()
	local db = cvm.open()
	local pk_1 = initialize_process(db)
	local pk_2 = initialize_process(db)

	local count

	for row in db:nrows('select count(*) as n from processes') do
		count = row.n
	end

	h.assert_eq(count, 2, 'expected two processes rows after two calls')
	h.assert_true(pk_1 ~= pk_2, 'the two returned pks should differ')
	db:close()
end)
