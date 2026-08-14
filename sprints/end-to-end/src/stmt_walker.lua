--[[
{
	"module": "stmt_walker",
	"role": "Sprint-scoped Larry subclass. Rewrites Engine's `run` as a two-level stmt_idx-driven walk: `run` resolves the frame pk and hands off to `run_frame`, which loops on `record.stmt_idx < #ast`. Per statement: dispatches via the row-handler chain, then in one transaction advances stmt_idx AND deletes any child frame the dispatch may have pushed. When the frame's ast is exhausted, if the frame is the process's frame 0 (identified by `process_pk` being set on the row), a second transaction marks the process complete and deletes the frame row.",
	"exports": {
		"new": "(opts?) -> StmtWalker",
		"run": "(nothing) -> message — resolves frame_pk (fresh via create_frame_0, revival via get_latest_frame), delegates to run_frame, and returns a message with `complete` (0/1) and `message` (text or nil) reaped from the process record",
		"run_frame": "(frame_pk) -> process_pk|nil — dispatches every row of the given frame, advancing stmt_idx per row and shutting the process down when the frame is frame 0. Returns the frame's process pk (frame 0) or nil (sub-frame) so the caller can reap the process record."
	},
	"depends_on": ["larry", "cjson", "cvm.create_frame_0", "cvm.get_latest_frame"],
	"status": "sprint-scoped"
}
]]

--[[
# `stmt_walker`

Larry subclass. Overrides Engine's `run` with a two-level stmt_idx-driven walk (details in `run_frame` below). Uses the sprint's copy of `schema.sql` by default so the `complete` column on `processes` and the relaxed `processes_no_update` trigger are available.
]]
local cjson              = require('cjson')
local create_frame_0     = require('cvm.create_frame_0')
local get_latest_frame   = require('cvm.get_latest_frame')
local Larry              = require('larry')

-- cjson defaults to encoding empty Lua tables as `{}` (empty JSON
-- object). Under this sprint's schema the `ast` column is validated
-- to be a JSON array by trigger, so empty asts have to serialize as
-- `[]`. Flip the process-wide cjson mode here at module load so the
-- shared cjson.encode used by `cvm.create_frame_0` produces the right
-- shape without needing a sprint copy of that file. Bleed is
-- process-local; sprint tests run in their own processes.
cjson.encode_empty_table_as_object(false)

-- Sprint-scoped schema path — the modified copy under this sprint's
-- src/ that carries the `complete` / `message` columns on processes
-- and the relaxed `processes_no_update` trigger.
local function sprint_schema_path()
	local this_file = debug.getinfo(1, 'S').source:sub(2)
	local this_dir = this_file:match('(.*/)') or './'
	return this_dir .. 'schema.sql'
end

local StmtWalker = setmetatable({}, {__index = Larry})
StmtWalker.__index = StmtWalker

