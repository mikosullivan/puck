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

	local db = cvm_open.open(opts.cvm)

	local engine = setmetatable({
		cvm                 = db,
		data                = Cvm.new(db),
		stdout              = nil,
		debugger            = nil,
		transpiler          = transpiler,
		cap_pk              = nil,
		caspm               = nil,
		current_frame       = nil,
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
		advance_with_gc  = db:prepare('update objects set stmt_idx = ?, gc = 1 where object_pk = ?'),
		reset_gc         = db:prepare('update objects set gc = null where object_pk = ?'),
		insert_cap       = db:prepare("insert into objects (primitive, process, ast, stmt_idx, owner_role) values ('f', 1, '[]', 0, ?) returning object_pk"),
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

Runs the loaded CaspM program (`self.caspm`, populated by `engine:load(source)`) end-to-end. Under the current CVM design a process is a cap frame — an `objects` row with `primitive='f'`, `process=1`, `ast='[]'`. Frame 0 sits under the cap as a nested frame. `run` seeds both, walks frame 0's ast through the handler chain, then advances the cap to sweep frame 0 and reach terminal state.

**Steps:**

1. Seed the cap: INSERT a cap row (`process=1`, `ast='[]'`, `stmt_idx=0`, no parent).
2. Seed frame 0 as a nested frame under the cap (`parent_frame=cap_pk`, `ast=<caspm>`, `stmt_idx=0`).
3. `self:run_frame(frame_0_pk)` — walks the ast; per statement: set `self.current_frame`, dispatch, advance `stmt_idx += 1, gc = 1` (cascades any marker child), reset `gc = null`.
4. Advance the cap: `stmt_idx = 1, gc = 1` — cascade sweeps frame 0. Frame 0's outgoing refs (including any owner→bucket ref) cascade too, firing the standard mark-needs-trace trigger on each ref-delete.
5. Reset cap's `gc = null` — cap is now terminal (`stmt_idx=1, gc=null, no children`). This is the "program is done" state.

**GC not wired here.** After `run` returns, the cap and any orphaned graph (`needs_trace = 1` rows) still sit in the DB. Marking the cap `needs_trace = 1` and running the trace-and-sweep pass lands with GC-substrate integration.

**Precondition.** `self.caspm` must be populated via `engine:load(source)`; missing raises `engine:run() called before engine:load()`.

**Return value.** A hash `{complete = 1, cap_pk = <cap_pk>}`. The completion signal is derivable from the cap's terminal shape; the cap_pk lets callers inspect post-run state.
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

	-- 3. Walk frame 0's ast.
	self:run_frame(frame_0_pk)

	-- 4. Advance the cap: sweeps frame 0 via cascade.
	stmts.advance_with_gc:bind_values(1, cap_pk)
	stmts.advance_with_gc:step()
	stmts.advance_with_gc:reset()

	-- 5. Reset cap's gc → null. Cap is now terminal.
	stmts.reset_gc:bind_values(cap_pk)
	stmts.reset_gc:step()
	stmts.reset_gc:reset()

	return {complete = 1, cap_pk = cap_pk}
end

--[[
## `run_frame`

Runs one frame from the top of its ast to the end. Per statement: set `self.current_frame` so handlers can reach the frame; dispatch the row through the handler chain (via `run_row`); advance `stmt_idx += 1, gc = 1` in one UPDATE (the AFTER-UPDATE cascade sweeps any marker child the handler pushed); reset `gc = null` (completes the gc cycle for this statement).

**Live stmt_idx.** `stmt_idx` is read live from the DB each iteration; nothing resets it at entry. Fresh frames start at 0 (seeded that way); revived frames pick up wherever they were when the last run left off. Every at-rest state is a valid resume state.

**Does not shut down the frame.** After the ast is exhausted, the frame is at `stmt_idx > max, gc = null` — terminal, but still present. The frame's parent (a nested-frame parent, or the cap for frame 0) will sweep it via its own advance-with-gc cascade. This method only walks; sweep-me happens externally.
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
		local idx = get_stmt_idx()

		-- Handlers need access to the current frame to write into it —
		-- e.g., set_local_to_scalar on a variable-assignment handler.
		self.current_frame = self.data:object_by_pk(frame_pk)

		-- ast indices are 0-based in the DB (stmt_idx starts at 0);
		-- Lua arrays are 1-based, so `+ 1` at the site.
		self:run_row(ast[idx + 1])

		-- Advance + set gc=1 in one UPDATE. AFTER-UPDATE cascade sweeps
		-- any marker child the handler pushed. All four gc-cycle
		-- invariants enforced by triggers on `objects`.
		stmts.advance_with_gc:bind_values(idx + 1, frame_pk)
		stmts.advance_with_gc:step()
		stmts.advance_with_gc:reset()

		-- Complete the gc cycle: no children remain (marker cascade-swept),
		-- so the gc-reset trigger passes.
		stmts.reset_gc:bind_values(frame_pk)
		stmts.reset_gc:step()
		stmts.reset_gc:reset()
	end

	self.current_frame = nil
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
