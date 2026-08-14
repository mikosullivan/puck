--[[
{
	"module": "engine",
	"role": "Caspian's runtime. `engine.new()` is the boot entry point — its first act is to open an CVM (via cvm.open()) and stash the SQLite handle as engine.cvm, so the runtime state store (CVM in V1) is live from the moment the engine exists. Host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(source) which transpiles + normalizes into a CaspM tree; run() walks that tree and dispatches each row via the row-handler chain-of-responsibility. Iteratively extended by registering Handler subclasses via the row-handler-chain API (add_handler / prepend_handler / remove_handler / clear_handlers / handlers) — no if/elseif branching in run_row.",
	"exports": {
		"new": "(opts?) -> Engine — opts.cvm is passed through to cvm.open() for the underlying CVM connection",
		"add_handler": "(handler) -> self — appends a handler to the end of self.row_handlers",
		"prepend_handler": "(handler) -> self — inserts a handler at index 1 of self.row_handlers (front of the chain, wins over stock handlers)",
		"remove_handler": "(handler) -> self — removes the first occurrence of `handler` by identity; raises `handler_not_found` if not in the chain",
		"clear_handlers": "() -> self — empties self.row_handlers (including stock handlers); subsequent rows raise unrecognized_caspm until at least one handler is added back",
		"handlers": "() -> array — returns a shallow copy of self.row_handlers, in chain order (index 1 is checked first at dispatch time)"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Tests wire a FakeOutput; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface.",
	"dispatch_contract": "Two raise sites, both with `unrecognized_` prefix so grep finds them: `unrecognized_caspm` (statement row that no registered Handler in row_handlers claimed — surfaced by run_row with the row-head atom's key set appended for diagnostic detail), `unrecognized_atom_kind` (value-producing atom whose kind key isn't in the value dispatcher). Adding a new construct = registering a Handler subclass via engine:add_handler and re-running the failing program."
}
]]

--[[
# Engine

Caspian's runtime. A host constructs an engine with `engine.new()` — which
opens an CVM (the runtime state store — CVM in V1; see
[cvm](https://www.puck.uno/requirements/cvm/)) via `cvm.open()`
and stashes the SQLite handle as `engine.cvm`. From that moment on, every
runtime state read or write goes through that handle: objects, frames,
frame_locals, roles, listeners — everything the CVM schema tracks.

The CVM defaults to `:memory:` — pass `opts.cvm = {path = '/some/file.db'}`
to `engine.new()` to open a file-backed one, or `opts.cvm = {path = ...,
schema = ...}` to override the schema (see [cvm.lua](../engine/cvm.lua)
for the full option set).

The host then wires whatever capabilities the program needs
(`engine.stdout = ...`, `engine.debugger = ...`), feeds the program source
through `engine:load(source)` — which transpiles + normalizes it into a
CaspM tree — and walks that tree with `engine:run()`.

Built iteratively. Any atom kind, bareword command, or row-head shape the
dispatcher doesn't recognize raises a specific `unrecognized_*` error
naming the missing piece, so the walking-skeleton iteration loop always
has a clear signal about what to build next.
]]

local cjson              = require('cjson')
local transpiler         = require('transpiler')
local normalize          = require('normalize')
local cvm                = require('cvm.open')
local create_frame_0     = require('cvm.create_frame_0')
local get_latest_frame   = require('cvm.get_latest_frame')
local dispatch           = require('dispatch')
local handlers           = require('handlers')

local M = {}
M.__index = M

--[[
## `atom_keys`

`atom_keys(atom)` renders an atom's key set as a deterministic
comma-separated string for use in error messages. Keys are sorted so the
`unrecognized_*` raises match across runs regardless of hash iteration
order — tests can pattern-match on the raise text without pre-sorting.
]]
local function atom_keys(atom)
	local keys = {}

	for k, _ in pairs(atom) do
		table.insert(keys, k)
	end

	table.sort(keys)
	return table.concat(keys, ', ')
end

--[[
## `debug_log`

`debug_log(engine, entry)` appends `entry` to `engine.debugger` if one
is attached; no-op otherwise. Every raise path and every dispatch
appends an entry so a coder attaching a Lua sequence to
`engine.debugger` can trace exactly what the engine did in what order.

Named `debug_log` rather than `debug` to avoid shadowing Lua's standard
`debug` table.

Each entry is a plain hash of whatever the call site chose to record —
`{kind = ..., source_length = ..., ...}` — no required fields, no
growing method surface. The array shape is the whole contract.
]]
local function debug_log(engine, entry)
	if engine.debugger then
		table.insert(engine.debugger, entry)
	end
end

--[[
## `new`

`engine.new(opts?)` is the boot entry point. Its first act is to open
an CVM (via `cvm.open(opts and opts.cvm)`) and stash the returned
SQLite handle as `engine.cvm`, so the runtime state store is live from
the moment the engine exists. Host wiring slots and walking-skeleton
load-artifact slots start nil:

- **`cvm`** — the open SQLite handle for the CVM — the
  runtime state store. See [cvm.lua](../engine/cvm.lua) for the
  open API and [cvm.sql](../engine/cvm.sql) for the schema.
  Every runtime state read or write goes through this handle.
- **`stdout`, `debugger`** — nil at construction. The host attaches
  capabilities by plain field assignment before or after loading, in any
  order.
- **`transpiler`** — the canonical Caspian transpiler module, wired at
  construction. Placeholder for the eventual pluggable-frontend seam
  the engine will grow when it consults this slot at
  [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/#this-is-where-transpilation-happens).
  Today nothing reads this slot; `load()` still reaches for the
  transpiler module directly. Reassigning the slot doesn't yet change
  behavior. Added ahead of the wiring so downstream sprints can rely on
  the field's presence.
- **`process_pk`** — nil at construction. Fresh vs revival signal for
  `run()`. Host sets it to an existing process pk before calling
  `run()` to revive that process (dispatch resumes from the process's
  deepest live frame). Leaves it nil for a fresh run (dispatch pushes
  frame 0 into a new process). Consulted only by `run()`.
- **`caspm`** — nil at construction. Populated by `engine:load` with the
  normalized program that gets stashed into frame 0's `ast` on push.
  Input-staging slot with a short lifetime: `create_frame_0` reads it
  and JSON-encodes it into the DB frame, then `run()` nils it out so
  the loaded program has one source of truth (the DB frame's ast), not
  two. Not populated on revival runs.
- **`row_handlers`** — the row-head dispatch chain. Populated at
  construction from `handlers.stock_instances()` — the aggregator at
  [src/engine/handlers/init.lua](../engine/handlers/init.lua) that
  hands back a fresh instance of every stock Handler subclass. Hosts
  extend the chain via `engine:add_handler(h)`, `engine:prepend_handler(h)`,
  `engine:remove_handler(h)`, `engine:clear_handlers()`, and inspect it
  via `engine:handlers()`. Direct mutation of the underlying array is
  not the sanctioned surface — the engine reserves the right to change
  the internal representation. Empty chain (no stock handlers yet + no
  host additions) means every row raises `unrecognized_caspm` from
  dispatch's fallback.

`opts.cvm` (when supplied) is passed through to `cvm.open()` — see
that function's signature for the fields (`path`, `schema`, `schema_path`).
Omit `opts` entirely for the common case: a fresh in-memory CVM. A
program that doesn't need a given host capability doesn't force its host
to provide one; reaching for an unwired capability raises at the fire
site.
]]
function M.new(opts)
	opts = opts or {}

	local engine = setmetatable({
		cvm                  = cvm.open(opts.cvm),
		stdout               = nil,
		debugger             = nil,
		transpiler           = transpiler,
		process_pk           = nil,
		caspm                = nil,
		row_handlers         = {},
		auto_delete_process  = true,
	}, M)

	-- Every SQL statement the walker issues gets compiled once here and
	-- reused for the engine's lifetime. Prepare-per-call is wasted work
	-- on a hot dispatch loop; the walker's SQL surface is small enough
	-- that a fixed named set covers it.
	engine.stmts = {
		get_ast          = engine.cvm:prepare('select ast from objects where object_pk = ?'),
		get_stmt_idx     = engine.cvm:prepare('select stmt_idx from objects where object_pk = ?'),
		advance_stmt_idx = engine.cvm:prepare('update objects set stmt_idx = stmt_idx + 1 where object_pk = ?'),
		get_process      = engine.cvm:prepare('select process_pk from objects where object_pk = ?'),
		delete_frame     = engine.cvm:prepare('delete from objects where object_pk = ?'),
		reap_process     = engine.cvm:prepare('select complete, message from processes where process_pk = ?'),
		delete_process   = engine.cvm:prepare('delete from processes where process_pk = ?'),
	}

	-- Wire the stock handler roster through the public API so even the
	-- engine's own constructor self-hosts on add_handler.
	for _, handler in ipairs(handlers.stock_instances()) do
		engine:add_handler(handler)
	end

	return engine
end

--[[
## `load`

`engine:load(source)` takes a Caspian source string, transpiles it into
CaspJ, normalizes that into CaspM, and stashes the resulting CaspM on
`self.caspm`. The intermediate source and CaspJ are not retained —
`run()` only needs the normalized form, and any inspector who wants to
see the earlier representations can call `transpiler.transpile` and
`normalize.normalize` themselves against the same source. Appends a
`{kind = 'loaded', source_length = N}` entry to the debugger if one is
attached.

Must be called before `run()`; calling `run()` on an engine that hasn't
loaded anything raises `engine:run() called before engine:load()`.
]]
function M:load(source)
	self.caspm = normalize.normalize(transpiler.transpile(source))

	debug_log(self, {kind = 'loaded', source_length = #source})

	return
end

--[[
## `run`

Resolves frame 0 (fresh or revival, per the `process_pk` slot), delegates to `run_frame` to walk it, then reaps the process's `complete` + `message` into a return hash. If `self.auto_delete_process` is true (the default), deletes the process record after the reap.

**Fresh vs revival.** If `self.process_pk` is nil, `run` treats the run as fresh: `create_frame_0` invents a new process, encodes `self.caspm` into frame 0's `ast`, and pushes the frame. `self.caspm` is nil'd immediately after — once the CaspM lives in the DB frame, the Lua-side staging slot is spent, and keeping it around would give the loaded program two sources of truth. If `self.process_pk` is set, `run` treats the run as revival: `get_latest_frame` finds the deepest live frame in that process; `self.caspm` is not consulted (the program lives in the DB frame, not on the engine).

**Precondition.** Fresh runs require `self.caspm` to be set (via `engine:load(source)` before `run()`); missing raises `engine:run() called before engine:load()`. Revival runs have no such requirement.

**Return value.** A hash with `complete` (0 or 1) and `message` (text or nil) reaped from the process record before its auto-delete. Callers who set `auto_delete_process = false` before `run()` can also read the row directly from the DB after `run()` returns.
]]
function M:run()
	local frame_pk

	if self.process_pk then
		frame_pk = get_latest_frame(self.cvm, self.process_pk)
	else
		if not self.caspm then
			error("engine:run() called before engine:load(); no program to execute")
		end

		frame_pk = create_frame_0(self.cvm, self)
		self.caspm = nil
	end

	local message = {}

	local process_pk = self:run_frame(frame_pk)

	-- Reap the process's post-run state. For frame 0, run_frame returns
	-- the process pk it just marked complete; look up complete + message
	-- and drop them into the return hash the caller inspects. For a
	-- sub-frame (process_pk nil here), there's nothing at process level
	-- to reap — that frame's parent handles its own reap when the
	-- parent's frame-0 ancestor completes.
	if process_pk then
		self.stmts.reap_process:bind_values(process_pk)

		for row in self.stmts.reap_process:nrows() do
			message.complete = row.complete
			message.message = row.message
		end

		self.stmts.reap_process:reset()

		-- Default: auto-delete the process record now that the caller
		-- has what they need in the return hash. Callers that want the
		-- record retained for inspection set auto_delete_process = false
		-- before run.
		if self.auto_delete_process then
			self.stmts.delete_process:bind_values(process_pk)
			self.stmts.delete_process:step()
			self.stmts.delete_process:reset()
		end
	end

	return message
end

--[[
## `run_frame`

Runs one frame from the top of its ast to the end.

**Per-statement advance.** For each row: hand it to `run_row` (which walks the row-handler chain via `dispatch`). If dispatch claims the row, one UPDATE on the frame bumps `stmt_idx` by 1. The `frames_delete_children_after_stmt_idx_update` SQL trigger fires as part of that UPDATE and clears any child frame the dispatch may have pushed — advance-plus-cleanup are atomic at the SQL layer with no Lua-side savepoint needed. If no handler claims the row, `run_row` raises `unrecognized_caspm` (with an atom-keys reshape).

**Final (frame-0) shutdown.** After the ast is exhausted, if the frame's `process` column is set (i.e., this is frame 0 of a process), one DELETE on the frame row runs. The `processes_complete_after_frame_0_delete` trigger fires as part of that DELETE and flips `processes.complete = 1` — mark-complete and frame-delete are one atomic SQL operation. Sub-frames (`process` null) skip this step; their parent's `stmt_idx` advance is what deletes them (via the child-cleanup trigger).

**Mid-frame revival.** `stmt_idx` is read live from the DB via `get_stmt_idx()` each iteration; nothing resets it at entry. Fresh frames start at 0 (`create_frame_0`'s doing); revived frames pick up wherever they were when the last run left off. Every valid DB state is a valid resume state.

**Returns** the process pk for the frame just walked (nil for sub-frames, the frame-0 owner's process pk otherwise). Lets `run` reap the process record.
]]
function M:run_frame(frame_pk)
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
	-- either nil (empty) or numeric. The ast_valid_insert trigger
	-- enforces this at write time; the Lua check is defense-in-depth.
	if type(ast) ~= 'table' or (next(ast) ~= nil and type(next(ast)) ~= 'number') then
		error('caspm_not_array: expected frame ast to decode as a JSON array')
	end

	-- Live read of the frame's stmt_idx. Called every time the loop
	-- wants the value (the condition, the array index) — the DB is the
	-- single source of truth.
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
		-- ast indices are 0-based in the DB (stmt_idx starts at 0);
		-- Lua arrays are 1-based, so `+ 1` at the site.
		self:run_row(ast[get_stmt_idx() + 1])

		-- Advance stmt_idx. The frames_delete_children_after_stmt_idx_
		-- update trigger fires as part of this UPDATE and clears any
		-- child frame the just-completed dispatch may have pushed.
		stmts.advance_stmt_idx:bind_values(frame_pk)
		stmts.advance_stmt_idx:step()
		stmts.advance_stmt_idx:reset()
	end

	-- Look up whether this frame is frame 0 (process_pk set) or a
	-- sub-frame (process_pk null). Only frame 0 runs the final shutdown;
	-- sub-frames get deleted by their parent's per-statement UPDATE.
	local process_pk

	stmts.get_process:bind_values(frame_pk)

	for row in stmts.get_process:nrows() do
		process_pk = row.process_pk
	end

	stmts.get_process:reset()

	if process_pk then
		-- Delete the frame. The processes_complete_after_frame_0_delete
		-- trigger fires as part of this DELETE and flips the process's
		-- complete to 1. One statement, atomic at the SQL layer.
		stmts.delete_frame:bind_values(frame_pk)
		stmts.delete_frame:step()
		stmts.delete_frame:reset()
	end

	return process_pk
end

--[[
## `run_row`

`engine:run_row(row)` offers the row to each Handler in `self.row_handlers` via the shared [dispatch](../engine/dispatch.lua) function. First handler to return `true` wins; if none does, dispatch raises `unrecognized_caspm`. Handler raises propagate through — dispatch doesn't catch.

This method wraps dispatch's raise with a more diagnostic message: if dispatch raises `unrecognized_caspm`, `run_row` catches and re-raises with the row-head atom's key set appended, so the walking-skeleton iteration knows what row shape to add support for next. A handler's own raise (anything other than `unrecognized_caspm`) propagates as-is.

New row-head shapes land as new Handler subclasses registered into `self.row_handlers` — no if/elseif branches to grow here.
]]
function M:run_row(row)
	local ok, err = pcall(dispatch, self.row_handlers, self, row)

	if ok then
		return
	end

	-- Reshape the fallback raise with atom-keys diagnostic; propagate
	-- everything else as-is (handler raises, other errors).
	if type(err) == 'string' and err:find('unrecognized_caspm', 1, true) then
		debug_log(self, {kind = 'raised', reason = 'unrecognized_caspm', head = row[1]})
		error("unrecognized_caspm: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(row[1]) .. "}")
	end

	error(err, 0)
end

--[[
## `engine:add_handler` — append a handler to the row-handler chain

Appends `handler` to `self.row_handlers`. Chain order matters: handlers are consulted in order at dispatch time, first one to claim the row wins. Appending puts the new handler behind everything already registered (stock handlers included). Returns `self` for chaining.
]]
function M:add_handler(handler)
	table.insert(self.row_handlers, handler)
	return self
end

--[[
## `engine:prepend_handler` — insert a handler at the front of the row-handler chain

Puts `handler` at index 1 of `self.row_handlers`. First handler consulted at dispatch time — wins over anything already registered, including the stock handlers wired at construction. Returns `self` for chaining.
]]
function M:prepend_handler(handler)
	table.insert(self.row_handlers, 1, handler)
	return self
end

--[[
## `engine:remove_handler` — remove a handler by identity

Removes the first occurrence of `handler` from `self.row_handlers` by identity (`==`). If `handler` is not in the chain, raises `handler_not_found: handler is not in the chain` — fail loudly rather than silently no-op, so a mistyped reference or double-remove surfaces at the call site. Returns `self` for chaining.
]]
function M:remove_handler(handler)
	for i, h in ipairs(self.row_handlers) do
		if h == handler then
			table.remove(self.row_handlers, i)
			return self
		end
	end

	error("handler_not_found: handler is not in the chain")
end

--[[
## `engine:clear_handlers` — empty the row-handler chain

Removes every handler from `self.row_handlers`, including the stock handlers wired at construction. After a `clear_handlers` every row raises `unrecognized_caspm` at dispatch time until at least one handler is added back. Returns `self` for chaining.
]]
function M:clear_handlers()
	self.row_handlers = {}
	return self
end

--[[
## `engine:handlers` — read the current row-handler chain

Returns a shallow copy of `self.row_handlers` as a new array, so inspection doesn't hand out a reference callers could mutate to bypass the public API. Chain order is preserved — index 1 is the first handler consulted at dispatch time.

Callers that want to mutate the chain go through `add_handler`, `prepend_handler`, `remove_handler`, or `clear_handlers`.
]]
function M:handlers()
	local copy = {}

	for i, h in ipairs(self.row_handlers) do
		copy[i] = h
	end

	return copy
end

--[[
## `eval`

`engine:eval(atom)` evaluates a value-producing atom to a Caspian
value. Currently handles one atom shape — `{v: value}` (the normalized
string / number literal shape) — and returns the value directly.

Anything else appends a `raised` entry to the debugger and raises
`unrecognized_atom_kind` with the atom's key set in the message so the
walking-skeleton iteration knows what atom kind to add support for
next.
]]
function M:eval(atom)
	if atom.v ~= nil then
		return atom.v
	end

	local keys = atom_keys(atom)
	debug_log(self, {kind = 'raised', reason = 'unrecognized_atom_kind', keys = keys})
	error("unrecognized_atom_kind: cannot evaluate atom — no rule handles atoms with keys {" .. keys .. "}")
end

return M
