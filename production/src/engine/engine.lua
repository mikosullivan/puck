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
local cvm_open           = require('cvm.open')
local Cvm                = require('cvm')
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
- **`data`** — the CVM data-access layer (an instance of `cvm`) wrapping the SQLite handle. Every method callers reach for on `engine.data` (`add_scalar`, `add_bucket`, `object_by_pk`, etc.) operates via prepared statements over the schema. Populated at construction.
- **`cap_pk`** — nil at construction. `run()` sets it to the process's cap-frame pk (the top of the call stack; its `object_pk` IS the process identity). Callers can inspect this after `run()` returns to reach the resulting graph. Not consulted for revival — revival semantics land with GC-substrate work.
- **`caspm`** — nil at construction. Populated by `engine:load` with the normalized program that `run()` JSON-encodes into frame 0's `ast` on seed, then nils out so the loaded program has one source of truth (the DB frame's ast), not two.
- **`current_frame`** — nil at construction. `run_frame` sets it to the wrapped frame object before each dispatch, so handlers can reach the frame they're writing into (e.g., `frame:set_local_to_scalar`). Nil again after `run_frame` returns.
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

	-- Forward-declare so the getter closure below can reach the engine
	-- table once it's assembled. cvm.open calls the getter at fire time,
	-- not at open time, so the nil-during-open is harmless.
	local engine

	-- Shallow-copy opts.cvm to add the getter without mutating the
	-- caller's table. The getter returns the CURRENT cap_pk on the
	-- engine — schema-side rules that scope by process (needs_trace's
	-- DEFAULT, frames_gc_reset_requires_empty_needs_trace, etc.) reach
	-- through this closure and pick up whatever run() has set most
	-- recently.
	local cvm_opts = {}
	if opts.cvm then for k, v in pairs(opts.cvm) do cvm_opts[k] = v end end
	cvm_opts.get_current_process_pk = function()
		return engine and engine.cap_pk
	end

	local db = cvm_open.open(cvm_opts)

	engine = setmetatable({
		cvm                 = db,
		data                = Cvm.new(db),
		stdout              = nil,
		debugger            = nil,
		transpiler          = transpiler,
		cap_pk              = nil,
		caspm               = nil,
		current_frame       = nil,
		-- `stopped` is the %process.stop flag. The ProcessStop handler
		-- sets it to true; the walker's per-iteration check breaks the
		-- dispatch loop on true; run() returns a "stopped" result and
		-- skips frame 0's reap so the DB stays exactly as the last
		-- executed statement left it.
		stopped             = false,
		row_handlers        = {},
	}, M)

	-- Every SQL statement the walker issues gets compiled once here and
	-- reused for the engine's lifetime. Prepare-per-call is wasted work
	-- on a hot dispatch loop; the walker's SQL surface is small enough
	-- that a fixed named set covers it.
	engine.stmts = {
		get_ast          = db:prepare('select ast from objects where object_pk = ?'),
		get_stmt_idx     = db:prepare('select stmt_idx from objects where object_pk = ?'),
		get_user_role    = db:prepare("select object_pk from objects where core_role = 'u'"),
		-- Bare advance: `SET stmt_idx = ?` with no gc mention. The
		-- schema's frames_advance_requires_gc trigger requires the
		-- handler to have already set `gc = 1` (via cvm:mark_frame_gc),
		-- and the frames_advance_sets_gc_null AFTER trigger auto-resets
		-- gc back to null. Mentioning gc = 1 in this SET clause is
		-- rejected as an engine bug (frames_advance_rejects_non_null_gc)
		-- and at terminal is doubly rejected (frames_gc_set_rejects_at_terminal).
		advance           = db:prepare('update objects set stmt_idx = ? where object_pk = ?'),
		-- Reap: delete a frame that's finished its ast. Under the current
		-- design terminal frames don't auto-delete — the engine reaps
		-- them explicitly. The AFTER-DELETE cascade
		-- (frames_child_delete_sets_parent_gc) flips the parent's gc from
		-- null to 1 (unless the parent is a cap; that cascade is exempt).
		reap_frame       = db:prepare('delete from objects where object_pk = ?'),
		insert_cap       = db:prepare("insert into objects (primitive, process_cap, ast, stmt_idx, owner_role) values ('f', 1, '[]', 0, ?) returning object_pk"),
		insert_frame_0   = db:prepare("insert into objects (primitive, ast, stmt_idx, parent_frame, owner_role) values ('f', ?, 0, ?, ?) returning object_pk"),
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

Runs the loaded CaspM program (`self.caspm`, populated by `engine:load(source)`) end-to-end. Under the current CVM design a process is a cap frame — an `objects` row with `primitive='f'`, `process_cap=1`, `ast='[]'`. Frame 0 sits under the cap as a nested frame. `run` seeds both, walks frame 0's ast through the handler chain, then advances the cap to sweep frame 0 and reach terminal state.

**Steps:**

1. Seed the cap: INSERT a cap row (`process_cap=1`, `ast='[]'`, `stmt_idx=0`, no parent).
2. Seed frame 0 as a nested frame under the cap (`parent_frame=cap_pk`, `ast=<caspm>`, `stmt_idx=0`).
3. `self:run_frame(frame_0_pk)` — walks the ast; per statement: set `self.current_frame`, dispatch, advance `stmt_idx += 1, gc = 1` (cascades any marker child), reset `gc = null`.
4. Advance the cap: `stmt_idx = 1, gc = 1` — cascade sweeps frame 0. Frame 0's outgoing refs (including any owner→bucket ref) cascade too, firing the standard mark-needs-trace trigger on each ref-delete.
5. Reset cap's `gc = null` — cap is now terminal (`stmt_idx=1, gc=null, no children`). This is the "program is done" state.

**GC not wired here.** After `run` returns, the cap and any orphaned graph (rows referenced by `needs_trace` entries) still sit in the DB. Running the trace-and-sweep pass over that worklist lands with GC-substrate integration.

**Precondition.** `self.caspm` must be populated via `engine:load(source)`; missing raises `engine:run() called before engine:load()`.

**Return value.** A hash `{complete = 1, cap_pk = <cap_pk>}` on normal completion. If `%process.stop` fired during the walk, a hash `{complete = 0, stopped = 1, cap_pk = <cap_pk>}` is returned instead — the frame stayed alive, the reap was skipped, and the DB sits exactly as the last executed statement left it.
]]
function M:run()
	if not self.caspm then
		error("engine:run() called before engine:load(); no program to execute")
	end

	local stmts = self.stmts

	-- Look up the user role (schema-seeded).
	local user_pk

	if stmts.get_user_role:step() == 100 then
		user_pk = stmts.get_user_role:get_value(0)
	end

	stmts.get_user_role:reset()

	-- 1. Seed the cap.
	stmts.insert_cap:bind_values(user_pk)
	stmts.insert_cap:step()
	local cap_pk = stmts.insert_cap:get_value(0)
	stmts.insert_cap:reset()
	self.cap_pk = cap_pk

	-- 2. Seed frame 0 under the cap.
	local ast_json = cjson.encode(self.caspm)
	stmts.insert_frame_0:bind_values(ast_json, cap_pk, user_pk)

	-- If the INSERT raises (e.g., the ast_valid_insert trigger fires on
	-- a non-array ast), step returns an error code and get_value on the
	-- failed statement returns "misuse of function." Check the return
	-- and surface the DB's error text instead.
	local rc = stmts.insert_frame_0:step()

	if rc ~= 100 then  -- 100 == sqlite.ROW; anything else means no row returned
		local err = self.cvm:errmsg()
		stmts.insert_frame_0:reset()
		error(err)
	end

	local frame_0_pk = stmts.insert_frame_0:get_value(0)
	stmts.insert_frame_0:reset()

	self.caspm = nil

	-- Reset stopped in case this engine is being reused across runs.
	self.stopped = false

	-- 3. Walk frame 0's ast. run_frame reaps at the end (whether the
	-- ast was empty from birth or exhausted through the loop), so by
	-- the time this returns, frame 0 is gone. Cap stays alive at
	-- (stmt_idx=0, gc=null) as the process anchor — the
	-- child-delete cascade that fires against the cap is cap-exempt,
	-- so cap.gc never gets touched and cap.stmt_idx never advances.
	--
	-- If the walker halted via %process.stop, frame 0 is still alive
	-- (run_frame skipped the reap) and the return value below signals
	-- that to the caller.
	self:run_frame(frame_0_pk)

	if self.stopped then
		return {complete = 0, stopped = 1, cap_pk = cap_pk}
	end

	return {complete = 1, cap_pk = cap_pk}
