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
local dispatch           = require('dispatch')
local handlers           = require('handlers')
local halt               = require('halt')

-- Cached at module load; avoids per-call global lookups.
local SQLITE_ROW  = sqlite.ROW
local SQLITE_DONE = sqlite.DONE

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
- **`current_frame_pk`** — nil at construction. `run_frame` sets it to the frame's pk before dispatch so handlers can reach the frame they're writing into. Nil again after `run_frame` returns. (Replaces the older `current_frame` slot, which held a wrapper instance — handlers now work in pks against the CVM.)
- **`current_role_pk`** — nil at construction. `run_frame` sets it to the frame's `owner_role` pk in the same pass — the frame's owner is what a scalar or bucket a handler creates inherits from. Nil again after `run_frame` returns.
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
		current_frame_pk    = nil,
		current_role_pk     = nil,
		row_handlers        = {},
	}, M)

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
		advance           = db:prepare('update objects set frame_stmt_idx = ? where object_pk = ?'),
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

--[[
## `find_child_of` — helper: single-child lookup

Returns the object_pk of the frame's single child (or nil if none). Under the linear-stack rule, at most one child exists.
]]
local function find_child_of(self, frame_pk)
	local stmt = self.stmts.find_child_of
	stmt:bind_values(frame_pk)

	local child_pk

	if stmt:step() == SQLITE_ROW then
		child_pk = stmt:get_value(0)
	end

	stmt:reset()

	return child_pk
end

--[[
## `get_frame_gc` — helper: read frame_gc

Returns `1` if the frame is in gc state, `nil` otherwise.
]]
local function get_frame_gc(self, frame_pk)
	local stmt = self.stmts.get_frame_gc
	stmt:bind_values(frame_pk)

	local gc

	if stmt:step() == SQLITE_ROW then
		gc = stmt:get_value(0)
	end

	stmt:reset()

	return gc
end

--[[
## `get_engine_class` — helper: read engine_class

Returns the object's `engine_class` string (e.g. `'stop'`), or `nil` if unset. Used as a precondition check when `run` is asked to inject a value: injection only makes sense at a stop frame.
]]
local function get_engine_class(self, object_pk)
	local stmt = self.stmts.get_engine_class
	stmt:bind_values(object_pk)

	local engine_class

	if stmt:step() == SQLITE_ROW then
		engine_class = stmt:get_value(0)
	end

	stmt:reset()

	return engine_class
end

--[[
## `advance_past_current` — helper: read stmt_idx, advance to stmt_idx+1

Reads the frame's current stmt_idx and advances it by one via the standard `advance` prepared statement. Assumes the schema's advance preconditions (frame_gc = 1, needs_trace empty) are already met by the caller — the advance's AFTER trigger auto-nulls frame_gc.
]]
local function advance_past_current(self, frame_pk)
	local get_idx = self.stmts.get_stmt_idx
	get_idx:bind_values(frame_pk)

	local current_idx

	if get_idx:step() == SQLITE_ROW then
		current_idx = get_idx:get_value(0)
	end

	get_idx:reset()

	local advance = self.stmts.advance
	advance:bind_values(current_idx + 1, frame_pk)
	advance:step()
	advance:reset()
end

