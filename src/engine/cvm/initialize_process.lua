--[[
{
	"module": "initialize_process",
	"role": "Sprint frame-0 routine: creates a new process row in the CVM and returns its pk. One INSERT — text UUID defaulted from randomblob, RETURNING hands the fresh pk back so no follow-up query is needed. Split out from the fresh-case flow so each piece is independently testable; the caller (a future Create Frame 0 routine) combines this with the frame INSERT in a single transaction.",
	"exports": {
		"(function)": "(db) -> process_pk"
	},
	"status": "sprint-scoped; not yet promoted"
}
]]

--[[
# `initialize_process`

Creates one new process row in the CVM and returns its pk. Read/write — one INSERT. No frame is pushed; that's a separate routine.

~~~sql
insert into processes default values
returning process_pk;
~~~

The `processes.process_pk` column is text UUID under the sprint's schema, defaulted from `randomblob`; the `default values` INSERT triggers that default. `RETURNING` hands the fresh pk back in the same round trip so the caller doesn't have to re-query.

**Return value:** the new row's `process_pk` (a UUID4-shaped text string).

**Why this is its own routine.** The fresh-case flow does two INSERTs — a process row and frame 0 — and wants both in one transaction. Splitting `initialize_process` out lets each piece be tested independently; the future Create Frame 0 routine composes this with the frame INSERT under a `begin;`/`commit;` wrap.
]]
local function initialize_process(db)
	local process_pk

	for row in db:nrows("insert into processes default values returning process_pk") do
		process_pk = row.process_pk
	end

	return process_pk
end

return initialize_process