end

--[[
## `run_frame`

Runs one frame from the top of its ast to the end, then reaps it. Per statement: set `self.current_frame` so handlers can reach the frame; dispatch the row through the handler chain (via `run_row`); do a bare `SET stmt_idx = ?` advance (the schema's BEFORE `frames_advance_requires_gc` enforces the handler-set gc=1 precondition; the AFTER `frames_advance_sets_gc_null` auto-resets gc).

**Live stmt_idx.** `stmt_idx` is read live from the DB each iteration; nothing resets it at entry. Fresh frames start at 0 (seeded that way); revived frames pick up wherever they were when the last run left off. Every at-rest state is a valid resume state.

**Reap at end.** When the loop exits (ast exhausted, or frame born at terminal with an empty ast), the frame is DELETEd. The AFTER-DELETE cascade `frames_child_delete_sets_parent_gc` flips the parent's gc from null to 1 (cap-exempt, so a cap parent stays untouched). Under the current design terminal is a valid at-rest state; the frame stays there until this reap runs.
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

	-- Defense-in-depth: if the frame doesn't exist for some reason,
	-- bail without trying to walk it. Under the current design run_frame
	-- is only ever called with a freshly-inserted frame pk, so nil
	-- shouldn't happen on the normal path.
	if ast_json == nil then return end

	local ast = cjson.decode(ast_json)

	-- Shape check: ast should be a JSON array. Table + first key is
	-- either nil (empty) or numeric. The ast_valid_insert trigger
	-- enforces this at write time; the Lua check is defense-in-depth.
	if type(ast) ~= 'table' or (next(ast) ~= nil and type(next(ast)) ~= 'number') then
		error('caspm_not_array: expected frame ast to decode as a JSON array')
	end

	-- Live read of the frame's stmt_idx. Called every time the loop
	-- wants the value (the condition, the array index) — the DB is the
	-- single source of truth. Returns `nil` if the frame has been
	-- deleted (auto-swept by frames_auto_delete_at_terminal); callers
	-- treat nil as "loop is done."
	local function get_stmt_idx()
		stmts.get_stmt_idx:bind_values(frame_pk)

		local idx

		for row in stmts.get_stmt_idx:nrows() do
			idx = row.stmt_idx
		end

		stmts.get_stmt_idx:reset()

		return idx
	end

	while true do
		local idx = get_stmt_idx()
		if idx == nil then break end

		-- Loop guard: still-within-ast check.
		if idx >= #ast then break end

		-- Handlers need access to the current frame to write into it —
		-- e.g., set_local_to_scalar on a variable-assignment handler.
		self.current_frame = self.data:object_by_pk(frame_pk)

		-- ast indices are 0-based in the DB (stmt_idx starts at 0);
		-- Lua arrays are 1-based, so `+ 1` at the site.
		self:run_row(ast[idx + 1])

		-- %process.stop lands here. If the handler set the flag,
		-- break BEFORE advancing — that leaves the frame at its
		-- current stmt_idx, gc as whatever the handler left it, and
		-- (up in run()) the reap step gets skipped too. Whole DB
		-- state is preserved for the caller to inspect.
		if self.stopped then break end

		-- Drain the current process's needs_trace worklist between
		-- statements. The handler's writes may have marked orphaned
		-- children (e.g. a `$x = 2` rebind on top of `$x = 1` marks
		-- scalar_1); the drain reaps those before the advance so the
		-- schema's `frames_gc_reset_requires_empty_needs_trace` guard
		-- doesn't trip on the auto-null that fires with the advance.
		self.data:drain_needs_trace(self.cap_pk)

		-- Bare advance. The handler was responsible for setting
		-- `gc = 1` (via cvm:mark_frame_gc) as part of its writes; the
		-- BEFORE trigger frames_advance_requires_gc enforces that
		-- precondition. After stmt_idx changes, the AFTER trigger
		-- frames_advance_sets_gc_null completes the cycle by resetting
		-- gc back to null. The walker just SETs stmt_idx.
		stmts.advance:bind_values(idx + 1, frame_pk)
		stmts.advance:step()
		stmts.advance:reset()
	end

	self.current_frame = nil

	-- If %process.stop halted the walker, skip the reap — leaving the
	-- frame alive is part of the "leaves the database as it is"
	-- promise. Normal completion still reaps.
	if self.stopped then return end

	-- Reap: frame is done with its ast (either exhausted the loop or
	-- was born terminal with an empty ast). Delete it. The
	-- frames_child_delete_sets_parent_gc cascade fires against the
	-- parent (cap-exempt).
	stmts.reap_frame:bind_values(frame_pk)
	stmts.reap_frame:step()
	stmts.reap_frame:reset()

	-- Reap cascades: the frame's outgoing refs (parent = frame_pk)
	-- cascade-delete, and each fires `refs_mark_needs_trace_after_delete`
	-- against the ref's child. Those marks sit in `needs_trace` until
	-- something sweeps them; the drain below is that sweep. Under the
	-- current design the whole orphaned subgraph (bucket → scopes →
	-- scopes[0] → any bindings) unwinds through the drain's iterative
	-- reap-and-cascade cycle, and this process's worklist ends empty.
	self.data:drain_needs_trace(self.cap_pk)
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
