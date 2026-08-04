--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Constructed with no required params — host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(source), which transpiles + normalizes it into a CaspM tree ready for run() to walk. Right now the tiniest thing that has a program in it: empty constructor, `stdout` / `debugger` / `source` / `caspj` / `caspm` fields, load(source) that runs the parse pipeline and logs a 'loaded' entry to the debugger.",
	"exports": {
		"new": "() -> Engine"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Not called from anywhere yet — the eventual execution path will use it. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface."
}
]=]

local transpiler = require('transpiler')
local normalize  = require('normalize')

local M = {}
M.__index = M

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

	if self.debugger then
		table.insert(self.debugger, {kind = 'loaded', source_length = #source})
	end

	return
end

return M
