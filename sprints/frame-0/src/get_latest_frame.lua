--[[
{
	"module": "get_latest_frame",
	"role": "Sprint frame-0 routine: returns the deepest on-stack frame in the given process. Read-only. Only frame 0 binds to `processes` via `process`; sub-frames chain via `frame_parent`. The routine finds frame 0 with one indexed lookup, then walks the parent-inverse chain in a Lua loop, one indexed hop per step. Raises get_latest_frame_process_not_found if the process pk isn't in the processes table. Returns nil if the process exists but has no frames.",
	"exports": {
		"(function)": "(db, process_pk) -> frame_pk | nil"
	},
	"status": "sprint-scoped; not yet promoted"
}
]]

--[[
# `get_latest_frame`

Given a CVM db handle and a process pk, returns the deepest on-stack frame in that process. Read-only — no writes.

**Return values:**

- Process exists, ≥1 on-stack frame → the frame's `object_pk` (frame 0's pk if that's the only frame; otherwise the deepest child).
- Process exists, 0 on-stack frames → `nil`. Cleanup of empty processes is done later, not by this routine.
- Process doesn't exist → raises `get_latest_frame_process_not_found` naming the pk the caller passed. A caller told to look inside a process that isn't in the DB has a bug — fail loudly at the earliest layer that can detect it (per [invariant violations](https://puck.uno/requirements/concepts#invariant-violations-crash-the-program)).

**How the deepest frame is found.** Only frame 0 of a process carries `process`; every sub-frame carries `frame_parent` pointing at the frame that pushed it. So the walk is:

1. `select object_pk from objects where primitive = 'f' and process = ?` — one indexed lookup, returns frame 0 (or nothing if the process is empty).
2. Loop: `select object_pk from objects where primitive = 'f' and frame_parent = ?` — one indexed lookup per hop, taking `object_pk` from the previous step as the parent. Under the current push model there's at most one such child per frame.
3. Terminate when the child query returns nothing — the last frame with no child is the deepest.

Rowid ordering plays no role — the chain is explicit.

**Why binding only frame 0 to the process.** Binding every frame to a single process forecloses future systems where multiple processes share the tail of a call chain (fan-in). Binding only frame 0 leaves that door open — future work can spec how a shared child frame is discovered from more than one process anchor without any schema change to sub-frames.

**Why a loop and not recursion.** Semantically identical here. A loop reads more directly and avoids Lua's stack cost for chains that could get deep. If a future design admits genuine tree-shaped stacks (multiple children per frame), recursion or an explicit worklist would replace the loop.

**What this routine doesn't do:** the fresh case — no `processes` row yet, need to create one and push frame 0. That's split across `initialize_process` and a future Create Frame 0 routine; see the sprint's [Create Frame 0](../index.md#create-frame-0) section for the design.
]]
local function get_latest_frame(db, process_pk)
	-- 1. Verify the process exists. Distinct from "process exists but
	--    has no frames" (which is a valid return-nil case); the
	--    process-not-found case is a caller-side bug.
	local process_exists = false

	local exists_stmt = db:prepare(
		"select 1 from processes where process_pk = ?"
	)
	exists_stmt:bind_values(process_pk)

	for _ in exists_stmt:nrows() do
		process_exists = true
	end

	exists_stmt:reset()

	if not process_exists then
		error(
			"get_latest_frame_process_not_found: no processes row with pk " ..
			tostring(process_pk)
		)
	end

	-- 2. Find frame 0 — the one frame in this process that binds to
	--    `processes` directly. At most one row can match under the
	--    convention (only frame 0 sets `process`).
	local frame_0_pk

	local frame_0_stmt = db:prepare(
		"select object_pk from objects " ..
		"where primitive = 'f' and process = ?"
	)
	frame_0_stmt:bind_values(process_pk)

	for row in frame_0_stmt:nrows() do
		frame_0_pk = row.object_pk
	end

	frame_0_stmt:reset()

	if frame_0_pk == nil then
		return nil
	end

	-- 3. Walk down through `frame_parent` inverse — each hop finds
	--    the child of the current frame. Stop when there's no child;
	--    that frame is the deepest on the stack.
	local current = frame_0_pk

	local child_stmt = db:prepare(
		"select object_pk from objects " ..
		"where primitive = 'f' and frame_parent = ?"
	)

	while true do
		local next_pk

		child_stmt:bind_values(current)

		for row in child_stmt:nrows() do
			next_pk = row.object_pk
		end

		child_stmt:reset()

		if next_pk == nil then
			return current
		end

		current = next_pk
	end
end

return get_latest_frame
