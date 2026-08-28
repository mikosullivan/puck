--[[
{
	"spec": "test_bare_scalar",
	"role": "End-to-end tests for bare-scalar Caspian programs — a single value literal as the whole program. Runs `'foo'` (string), `42` (number), `true` (bool); asserts each runs cleanly through the ScalarAtom handler, produces a scalar object bound as the frame's rv, and propagates up through frame 0's reap to the cap's bucket `rv` slot as the process's return value.",
	"status": "V0.1"
}
]]

--[[
# `test_bare_scalar`

End-to-end tests for the [`handlers.scalar-atom`](https://puck.uno/production/src/engine/handlers/scalar-atom.lua) core handler.

A program that is just a scalar literal (`'foo'`, `42`, `true`, `null`) normalizes to a one-statement ast whose row is `[{v: LITERAL}]`. `ScalarAtom` claims that shape and does its four writes: `add_scalar` + `add_bucket` + `upsert_ref(bucket, 'rv', scalar)` + `mark_frame_gc`. Frame 0's walker advances past the statement, hits terminal, reaps. The reap fires `frames_child_delete_propagates_rv`, which copies the `rv` ref up to the cap's bucket. Post-run: `cap.bucket.rv` names the scalar that was the program's value.

Assertions per case:

- `run()` returns `{complete = 1, cap_pk = ...}` — no halt, no error.
- Cap in terminal state (`frame_stmt_idx = 1`, `frame_gc = null`), no children (frame 0 reaped).
- One ref from cap to its bucket (`key = 'b'`), one from bucket to the scalar (`key = 'rv'`).
- Scalar's payload matches the source literal.
- No orphan state — `needs_trace` empty.
- Six object rows: three core-role seeds, the cap, the cap's bucket, the scalar.
]]

local h      = require('helpers')
local engine = require('engine')


-- Fetch a single scalar from a one-row-one-column query.
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


-- Fetch the first row (nrows shape) or nil.
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


--[[
Runs `program` through a fresh engine and asserts on the shape of what came out. `column` is the scalars-table column name that carries the payload for this literal's type (`scalar_string` / `scalar_number` / `scalar_bool`); `expected_payload` is the value that column should hold.
]]
local function assert_bare_scalar_program(program, column, expected_payload)
	local e = engine.new()
	e:load(program)

	local result = e:run()

	h.assert_eq(result.complete, 1, program .. ': result.complete == 1')
	h.assert_true(result.stopped == nil, program .. ': result.stopped is absent')
	h.assert_true(type(result.cap_pk) == 'string', program .. ': result.cap_pk is a string')

	-- Cap in terminal state.
	local cap = first(e.cvm,
		"select frame_stmt_idx, frame_gc from objects where object_pk = ?",
		result.cap_pk)
	h.assert_true(cap ~= nil, program .. ': cap row exists')
	h.assert_eq(tonumber(cap.frame_stmt_idx), 1, program .. ": cap.frame_stmt_idx == 1 (advanced past frame 0's reap)")
	h.assert_true(cap.frame_gc == nil, program .. ': cap.frame_gc is null (auto-nulled by advance)')

	-- Frame 0 reaped — cap has no children.
	local cap_kids = scalar(e.cvm,
		"select count(*) from objects where frame_parent = ?",
		result.cap_pk)
	h.assert_eq(cap_kids, 0, program .. ': cap has no children (frame 0 reaped)')

	-- Cap → bucket → scalar chain via refs.
	local bucket_pk = scalar(e.cvm,
		"select child from refs where parent = ? and key = 'b'",
		result.cap_pk)
	h.assert_true(bucket_pk ~= nil, program .. ": cap.bucket ref ('b') exists")

	local scalar_pk = scalar(e.cvm,
		"select child from refs where parent = ? and key = 'rv'",
		bucket_pk)
	h.assert_true(scalar_pk ~= nil, program .. ": cap.bucket.rv ref exists")

	-- Scalar's payload matches the source literal. Query the objects
	-- table directly for the typed scalar_* column; the `scalars`
	-- view coalesces to a single `value` column and loses type
	-- distinction.
	local payload = scalar(e.cvm,
		"select " .. column .. " from objects where object_pk = ?",
		scalar_pk)
	h.assert_eq(payload, expected_payload, program .. ": scalar's " .. column .. " matches source literal")

	-- No orphan state.
	h.assert_eq(scalar(e.cvm, 'select count(*) from needs_trace'), 0,
		program .. ': needs_trace empty')

	-- Six objects total: three core-role seeds + cap + bucket + scalar.
	h.assert_eq(scalar(e.cvm, 'select count(*) from objects'), 6,
		program .. ': six objects (core-role seeds + cap + bucket + scalar)')
end


h.test("'foo' (string): ScalarAtom sets frame rv; reap propagates it to cap.bucket.rv", function()
	assert_bare_scalar_program("'foo'", 'scalar_string', 'foo')
end)


h.test('42 (number): ScalarAtom sets frame rv; reap propagates it to cap.bucket.rv', function()
	assert_bare_scalar_program('42', 'scalar_number', 42)
end)


h.test('true (bool): ScalarAtom sets frame rv; reap propagates it to cap.bucket.rv', function()
	-- REAL affinity on scalar_bool stores 1/0 (SQLite booleans-as-integers).
	assert_bare_scalar_program('true', 'scalar_bool', 1)
end)
