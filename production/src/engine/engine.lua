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
[cvm](https://www.puck.uno/requirements/cvm/sqlite/)) via `cvm.open()`
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
local sqlite             = require('lsqlite3')
local transpiler         = require('transpiler')
local normalize          = require('normalize')
local cvm_open           = require('cvm.sqlite.open')
local Cvm                = require('cvm.sqlite')
local handlers           = require('handlers')
local halt               = require('halt')
local Frame              = require('frame')

-- Cached at module load; avoids per-call global lookups.
local SQLITE_ROW = sqlite.ROW

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
- **`caspm`** — nil at construction. Populated by `engine:load` with the normalized program that `run()` JSON-encodes into frame 0's `frame_ast` on seed, then nils out so the loaded program has one source of truth (the DB frame's frame_ast), not two.
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
		row_handlers        = {},
	}, M)

	-- Back-reference: `cvm:object_by_pk` calls `object.new(self.engine, row)`
	-- so wrapped objects carry a reference to the top-level Engine rather
	-- than just the CVM. Object.lua's methods reach the CVM via
	-- `self.engine.data`. Frame (an object subclass) uses the same field
	-- for its top-level-only concerns (row_handlers, cap_pk, stmts).
	engine.data.engine = engine

	-- Every SQL statement the walker issues gets compiled once here and
	-- reused for the engine's lifetime. Prepare-per-call is wasted work
	-- on a hot dispatch loop; the walker's SQL surface is small enough
	-- that a fixed named set covers it.
	engine.stmts = {
		get_ast          = db:prepare('select frame_ast from objects where object_pk = ?'),
		get_stmt_idx     = db:prepare('select frame_stmt_idx from objects where object_pk = ?'),
		get_user_role    = db:prepare("select object_pk from objects where role_core = 'u'"),
		-- Bare advance: `SET frame_stmt_idx = ?` with no frame_gc mention. The
		-- schema's frames_advance_requires_gc trigger requires the
		-- handler to have already set `frame_gc = 1` (via cvm:mark_frame_gc),
		-- and the frames_advance_sets_gc_null AFTER trigger auto-resets
		-- frame_gc back to null. Mentioning frame_gc = 1 in this SET clause is
		-- rejected as an engine bug (frames_advance_rejects_non_null_gc)
		-- and at terminal is doubly rejected (frames_gc_set_rejects_at_terminal).
		-- Bare advance-by-one: `SET frame_stmt_idx = frame_stmt_idx + 1`.
		-- The schema enforces advance-by-1 (frames_stmt_idx_advances_by_one)
		-- so no target value is bindable; the SQL expresses "increment"
		-- directly. Same trigger-stack applies: frames_advance_requires_gc
		-- (BEFORE), frames_advance_sets_gc_null (AFTER).
		advance           = db:prepare('update objects set frame_stmt_idx = frame_stmt_idx + 1 where object_pk = ?'),
		-- Reap: delete a frame that's finished its frame_ast. Under the
		-- current design terminal frames don't auto-delete — the
		-- engine reaps them explicitly. The AFTER-DELETE cascade
		-- (frames_child_delete_sets_parent_gc) flips the parent's
		-- frame_gc from null to 1. The `frame_process_cap is null`
		-- clause makes the reap a silent no-op on caps: cap's own
		-- run_frame hits terminal and runs this delete, but the cap
		-- survives as the process anchor.
		reap_frame       = db:prepare('delete from objects where object_pk = ? and frame_process_cap is null'),
		insert_cap       = db:prepare("insert into objects (base, control, frame_process_cap, frame_ast, frame_stmt_idx, owner_role) values ('o', 'f', 1, '[null]', 0, ?) returning object_pk"),
		insert_frame_0   = db:prepare("insert into objects (base, control, frame_ast, frame_stmt_idx, frame_parent, owner_role) values ('o', 'f', ?, 0, ?, ?) returning object_pk"),
		-- Halt-and-restart mechanics for %process.stop.
		insert_stop_frame = db:prepare("insert into objects (base, control, engine_class, frame_ast, frame_stmt_idx, frame_parent, owner_role) select 'o', 'f', 'stop', '[]', 0, ?1, owner_role from objects where object_pk = ?1"),
		-- Restart-frame descent recursion helpers.
		find_child_of     = db:prepare('select object_pk from objects where frame_parent = ?'),
		get_frame_gc      = db:prepare('select frame_gc from objects where object_pk = ?'),
		get_engine_class  = db:prepare('select engine_class from objects where object_pk = ?'),
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

-- The walker (single `run(restart)` method), the row dispatcher
-- (run_row), the %process.stop primitive, and the helpers that used
-- to live here (find_child_of, get_frame_gc, get_engine_class,
-- advance) all moved to Frame — see production/src/engine/frame.lua.
-- Engine's job is now just: bootstrap cap + frame 0, construct a
-- Frame for the cap, kick off `run(true)`. Nothing on the engine
-- holds "which frame are we in" state — each Frame is an object
-- subclass wrapping its `objects` row, gets passed to handlers
-- directly.

--[[
## `run`

The one entry point for driving a process — both first-time execution and continuation-after-halt. First call after `:load()` bootstraps cap + frame 0; subsequent calls continue whatever the DB currently has (halted at a stop frame, halted at a crash-restart chain, whatever the last valid transaction left). The recursion inside `Frame:run(true)` handles the actual walking work; `run` is the setup + xpcall wrapper.

**Optional `restart_value`.** If given, the value is materialized as a scalar and injected as the leaf frame's `rv` before the recursion kicks off. Only valid when the leaf is a stop frame (`engine_class = 'stop'`) — the check raises `engine_run_inject_requires_stop_frame` otherwise. Passing `restart_value` on a fresh process (no stop frame at the leaf) hits the same guard.

**Result hash:**

- `{complete = 1, cap_pk = <cap_pk>}` on normal completion.
- `{stopped  = 1, cap_pk = <cap_pk>}` if `%process.stop` fired during the walk. The stop frame survives; a subsequent `run` (optionally with `restart_value`) resumes.

**Precondition.** On the first invocation, `self.caspm` must be populated via `engine:load(source)`; a first call with no caspm and no existing cap raises `engine_run_before_load`.
]]
function M:run(restart_value)
	local db    = self.cvm
	local stmts = self.stmts

	-- Bootstrap on first call. self.caspm is set by :load() and
	-- cleared after seeding — its presence identifies "first call
	-- after load, seed the process."
	if self.caspm then
		-- Look up the user role (schema-seeded).
		local user_pk

		if stmts.get_user_role:step() == SQLITE_ROW then
			user_pk = stmts.get_user_role:get_value(0)
		end

		stmts.get_user_role:reset()

		-- Seed the cap.
		stmts.insert_cap:bind_values(user_pk)
		stmts.insert_cap:step()
		self.cap_pk = stmts.insert_cap:get_value(0)
		stmts.insert_cap:reset()

		-- Seed frame 0 under the cap.
		local ast_json = cjson.encode(self.caspm)
		stmts.insert_frame_0:bind_values(ast_json, self.cap_pk, user_pk)

		local rc = stmts.insert_frame_0:step()

		if rc ~= SQLITE_ROW then
			local err = self.cvm:errmsg()
			stmts.insert_frame_0:reset()
			error("engine_insert_frame_0_failed: " .. err)
		end

		stmts.insert_frame_0:reset()

		self.caspm = nil
	elseif not self.cap_pk then
		error("engine_run_before_load: engine:run() called before engine:load() and no existing process to continue")
	end

	-- Optional value injection onto the leaf frame.
	if restart_value ~= nil then
		-- Walk cap → leaf via Frame objects. Cheap: each Frame is a
		-- table with 3 fields; the chain is O(halt-depth), typically 2-3.
		local leaf_frame = Frame.new(self, self.cap_pk)

		while true do
			local child_pk = leaf_frame:find_child_pk()
			if not child_pk then break end
			leaf_frame = Frame.new(self, child_pk)
		end

		-- Injecting a return value only makes sense when the process
		-- was intentionally halted via %process.stop — that's what
		-- created a stop frame at the leaf. A crash-restart, or any
		-- other paused-but-not-stopped state, has no stop frame; there
		-- is no meaningful "reply" the value could stand in for.
		local leaf_engine_class = leaf_frame:get_engine_class()

		if leaf_engine_class ~= 'stop' then
			error(
				"engine_run_inject_requires_stop_frame: cannot inject a " ..
				"restart_value; the leaf frame's engine_class is " ..
				tostring(leaf_engine_class) ..
				" (expected 'stop'). Value injection is only valid on a " ..
				"process that was intentionally halted via %process.stop.")
		end

		assert(db:exec('savepoint engine_run_inject_rv;') == 0, db:errmsg())

		local ok, err = pcall(function()
			local scalar_pk = self.data:add_scalar(restart_value, leaf_frame.owner_role)
			local bucket_pk = self.data:add_bucket(leaf_frame.object_pk)
			self.data:upsert_ref(bucket_pk, 'rv', scalar_pk)
		end)

		if not ok then
			db:exec('rollback to savepoint engine_run_inject_rv;')
			db:exec('release savepoint engine_run_inject_rv;')
			error(err, 0)
		end

		assert(db:exec('release savepoint engine_run_inject_rv;') == 0, db:errmsg())
	end

	-- Kick the process off. Construct a Frame for the cap and call
	-- run(true) — truthy restart triggers the descent + gc + advance
	-- prelude, then walks. The recursion inside Frame handles the
	-- full descent through any halt chain and the cap's own cycle.
	-- Frame objects are constructed per-frame during recursion; no
	-- ambient state on the engine tracks "which frame are we in."
	local cap_frame = Frame.new(self, self.cap_pk)

	local ok, result_or_err = xpcall(
		function() return cap_frame:run(true) end,
		function(err) return err end
	)

	if ok then
		return {complete = 1, cap_pk = self.cap_pk}
	end

	if halt.is_halt(result_or_err) then
		return {stopped = 1, cap_pk = self.cap_pk}
	end

	error(result_or_err, 0)
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
