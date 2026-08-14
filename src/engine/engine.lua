--[[
{
	"module": "engine",
	"role": "Caspian's runtime. `engine.new()` is the boot entry point — its first act is to open an CVM (via cvm.open()) and stash the SQLite handle as engine.cvm, so the runtime state store (CVM in V1) is live from the moment the engine exists. Host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(source) which transpiles + normalizes into a CaspM tree; run() walks that tree and dispatches each row via the row-handler chain-of-responsibility. Iteratively extended by registering Handler subclasses via the row-handler-chain API (add_handler / prepend_handler / remove_handler / clear_handlers / handlers) — no if/elseif branching in run_row.",
	"exports": {
		"new": "(opts?) -> Engine — opts.cvm is passed through to cvm.open() for the underlying CVM connection",
		"add_handler": "(handler) -> self — appends a handler to the end of self.row_handlers",
		"prepend_handler": "(handler) -> self — inserts a handler at index 1 of self.row_handlers (front of the chain, wins over stock handlers)",
		"remove_handler": "(handler) -> self — removes the first occurrence of `handler` by identity; raises `handler_not_found` if not in the chain",
		"clear_handlers": "() -> self — empties self.row_handlers (including stock handlers); subsequent rows raise unrecognized_row_head until at least one handler is added back",
		"handlers": "() -> array — returns a shallow copy of self.row_handlers, in chain order (index 1 is checked first at dispatch time)"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Tests wire a FakeOutput; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface.",
	"dispatch_contract": "Two raise sites, both with `unrecognized_` prefix so grep finds them: `unrecognized_row_head` (statement row that no registered Handler in row_handlers claimed — surfaced by run_row with the row-head atom's key set appended for diagnostic detail), `unrecognized_atom_kind` (value-producing atom whose kind key isn't in the value dispatcher). Adding a new construct = registering a Handler subclass via engine:add_handler and re-running the failing program."
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
## Rendering an atom's key set

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
## Debug logging

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
## Constructor

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
  host additions) means every row raises `unrecognized_row_head` from
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
		cvm          = cvm.open(opts.cvm),
		stdout       = nil,
		debugger     = nil,
		transpiler   = transpiler,
		process_pk   = nil,
		caspm        = nil,
		row_handlers = {},
	}, M)

	-- Wire the stock handler roster through the public API so even the
	-- engine's own constructor self-hosts on add_handler.
	for _, handler in ipairs(handlers.stock_instances()) do
		engine:add_handler(handler)
	end

	return engine
end

--[[
## Loading source

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
## Running the program

`engine:run()` sets up frame 0 (fresh or revival, per the `process_pk`
slot) and then dispatches statement rows from the frame's `ast` via
`run_row`.

**Fresh vs revival.** If `self.process_pk` is nil, `run` treats the run
as fresh: `create_frame_0` invents a new process, encodes `self.caspm`
into frame 0's `ast`, and pushes the frame. `self.caspm` is nil'd
immediately after — once the CaspM lives in the DB frame, the Lua-side
staging slot is spent, and keeping it around would give the loaded
program two sources of truth. If `self.process_pk` is set, `run` treats
the run as revival: `get_latest_frame` finds the deepest live frame in
that process; `self.caspm` is not consulted (the program lives in the
DB frame, not on the engine).

**Precondition.** Fresh runs require `self.caspm` to be set (via
`engine:load(source)` before `run()`); missing raises `engine:run()
called before engine:load()`. Revival runs have no such requirement.

**Empty-process revival.** If `get_latest_frame` returns nil (the
process exists but has no frames — done), dispatch is skipped entirely.
Naturally a no-op; not a special case.

**Return value:** a fresh Lua table, created at the top of `run` and
returned at the end. Empty today — reserves the return-value surface so
callers can start writing against it before specific keys are decided;
keys get added as follow-on work lands. Exceptions still bubble up —
this table is only the clean-return path.
]]
function M:run()
	local result = {}

	-- Fresh vs revival. Set up frame 0's resume pk.
	local frame_pk

	if self.process_pk then
		-- Revival: read the deepest live frame from the process.
		-- self.caspm is not required — the program lives in the DB
		-- frame's ast, not on the engine.
		frame_pk = get_latest_frame(self.cvm, self.process_pk)
	else
		-- Fresh: create_frame_0 needs self.caspm to stash into the
		-- new frame's ast. Once that's done, self.caspm is spent —
		-- nil it out so the loaded program has one source of truth
		-- (the DB frame) rather than two (Lua slot + DB row).
		if not self.caspm then
			error("engine:run() called before engine:load(); no program to execute")
		end

		frame_pk = create_frame_0(self.cvm, self)
		self.caspm = nil
	end

	-- If frame_pk is nil, the process is done — dispatch has nothing to
	-- walk. Naturally a no-op.
	if frame_pk then
		-- Fetch the frame's ast from the DB and dispatch from it.
		local ast_stmt = self.cvm:prepare(
			"select ast from objects where object_pk = ?"
		)
		ast_stmt:bind_values(frame_pk)

		local ast_json

		for row in ast_stmt:nrows() do
			ast_json = row.ast
		end

		ast_stmt:reset()

		for _, row in ipairs(cjson.decode(ast_json)) do
			self:run_row(row)
		end
	end

	-- Last chance to read from the database before the connection scope ends.

	return result
end

--[[
## Dispatching a row

`engine:run_row(row)` offers the row to each Handler in `self.row_handlers` via the shared [dispatch](../engine/dispatch.lua) function. First handler to return `true` wins; if none does, dispatch raises `unrecognized_row_head`. Handler raises propagate through — dispatch doesn't catch.

This method wraps dispatch's raise with a more diagnostic message: if dispatch raises `unrecognized_row_head`, `run_row` catches and re-raises with the row-head atom's key set appended, so the walking-skeleton iteration knows what row shape to add support for next. A handler's own raise (anything other than `unrecognized_row_head`) propagates as-is.

New row-head shapes land as new Handler subclasses registered into `self.row_handlers` — no if/elseif branches to grow here.
]]
function M:run_row(row)
	local ok, err = pcall(dispatch, self.row_handlers, self, row)

	if ok then
		return
	end

	-- Reshape the fallback raise with atom-keys diagnostic; propagate
	-- everything else as-is (handler raises, other errors).
	if type(err) == 'string' and err:find('unrecognized_row_head', 1, true) then
		debug_log(self, {kind = 'raised', reason = 'unrecognized_row_head', head = row[1]})
		error("unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(row[1]) .. "}")
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

Removes every handler from `self.row_handlers`, including the stock handlers wired at construction. After a `clear_handlers` every row raises `unrecognized_row_head` at dispatch time until at least one handler is added back. Returns `self` for chaining.
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
## Evaluating an atom

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
