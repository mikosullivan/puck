--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Constructed with no required params — host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(source) which transpiles + normalizes into a CaspM tree; run() walks that tree and dispatches each row via a table-driven dispatcher. Iteratively extended one construct at a time: any atom kind / bwc / row-head shape the dispatcher doesn't have a handler for raises a specific unrecognized_* error that names the missing piece.",
	"exports": {
		"new": "() -> Engine"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface.",
	"dispatch_contract": "Three raise sites, all with `unrecognized_` prefix so grep finds them: `unrecognized_row_head` (statement-position atom the row dispatcher doesn't know), `unrecognized_bwc` (bareword-command name with no handler registered), `unrecognized_atom_kind` (value-producing atom whose kind key isn't in the value dispatcher). Adding a new construct = registering one handler and re-running the failing program."
}
]=]

local transpiler = require('transpiler')
local normalize  = require('normalize')

local M = {}
M.__index = M

-- Renders an atom's key set for error messages. Deterministic
-- ordering so tests can pattern-match without sorting.
local function atom_keys(atom)
	local keys = {}

	for k, _ in pairs(atom) do
		table.insert(keys, k)
	end

	table.sort(keys)
	return table.concat(keys, ', ')
end

-- ------------------------------------------------------------
-- Handlers for bareword commands. `bwc_handlers[name]` receives
-- (engine, row) where row[1] is the bwc marker and row[2..] are
-- the arg atoms (unevaluated — the handler calls engine:eval on
-- each). Missing name -> unrecognized_bwc raise.
-- ------------------------------------------------------------
local bwc_handlers = {}

function bwc_handlers.puts(engine, row)
	if not engine.stdout then
		error("puts: no stdout wired — set engine.stdout before running programs that write output")
	end

	-- Multi-arg puts: each arg gets its own trailing newline.
	-- `puts 'a', 'b'` writes `a\nb\n`.
	for i = 2, #row do
		local value = engine:eval(row[i])
		engine.stdout:print(tostring(value) .. '\n')
	end

	return
end

-- ------------------------------------------------------------
-- Debugger helper. No-op when no debugger is attached, so the
-- rest of the engine stays free of `if self.debugger` fences.
-- ------------------------------------------------------------
local function log(engine, entry)
	if engine.debugger then
		table.insert(engine.debugger, entry)
	end
end

--[[ {"in": {}, "out": "Engine instance — no wiring attached, no program loaded"} ]]
function M.new()
	return setmetatable({
		stdout   = nil,
		debugger = nil,
		source   = nil,
		caspj    = nil,
		caspm    = nil,
	}, M)
end

--[[ {"in": {"source": "Caspian source string"}, "out": "nil — transpiles source into CaspJ, normalizes into CaspM, stashes source / caspj / caspm on self, and logs a 'loaded' entry to the debugger if one is attached"} ]]
function M:load(source)
	self.source = source
	self.caspj  = transpiler.transpile(source)
	self.caspm  = normalize.normalize(self.caspj)

	log(self, {kind = 'loaded', source_length = #source})

	return
end

--[[ {"in": {}, "out": "nil — walks self.caspm and executes each statement row; raises 'engine:run() called before engine:load()' if caspm is unset"} ]]
function M:run()
	if not self.caspm then
		error("engine:run() called before engine:load(); no program to execute")
	end

	for _, row in ipairs(self.caspm) do
		self:run_row(row)
	end

	return
end

--[[ {"in": {"row": "one CaspM statement row — array of atoms"}, "out": "nil — dispatches the row based on its head atom; raises unrecognized_row_head if the head doesn't match any recognized dispatch shape"} ]]
function M:run_row(row)
	local head = row[1]

	if head.bwc then
		return self:run_bwc(head.bwc, row)
	end

	log(self, {kind = 'raised', reason = 'unrecognized_row_head', head = head})
	error("unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(head) .. "}")
end

--[[ {"in": {"name": "bwc name (string)", "row": "the CaspM row whose head is this bwc"}, "out": "whatever the handler returns; raises unrecognized_bwc when name has no handler"} ]]
function M:run_bwc(name, row)
	local handler = bwc_handlers[name]

	if not handler then
		log(self, {kind = 'raised', reason = 'unrecognized_bwc', name = name})
		error("unrecognized_bwc: no handler registered for bareword command '" .. name .. "'")
	end

	log(self, {kind = 'bwc', name = name})
	return handler(self, row)
end

--[[ {"in": {"atom": "a value-producing atom"}, "out": "the Caspian value the atom evaluates to; raises unrecognized_atom_kind when the atom's key isn't one the value dispatcher handles"} ]]
function M:eval(atom)
	if atom.v ~= nil then
		return atom.v
	end

	local keys = atom_keys(atom)
	log(self, {kind = 'raised', reason = 'unrecognized_atom_kind', keys = keys})
	error("unrecognized_atom_kind: cannot evaluate atom — no rule handles atoms with keys {" .. keys .. "}")
end

return M