--[[
## `run`

The one entry point for driving a process — both first-time execution and continuation-after-halt. First call after `:load()` bootstraps cap + frame 0; subsequent calls continue whatever the DB currently has (halted at a stop frame, halted at a crash-restart chain, whatever the last valid transaction left). The recursion inside `restart_frame` handles the actual walking work; `run` is the setup + xpcall wrapper.

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
		local leaf_pk = self.cap_pk

		while true do
			local next_pk = find_child_of(self, leaf_pk)
			if not next_pk then break end
			leaf_pk = next_pk
		end

		-- Injecting a return value only makes sense when the process
		-- was intentionally halted via %process.stop — that's what
		-- created a stop frame at the leaf. A crash-restart, or any
		-- other paused-but-not-stopped state, has no stop frame; there
		-- is no meaningful "reply" the value could stand in for.
		local leaf_engine_class = get_engine_class(self, leaf_pk)

		if leaf_engine_class ~= 'stop' then
			error(
				"engine_run_inject_requires_stop_frame: cannot inject a " ..
				"restart_value; the leaf frame's engine_class is " ..
				tostring(leaf_engine_class) ..
				" (expected 'stop'). Value injection is only valid on a " ..
				"process that was intentionally halted via %process.stop.")
		end

		local leaf_role = self.data:role_by_pk(leaf_pk)

		assert(db:exec('savepoint engine_run_inject_rv;') == 0, db:errmsg())

		local ok, err = pcall(function()
			local scalar_pk = self.data:add_scalar(restart_value, leaf_role)
			local bucket_pk = self.data:add_bucket(leaf_pk)
			self.data:upsert_ref(bucket_pk, 'rv', scalar_pk)
		end)

		if not ok then
			db:exec('rollback to savepoint engine_run_inject_rv;')
			db:exec('release savepoint engine_run_inject_rv;')
			error(err, 0)
		end

		assert(db:exec('release savepoint engine_run_inject_rv;') == 0, db:errmsg())
	end

	-- Kick the process off. restart_frame handles the full descent
	-- (recurses into any child chain), the unwind (each level's reap
	-- sets the parent's gc; parent's gc-check drains + advances), and
	-- the cap's own cycle (frame 0's reap sets cap.gc=1, cap runs gc
	-- + advances to terminal, cap's reap step no-ops via the cap-skip
	-- clause on reap_frame).
	local ok, result_or_err = xpcall(
		function() return self:restart_frame(self.cap_pk) end,
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
## `run_frame`

Runs one frame from the top of its frame_ast to the end, then reaps it. Per statement: dispatch the row through `run_row`; run gc (`garbage_collect`); advance stmt_idx via a bare `SET frame_stmt_idx = ?` (the schema's BEFORE `frames_advance_requires_gc` enforces the handler-set frame_gc=1 precondition; the AFTER `frames_advance_sets_gc_null` auto-resets frame_gc).

**Signature:** `(frame_pk, role_pk?)`. Optional `role_pk` lets a caller that already knows the frame's `owner_role` (e.g. a spawning handler that inherits the parent's role for the child) skip the `role_by_pk` lookup. When omitted, the fetch happens inline.

**Frame-scope publish.** `self.current_frame_pk` and `self.current_role_pk` are set once at the top of the method (both are immutable per-frame at the schema level) and cleared at the tail. Handlers read them to write into the frame.

**Missing ast raises.** If `frame_ast` is nil (row doesn't exist, or exists but isn't a frame), raises `run_frame_no_ast`. Fail-loudly rather than silently returning.

**Reap at end.** When the loop exits (frame_ast exhausted, or frame born at terminal with an empty frame_ast), the frame is DELETEd via `reap_frame`. Its cap-skip clause (`and frame_process_cap is null`) makes the delete a silent no-op on caps — cap survives its own run_frame to remain the process anchor. Non-cap frames reap normally; the reap fires `frames_child_delete_sets_parent_gc` on the parent (cap or otherwise), and `frames_child_delete_propagates_rv` lifts rv into the parent's bucket.

**No tail drain.** Cascade marks from the reap sit in `needs_trace` until the parent's next run-gc step (in `restart_frame`) sweeps them. Handlers that reap through `restart_frame` handle it uniformly; the walker doesn't double-dip.
]]
function M:run_frame(frame_pk, role_pk)
	local stmts = self.stmts

	-- Pull the frame_ast out of the frame and parse it.
	stmts.get_ast:bind_values(frame_pk)

	local ast_json

	for row in stmts.get_ast:nrows() do
		ast_json = row.frame_ast
	end

	stmts.get_ast:reset()

	if ast_json == nil then
		error("run_frame_no_ast: run_frame called with pk " .. frame_pk
			.. " but no frame_ast found (row missing or not a frame)")
	end

	local frame_ast = cjson.decode(ast_json)

	-- Shape check: frame_ast should be a JSON array. Table + first key is
	-- either nil (empty) or numeric. The ast_valid_insert trigger
	-- enforces this at write time; the Lua check is defense-in-depth.
	if type(frame_ast) ~= 'table' or (next(frame_ast) ~= nil and type(next(frame_ast)) ~= 'number') then
		error('caspm_not_array: expected frame frame_ast to decode as a JSON array')
	end

	local function get_stmt_idx()
		stmts.get_stmt_idx:bind_values(frame_pk)

		local idx

		for row in stmts.get_stmt_idx:nrows() do
			idx = row.frame_stmt_idx
		end

		stmts.get_stmt_idx:reset()

		return idx
	end

	local idx = get_stmt_idx()

	-- Publish the current frame's pk + owner_role_pk for handlers.
	-- Both are immutable at the schema level; hoisting outside the
	-- loop is safe. Handlers reach into these fields instead of
	-- pulling a full-row wrapper.
	self.current_frame_pk = frame_pk
	self.current_role_pk  = role_pk or self.data:role_by_pk(frame_pk)

	while idx < #frame_ast do
		idx = idx + 1

		-- frame_ast indices are 0-based in the DB; Lua arrays are
		-- 1-based, so we advance idx first (0→1) and use it directly.
		self:run_row(frame_ast[idx])

		self.data:garbage_collect(self.cap_pk)

		stmts.advance:bind_values(idx, frame_pk)
		stmts.advance:step()
		stmts.advance:reset()
	end

	self.current_frame_pk = nil
	self.current_role_pk  = nil

	-- Reap. The reap_frame prepared statement's cap-skip clause
	-- (`and frame_process_cap is null`) makes this a silent no-op on
	-- caps: cap's own run_frame hits terminal and runs this delete,
	-- but the cap survives as the process anchor. Non-cap frames
	-- reap normally; their parent's frame_gc flips to 1 via
	-- `frames_child_delete_sets_parent_gc`, and the parent's next
	-- run-gc step (in restart_frame) sweeps the cascade marks.
	stmts.reap_frame:bind_values(frame_pk)
	stmts.reap_frame:step()
	stmts.reap_frame:reset()
