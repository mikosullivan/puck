--[[
{
	"module": "engine",
	"role": "Caspian's runtime. `engine.new()` is the boot entry point — its first act is to open an CVM (via cvm.open()) and stash the SQLite handle as engine.cvm, so the runtime state store (CVM in V1) is live from the moment the engine exists. Host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(source) which transpiles + normalizes into a CaspM tree; run() walks that tree and dispatches each row via a table-driven dispatcher. Iteratively extended one construct at a time: any atom kind / bwc / row-head shape the dispatcher doesn't have a handler for raises a specific unrecognized_* error that names the missing piece.",
	"exports": {
		"new": "(opts?) -> Engine — opts.cvm is passed through to cvm.open() for the underlying CVM connection"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface.",
	"dispatch_contract": "Three raise sites, all with `unrecognized_` prefix so grep finds them: `unrecognized_row_head` (statement-position atom the row dispatcher doesn't know), `unrecognized_bwc` (bareword-command name with no handler registered), `unrecognized_atom_kind` (value-producing atom whose kind key isn't in the value dispatcher). Adding a new construct = registering one handler and re-running the failing program."
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

local transpiler = require('transpiler')
local normalize  = require('normalize')
local cvm    = require('cvm')

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
## The bwc handler table

`bwc_handlers` is a table keyed by bareword-command name. Each handler
takes `(engine, row)` where `row[1]` is the bwc marker atom and
`row[2..]` are the arg atoms (unevaluated — the handler calls
`engine:eval` on each). A bwc name with no matching entry raises
`unrecognized_bwc` from `engine:run_bwc`.

This table is walking-skeleton scaffolding. In the target design bwcs
resolve through a DSL chain per [nested-dsls](https://www.puck.uno/ideas/nested-dsls);
this direct-lookup shape is a stand-in until that lands. Anything added
here should survive the eventual refactor cleanly — no per-handler
features that duplicate what the DSL chain will handle.
]]
local bwc_handlers = {}

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
- **`source`, `caspj`, `caspm`** — nil at construction. Populated by
  `engine:load`. Vestigial: these are walking-skeleton fields; when the
  spec'd schema slot for CaspM-in-the-CVM lands, `load` will write into
  the CVM instead and these fields go away.

`opts.cvm` (when supplied) is passed through to `cvm.open()` — see
that function's signature for the fields (`path`, `schema`, `schema_path`).
Omit `opts` entirely for the common case: a fresh in-memory CVM. A
program that doesn't need a given host capability doesn't force its host
to provide one; reaching for an unwired capability raises at the fire
site.
]]
function M.new(opts)
	opts = opts or {}

	return setmetatable({
		cvm      = cvm.open(opts.cvm),
		stdout   = nil,
		debugger = nil,
		source   = nil,
		caspj    = nil,
		caspm    = nil,
	}, M)
end

--[[
## Loading source

`engine:load(source)` takes a Caspian source string, transpiles it into
CaspJ, normalizes that into CaspM, and stashes all three (`source`,
`caspj`, `caspm`) on the engine. Appends a `{kind = 'loaded',
source_length = N}` entry to the debugger if one is attached.

Must be called before `run()`; calling `run()` on an engine that hasn't
loaded anything raises `engine:run() called before engine:load()`. The
three intermediate representations remain readable on the engine after
load — useful for inspecting what the transpiler and normalizer
produced.
]]
function M:load(source)
	self.source = source
	self.caspj  = transpiler.transpile(source)
	self.caspm  = normalize.normalize(self.caspj)

	debug_log(self, {kind = 'loaded', source_length = #source})

	return
end

--[[
## Running the program

`engine:run()` walks the loaded CaspM tree and dispatches each statement
row via `run_row`. Raises `engine:run() called before engine:load()`
when the engine hasn't loaded anything — prevents a silent no-op that
would look like a working program.

Currently top-level only: there's no call stack yet, so `run` is the
only entry point and each row runs in the same implicit root frame.
When CVM and the call stack land, this grows into the root frame's
execution loop.
]]
function M:run()
	if not self.caspm then
		error("engine:run() called before engine:load(); no program to execute")
	end

	for _, row in ipairs(self.caspm) do
		self:run_row(row)
	end

	return
end

--[[
## Dispatching a row

`engine:run_row(row)` dispatches one CaspM statement row based on its
head atom. Currently handles one shape — `{bwc: name}` rows route to
`run_bwc`; anything else appends a `raised` entry to the debugger and
raises `unrecognized_row_head` with the head's key set in the message
so the walking-skeleton iteration knows what row shape to add support
for next.

New row-head shapes land as additional `elseif head.<key> then ...`
branches here, each with a corresponding sub-dispatcher (mirroring
the bwc case's `run_bwc`).
]]
function M:run_row(row)
	local head = row[1]

	if head.bwc then
		return self:run_bwc(head.bwc, row)
	end

	debug_log(self, {kind = 'raised', reason = 'unrecognized_row_head', head = head})
	error("unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(head) .. "}")
end

--[[
## Dispatching a bwc

`engine:run_bwc(name, row)` looks up `name` in `bwc_handlers` and
invokes the found handler. On success, appends `{kind = 'bwc', name =
name}` to the debugger and returns whatever the handler returned. On
failure — no registered handler for the name — appends `{kind =
'raised', reason = 'unrecognized_bwc', name = name}` and raises
`unrecognized_bwc: no handler registered for bareword command
'<name>'`.

The debugger entry lands before the raise so the diagnostic trail
survives the error path.
]]
function M:run_bwc(name, row)
	local handler = bwc_handlers[name]

	if not handler then
		debug_log(self, {kind = 'raised', reason = 'unrecognized_bwc', name = name})
		error("unrecognized_bwc: no handler registered for bareword command '" .. name .. "'")
	end

	debug_log(self, {kind = 'bwc', name = name})
	return handler(self, row)
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