--[[
## `new`

Delegates to `Larry.new(opts)` and rewraps the metatable so the returned instance's identity is StmtWalker. Defaults `opts.cvm.schema_path` to the sprint's copy of `schema.sql`; caller-supplied `opts.cvm.schema` or `opts.cvm.schema_path` wins.

**Prepared statements.** Every SQL statement the walker issues is compiled once here at construction and reused for the walker's lifetime. Prepare-per-call is wasted work on a hot dispatch loop; the engine's SQL surface is small enough that a fixed named set covers it. Slots hung off `self.stmts`:

- `get_ast` — pull a frame's ast by its `object_pk`
- `get_stmt_idx` — read the live `stmt_idx` off a frame
- `advance_stmt_idx` — atomic in-place increment (`set stmt_idx = stmt_idx + 1`)
- `get_process` — read the `process` column off a frame (nil for sub-frames, set for frame 0)
- `delete_frame` — delete a specific frame by its `object_pk`
- `reap_process` — read a process row's `complete` and `message` for the caller
- `delete_process` — delete a process row by its `process_pk`

Two Lua-side statements got dissolved into SQL triggers as the design tightened:

- Child-frame cleanup on stmt_idx advance → `frames_delete_children_after_stmt_idx_update`. The `advance_stmt_idx` UPDATE alone atomically clears children.
- Marking `processes.complete = 1` on frame-0 delete → `processes_complete_after_frame_0_delete`. The `delete_frame` DELETE alone atomically flips the process.

Both moves let us drop savepoint dances on the Lua side; one SQL statement per moment, atomic in the DB layer.
]]
function StmtWalker.new(opts)
	opts = opts or {}
	opts.cvm = opts.cvm or {}

	if not opts.cvm.schema and not opts.cvm.schema_path then
		opts.cvm.schema_path = sprint_schema_path()
	end

	local walker = Larry.new(opts)
	setmetatable(walker, StmtWalker)

	walker.stmts = {
		get_ast = walker.cvm:prepare('select ast from objects where object_pk = ?'),
		get_stmt_idx = walker.cvm:prepare('select stmt_idx from objects where object_pk = ?'),
		advance_stmt_idx = walker.cvm:prepare('update objects set stmt_idx = stmt_idx + 1 where object_pk = ?'),
		get_process = walker.cvm:prepare('select process from objects where object_pk = ?'),
		delete_frame = walker.cvm:prepare('delete from objects where object_pk = ?'),
		reap_process = walker.cvm:prepare('select complete, message from processes where process_pk = ?'),
		delete_process = walker.cvm:prepare('delete from processes where process_pk = ?'),
	}

	-- Auto-delete the process record after the caller has had a chance
	-- to reap it. Default on — the typical case is "run to completion,
	-- collect the message, clean up." Set to false for keep-alive
	-- (dashboards, manufacturing pipelines that enumerate finished
	-- processes, tests that want to inspect the DB post-run).
	walker.auto_delete_process = true

	return walker
end

--[[
## `run`

**Override.** Resolves the frame pk — `create_frame_0` for a fresh run (`self.process_pk` nil), `get_latest_frame` for a revival — and hands it to `run_frame`. Fresh runs require `self.caspm` (populated via `load()`); revival runs read the program from the frame's `ast`.

Under the sprint's model there is no outer loop over frames yet — one call to `run_frame` drives one frame. Multi-frame execution shape lands after Miko's sub-frame explanation.
]]
function StmtWalker:run()
	local frame_pk

	if self.process_pk then
		frame_pk = get_latest_frame(self.cvm, self.process_pk)
	else
		if not self.caspm then
			error('engine:run() called before engine:load(); no program to execute')
		end

		frame_pk = create_frame_0(self.cvm, self)
		self.caspm = nil
	end

	local return_hash = {}

	local process_pk = self:run_frame(frame_pk)

	-- Reap the process's post-run state. For frame 0, run_frame returns
	-- the process pk it just marked complete; look up complete + message
	-- and drop them into the message the caller inspects. For a
	-- sub-frame (process_pk nil here), there's nothing at process level
	-- to reap — that frame's parent will handle its own reap when the
	-- parent's frame-0 ancestor completes.
	if process_pk then
		self.stmts.reap_process:bind_values(process_pk)

		for row in self.stmts.reap_process:nrows() do
			return_hash.complete = row.complete
			return_hash.message = row.message
		end

		self.stmts.reap_process:reset()

		-- Default Caspian behavior: auto-delete the process record now
		-- that the caller has what they need in the message. A
		-- caller (or a test) that wants the record retained for
		-- inspection sets walker.auto_delete_process = false before run.
		if self.auto_delete_process then
			self.stmts.delete_process:bind_values(process_pk)
			self.stmts.delete_process:step()
			self.stmts.delete_process:reset()
		end
	end

	return return_hash
end

