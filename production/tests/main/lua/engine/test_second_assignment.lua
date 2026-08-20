--[[
{
	"spec": "test_second_assignment",
	"role": "End-to-end tests for rebinding a local. Runs `$x = 1\\n$x = 2` and asserts the walker drains the orphaned first-assignment scalar between statements, then drains the whole graph after frame 0's tail reap. Post-run: run() returns complete=1, the cap sits at its born-terminal state, refs is empty, and needs_trace is empty. Also installs a test-only trigger on needs_trace that mirrors every mark into debug_log, giving the suite a five-record trace of the drain's traversal for the two assertions at the bottom. See the test-only-triggers doc for the pattern rationale."
}
]]

--[[
# `test_second_assignment`

Assertions for the rebind path — `$x = 1` followed by `$x = 2`.

- Statement 0: `$x = 1` dispatches. Handler materializes scalar_1 and adds the frame_0 → bucket → scopes → scopes[0] → (key `x`) → scalar_1 chain. Nothing is orphaned yet; needs_trace stays empty.
- Statement 1: `$x = 2` dispatches. The upsert_ref path UPDATEs the existing `x` ref's `child` column from scalar_1 to scalar_2. The `refs_mark_needs_trace_after_child_update` trigger inserts scalar_1 into needs_trace.
- Between-statement drain (in `run_frame`): scalar_1 has no incoming refs (the ref was updated to point at scalar_2, not deleted, but the OLD child is what got marked and it now has no incoming ref). The drain reaps scalar_1; the needs_trace row cascades away with the objects row.
- Frame 0 hits terminal, `run_frame` reaps it, and the tail drain unwinds the orphaned bucket → scopes → scopes[0] → scalar_2 chain via successive reap-and-cascade cycles.
- End state: cap alone at (`stmt_idx = 0`, `gc = null`, no children); refs empty; needs_trace empty.

## Test-only trigger on `needs_trace`

Every engine.new() call in this file goes through the local `new_engine()` shim, which installs a test-only trigger on `needs_trace` that mirrors each mark into `debug_log`. The trigger is not part of the schema — it's a runtime probe added by test code — see [test-only-triggers](https://puck.uno/production/requirements/cvm/test-only-triggers) for the strategy and the format guarantees (`mark <marked_object_pk> <scalar_value_or_null>`, whole-number values rendered by `format('%g')` so they don't drag a trailing `.0`).
]]

local h      = require('helpers')
local engine = require('engine')


--[[
Diagnostic trigger — TEST-ONLY, NOT PRODUCTION SCHEMA. Installed on
every engine.cvm this file constructs. On INSERT INTO needs_trace it
writes a debug_log row scoped to the current process (`new.process_pk`
IS the cap's object_pk, so it satisfies debug_log's cap-only FK) with
a note of the form `mark <marked_object_pk> <scalar_value_or_null>`.

Notes on the value expression:

- `format('%g', scalar_value)` renders the number without a
  meaningless trailing '.0'. The scalar_value column stores REAL
  because cjson.decode always returns Lua floats regardless of
  whether the JSON text had a decimal point — so `cast(x as text)`
  would produce '1.0' / '2.0' for whole values. Caspian's numbers are
  one type; the decimal specifier doesn't buy anything. `%g` collapses
  '1.0' → '1' and preserves '1.5' as '1.5'.

- Explicit `case when scalar_value is null then 'null'`, NOT
  `coalesce(format(...), 'null')`: SQLite's `format('%g', NULL)`
  returns the STRING '0' rather than NULL, so a coalesce over it
  never falls through and every non-scalar mark would render as ' 0'
  instead of ' null'. The is-null case up front dodges that.
]]
local NEEDS_TRACE_DEBUG_TRIGGER = [[
	create trigger sprint_needs_trace_write_debug_log
	after insert on needs_trace
	begin
		insert into debug_log (object_pk, note)
		values (
			new.process_pk,
			'mark ' || new.object_pk || ' ' || (
				select case
					when scalar_value is null then 'null'
					else format('%g', scalar_value)
				end
				from objects where object_pk = new.object_pk
			)
		);
	end;
]]

