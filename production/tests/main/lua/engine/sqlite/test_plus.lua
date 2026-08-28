--[[
{
	"spec": "test_plus",
	"role": "End-to-end tests for the Plus handler.",
	"status": "V0.1"
}
]]

local h      = require('helpers')
local engine = require('engine')


local function scalar(cvm, sql, ...)
	local stmt = cvm:prepare(sql)

	if select('#', ...) > 0 then
		stmt:bind_values(...)
	end

	local out

	for row in stmt:rows() do
		out = row[1]
	end

	stmt:reset()

	return out
end


local function first(cvm, sql, ...)
	local stmt = cvm:prepare(sql)

	if select('#', ...) > 0 then
		stmt:bind_values(...)
	end

	local out

	for row in stmt:nrows() do
		out = row
		break
	end

	stmt:reset()

	return out
end


local function assert_plus_program(program, expected_sum)
	local e = engine.new()
	e:load(program)

	local result = e:run()

	h.assert_eq(result.complete, 1, program .. ': result.complete == 1')
	h.assert_true(result.stopped == nil, program .. ': result.stopped is absent')
	h.assert_true(type(result.cap_pk) == 'string', program .. ': result.cap_pk is a string')

	local cap = first(e.cvm,
		"select frame_stmt_idx, frame_gc from objects where object_pk = ?",
		result.cap_pk)
	h.assert_true(cap ~= nil, program .. ': cap row exists')
	h.assert_eq(tonumber(cap.frame_stmt_idx), 1, program .. ": cap.frame_stmt_idx == 1")
	h.assert_true(cap.frame_gc == nil, program .. ': cap.frame_gc is null')

	local cap_kids = scalar(e.cvm,
		"select count(*) from objects where frame_parent = ?",
		result.cap_pk)
	h.assert_eq(cap_kids, 0, program .. ': cap has no children (frame 0 reaped)')

	local bucket_pk = scalar(e.cvm,
		"select child from refs where parent = ? and key = 'b'",
		result.cap_pk)
	h.assert_true(bucket_pk ~= nil, program .. ": cap.bucket ref exists")

	local result_pk = scalar(e.cvm,
		"select child from refs where parent = ? and key = 'rv'",
		bucket_pk)
	h.assert_true(result_pk ~= nil, program .. ": cap.bucket.rv ref exists")

	local payload = scalar(e.cvm,
		"select scalar_number from objects where object_pk = ?",
		result_pk)
	h.assert_eq(payload, expected_sum, program .. ": scalar_number matches expected sum")

	h.assert_eq(scalar(e.cvm, 'select count(*) from needs_trace'), 0,
		program .. ': needs_trace empty')

	h.assert_eq(scalar(e.cvm, 'select count(*) from objects'), 6,
		program .. ': six objects (seeds + cap + bucket + result scalar)')
end


h.test('1 + 2: Plus orchestrates two eval frames, produces 3', function()
	assert_plus_program('1 + 2', 3)
end)


h.test('1 + 2 + 3: nested method_call in arg_0; inner + evaluated via child frame', function()
	assert_plus_program('1 + 2 + 3', 6)
end)


h.test('10 + 20 + 30 + 40: deeper nesting', function()
	assert_plus_program('10 + 20 + 30 + 40', 100)
end)


h.test("1 + 1: interned-scalar edge; receiver and arg_0 slots share target pk", function()
	assert_plus_program('1 + 1', 2)
end)