--[[
## `run_frame`

Runs one frame from the top of its ast to the end.

**Per-statement advance.** For each row: try each handler in `self.row_handlers`; the first that returns true claims the row. Then one UPDATE on the frame bumps `stmt_idx` by 1. The `frames_delete_children_after_stmt_idx_update` SQL trigger fires as part of that same UPDATE and clears any child frame the dispatch may have pushed — advance-plus-cleanup are atomic at the SQL layer with no Lua-side savepoint needed. If no handler claims the row, raises `unrecognized_caspm`.

**Final (frame-0) shutdown.** After the ast is exhausted, if the frame's `process` column is set (i.e., this is frame 0 of a process), one DELETE on the frame row runs. The `processes_complete_after_frame_0_delete` trigger fires as part of that DELETE and flips `processes.complete = 1` — mark-complete and frame-delete are one atomic SQL operation. Sub-frames (`process` null) skip this step; their parent's `stmt_idx` advance is what deletes them (via the child-cleanup trigger).

**Mid-frame revival.** `stmt_idx` is read live from the DB via `get_stmt_idx()` each iteration; nothing resets it at entry. Fresh frames start at 0 (`create_frame_0`'s doing); revived frames pick up wherever they were when the last run left off. Every valid DB state is a valid resume state — a crash mid-dispatch just means the next run reads `stmt_idx` and continues from there.
]]
function StmtWalker:run_frame(frame_pk)
	local stmts = self.stmts

	-- Pull the ast out of the frame and parse it. One fetch, one decode.
	stmts.get_ast:bind_values(frame_pk)

	local ast_json

	for row in stmts.get_ast:nrows() do
		ast_json = row.ast
	end

	stmts.get_ast:reset()

	local ast = cjson.decode(ast_json)

	-- Shape check: ast should be a JSON array. Table + first key is
	-- either nil (empty) or numeric. Lua's `or` short-circuits, so
	-- `next(ast)` only runs when the type check passes.
	if type(ast) ~= 'table' or (next(ast) ~= nil and type(next(ast)) ~= 'number') then
		error('caspm_not_array: expected frame ast to decode as a JSON array')
	end

	-- Live read of the frame's stmt_idx. Called every time the loop
	-- wants the value (the condition, the array index) — the DB is the
	-- single source of truth. Optimization can come later.
	local function get_stmt_idx()
		stmts.get_stmt_idx:bind_values(frame_pk)

		local idx

		for row in stmts.get_stmt_idx:nrows() do
			idx = row.stmt_idx
		end

		stmts.get_stmt_idx:reset()

		return idx
	end

	while get_stmt_idx() < #ast do
		local found = false

		for _, handler in ipairs(self.row_handlers) do
			-- ast indices are 0-based in the DB (stmt_idx starts at 0);
			-- Lua arrays are 1-based, so `+ 1` at the site.
			if handler:handle(self, ast[get_stmt_idx() + 1]) then
				found = true

				-- Advance stmt_idx. The `frames_delete_children_after_
				-- stmt_idx_update` trigger fires as part of this UPDATE
				-- and clears any child frame the just-completed dispatch
				-- may have pushed. One statement, atomic at the SQL layer.
				stmts.advance_stmt_idx:bind_values(frame_pk)
				stmts.advance_stmt_idx:step()
				stmts.advance_stmt_idx:reset()

				break
			end
		end

		if not found then
			error('unrecognized_caspm: no handler in the chain recognized the input')
		end
	end

	-- Look up whether this frame is frame 0 (process_pk set) or a
	-- sub-frame (process_pk null). Only frame 0 runs the final
	-- shutdown transaction; sub-frames get deleted by their parent's
	-- per-statement transaction.
	local process_pk

	stmts.get_process:bind_values(frame_pk)

	for row in stmts.get_process:nrows() do
		process_pk = row.process
	end

	stmts.get_process:reset()

	if process_pk then
		-- Delete the frame. The `processes_complete_after_frame_0_delete`
		-- trigger fires as part of this DELETE and flips the process's
		-- `complete` to 1. One statement, atomic at the SQL layer.
		stmts.delete_frame:bind_values(frame_pk)
		stmts.delete_frame:step()
		stmts.delete_frame:reset()
	end

	-- Return the process pk for the frame just walked (nil for sub-frames,
	-- the frame-0 owner's process pk otherwise). Lets `run` reap the
	-- process's `complete` / `message` for the caller.
	return process_pk
end

return StmtWalker