--[[
Fresh engine with the diagnostic trigger installed. Every test in
this file uses this shim instead of the raw `engine.new()` so
debug_log carries a per-mark trace for every run.
]]
local function new_engine()
	local e = engine.new()
	local rc = e.cvm:exec(NEEDS_TRACE_DEBUG_TRIGGER)
	assert(rc == 0, 'test-only diagnostic trigger install failed: ' .. tostring(e.cvm:errmsg()))
	return e
end


-- Fetch a single scalar from a one-row-one-column query. Returns nil
-- if no rows.
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


local SOURCE = '$x = 1\n$x = 2'


h.test('$x = 1 ; $x = 2: run() returns complete = 1', function()
	local e = new_engine()
	e:load(SOURCE)
	local result = e:run()

	h.assert_true(type(result) == 'table', 'run() should return a table')
	h.assert_eq(result.complete, 1, 'result.complete should be 1')
	h.assert_not_nil(result.cap_pk, 'result.cap_pk should be set')
end)

h.test('$x = 1 ; $x = 2: cap sits at its born-terminal state', function()
	local e = new_engine()
	e:load(SOURCE)
	local result = e:run()

	local stmt_idx = scalar(e.cvm,
		"select stmt_idx from objects where object_pk = ?",
		result.cap_pk)
	h.assert_eq(tonumber(stmt_idx), 0, 'cap stmt_idx should be 0')

	local gc = scalar(e.cvm,
		"select gc from objects where object_pk = ?",
		result.cap_pk)
	h.assert_true(gc == nil, 'cap gc should be null')

	local kids = scalar(e.cvm,
		"select count(*) from objects where parent_frame = ?",
		result.cap_pk)
	h.assert_eq(kids, 0, 'cap should have no children (frame 0 reaped)')
end)

h.test('$x = 1 ; $x = 2: needs_trace is empty at end of run', function()
	local e = new_engine()
	e:load(SOURCE)
	e:run()

	local marks = scalar(e.cvm, 'select count(*) from needs_trace')
	h.assert_eq(marks, 0, 'needs_trace should have no rows after the drain sweeps the orphaned graph')
end)

h.test('$x = 1 ; $x = 2: refs is empty at end of run', function()
	local e = new_engine()
	e:load(SOURCE)
	e:run()

	local refs = scalar(e.cvm, 'select count(*) from refs')
	h.assert_eq(refs, 0, 'refs should be empty after the drain reaps the whole orphaned chain')
end)

h.test('$x = 1 ; $x = 2: only cap + three core-role seeds remain in objects', function()
	local e = new_engine()
	e:load(SOURCE)
	e:run()

	local total = scalar(e.cvm, 'select count(*) from objects')
	h.assert_eq(total, 4, 'expected four object rows (engine/cache/user seeds + cap) after the drain')

	local core_role_count = scalar(e.cvm, 'select count(*) from objects where core_role is not null')
	h.assert_eq(core_role_count, 3, 'expected the three core-role seeds')

	local cap_count = scalar(e.cvm, "select count(*) from objects where process_cap = 1")
	h.assert_eq(cap_count, 1, 'expected one cap frame (the process anchor)')
end)

h.test('$x = 1 ; $x = 2: both scalar values are gone from objects', function()
	local e = new_engine()
	e:load(SOURCE)
	e:run()

	local ones = scalar(e.cvm,
		"select count(*) from objects where scalar_type = 'n' and scalar_value = 1")
	h.assert_eq(ones, 0, 'scalar_1 (the orphaned first-assignment value) should be reaped')

	local twos = scalar(e.cvm,
		"select count(*) from objects where scalar_type = 'n' and scalar_value = 2")
	h.assert_eq(twos, 0, 'scalar_2 (the surviving second-assignment value) should be reaped when frame 0 is')
end)