end

--[[
## `restart_frame`

Parallel to `run_frame`. Handles the two independent resume-time concerns before delegating the walker + reap to `self:run_frame`:

**Pre-step 1: descend into any child.** If this frame has a child (it's somewhere in a halt chain), recursively `restart_frame` the child. The recursion unwinds bottom-up: at the leaf, `run_frame` walks the ast (empty for a stop frame) and reaps. Each reap fires `frames_child_delete_propagates_rv` (parent gets the child's rv) and `frames_child_delete_sets_parent_gc` (parent's frame_gc → 1). When the recursion returns to this frame, it's now in gc state (unless it never had a child in the first place).

**Pre-step 2: run gc + advance if in gc state.** If `frame_gc = 1` — either from a child's reap during pre-step 1, or from a `%process.stop`-halted state where the handler pre-set gc — the frame is mid-cycle between run-statement and run-gc. Run gc (`garbage_collect` sweeps the cascade marks) + advance stmt_idx past the halted statement. The advance's AFTER trigger `frames_advance_sets_gc_null` resets `frame_gc` back to null.

**Delegate.** `self:run_frame(frame_pk)` walks any remaining statements and reaps at frame end. The reap unwinds one level up the recursion.

**General resume mechanism.** Works on any process paused in a valid DB state — intentional `%process.stop` halt (stop frame at leaf), unclean shutdown (crash, pulled plug, `kill -9`), whatever. The algorithm operates on graph structure (`frame_parent`, `frame_gc`), never on `engine_class = 'stop'` — a crash leaves no stop marker to find; the recursion + gc-check + delegate cycle unwinds any paused state.
]]
function M:restart_frame(frame_pk)
	local child_pk = find_child_of(self, frame_pk)

	if child_pk then
		self:restart_frame(child_pk)
	end

	if get_frame_gc(self, frame_pk) == 1 then
		self.data:garbage_collect(self.cap_pk)
		advance_past_current(self, frame_pk)
	end

	self:run_frame(frame_pk)
end

--[[
## `run_row`

`engine:run_row(row)` offers the row to each Handler in `self.row_handlers` via the shared [dispatch](../engine/dispatch.lua) function. First handler to return `true` wins; if none does, dispatch raises `unrecognized_caspm`. Handler raises propagate through — dispatch doesn't catch.

This method wraps dispatch's raise with a more diagnostic message: if dispatch raises `unrecognized_caspm`, `run_row` catches and re-raises with the row-head atom's key set appended, so the walking-skeleton iteration knows what row shape to add support for next. A handler's own raise (anything other than `unrecognized_caspm`) propagates as-is.

New row-head shapes land as new Handler subclasses registered into `self.row_handlers` — no if/elseif branches to grow here.
]]
function M:run_row(row)
	-- %process.stop is a system primitive, not a user-extensible row
	-- shape. Recognized here before the handler chain and dispatched
	-- to the engine's internal :process_stop() method.
	local expr = row[1]

	if type(expr) == 'table' then
		local head = expr[1]
		local call = expr[2]

		if type(head) == 'table' and head['in'] == 'fc'
			and type(call) == 'table' and call.fn == 'stop'
			and type(call.rc) == 'table' and call.rc.sys == 'process'
		then
			self:process_stop()
			return
		end
	end

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
## `process_stop` — internal handler for `%process.stop`

Called by `run_row` when it recognizes the `%process.stop` row shape. Not part of the pluggable handler chain — the stop primitive is a system-level operation.

**Behavior:** insert a stop frame under `self.current_frame_pk` (via the `insert_stop_frame` prepared statement), then raise the HALT sentinel via `halt.raise()`. The stop frame's shape: `base='o'`, `control='f'`, `engine_class='stop'`, `frame_ast='[]'` (terminal at birth), `frame_stmt_idx=0`, `frame_parent = current_frame_pk`, `owner_role` inherited from the current frame via the SELECT.

HALT unwinds through `run_row` + `run_frame` + `restart_frame` back to `run`'s xpcall, which catches it and returns `{stopped=1, cap_pk}`. A subsequent `run(restart_value?)` resumes: `restart_frame`'s descent recursion reaps the stop frame (lifting any injected rv up the chain via `frames_child_delete_propagates_rv`), and the parent's next iteration continues past the halted statement.
]]
function M:process_stop()
	local stmt = self.stmts.insert_stop_frame
	stmt:bind_values(self.current_frame_pk)

	local rc = stmt:step()
	stmt:reset()

	if rc ~= SQLITE_DONE then
		error("process_stop_insert_failed: " .. tostring(self.cvm:errmsg()))
	end

	halt.raise()
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