-- ============================================================
-- debug_log — assertions against the test-only trigger's trace
-- ============================================================

h.test('$x = 1 ; $x = 2: debug_log records the scalar_1 and scalar_2 marks', function()
	-- The test-only diagnostic trigger writes `mark <object_pk> <value>`
	-- for every insert into needs_trace. Every marked object across
	-- the whole run leaves a trace here — we assert the two we care
	-- most about are present:
	--   1. scalar_1 — marked when `$x = 2` upserted over `$x = 1`.
	--      Note ends with " 1" (the trigger uses format('%g') so
	--      whole values render without a trailing '.0').
	--   2. scalar_2 — marked during the tail drain as the orphaned
	--      chain unwinds. Note ends with " 2".
	local e = new_engine()
	e:load(SOURCE)
	local result = e:run()

	local ones = scalar(e.cvm,
		"select count(*) from debug_log where object_pk = ? and note like '% 1'",
		result.cap_pk)
	h.assert_eq(tonumber(ones), 1, 'expected one debug_log entry for the scalar_1 mark')

	local twos = scalar(e.cvm,
		"select count(*) from debug_log where object_pk = ? and note like '% 2'",
		result.cap_pk)
	h.assert_eq(tonumber(twos), 1, 'expected one debug_log entry for the scalar_2 mark')

	-- Every debug_log entry the trigger wrote should be scoped to
	-- this run's cap; nothing else should be logging against it.
	local total = scalar(e.cvm,
		"select count(*) from debug_log where object_pk = ?",
		result.cap_pk)
	h.assert_true(tonumber(total) >= 2, 'expected at least the two scalar marks in debug_log')
end)

h.test('$x = 1 ; $x = 2: debug_log holds EXACTLY these five records in insert order', function()
	-- Stricter than the presence check above — asserts the full
	-- five-record contents in the order the drain wrote them:
	--
	--   1  scalar_1 marked when `$x = 2` upserted over `$x = 1`.
	--   null  bucket marked when frame 0's outgoing ref cascaded on reap.
	--   null  scopes marked when the drain reaped the bucket.
	--   null  scopes[0] marked when the drain reaped the scopes array.
	--   2  scalar_2 marked when the drain reaped scopes[0], cascading
	--      the `x` ref that pointed at scalar_2.
	--
	-- The order is a load-bearing signal about how the drain
	-- traverses the graph: (a) between-statement drain reaps
	-- scalar_1 the instant the upsert fires; (b) frame-0 reap
	-- cascades one ref, marking the bucket; (c) the tail drain
	-- reaps bucket → scopes → scopes[0] → scalar_2 in that
	-- sequence, marking each next hop as its parent's cascade
	-- fires. If the drain traversal changes, this test's expected
	-- sequence needs to change with it — treat that as the
	-- diagnostic signal it's meant to be.
	local e = new_engine()
	e:load(SOURCE)
	e:run()

	local values = {}

	for row in e.cvm:nrows(
		"select note from debug_log order by entry_pk")
	do
		-- Note format: 'mark <uuid> <value>'. The last whitespace-
		-- delimited chunk is the value ('1', 'null', '2', etc.).
		table.insert(values, row.note:match(' (%S+)$'))
	end

	h.assert_eq(#values, 5,       'expected exactly five debug_log entries')
	h.assert_eq(values[1], '1',    'entry 1: scalar_1 mark with value 1')
	h.assert_eq(values[2], 'null', 'entry 2: bucket mark (null — not a scalar)')
	h.assert_eq(values[3], 'null', 'entry 3: scopes-array mark (null)')
	h.assert_eq(values[4], 'null', 'entry 4: scopes[0] hash mark (null)')
	h.assert_eq(values[5], '2',    'entry 5: scalar_2 mark with value 2')
end)
