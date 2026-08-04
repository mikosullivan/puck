--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Constructed with no required params — host wiring (stdout, debugger, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`, `engine.debugger = my_array`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(), will eventually execute it. Right now the tiniest possible thing: empty constructor, `stdout` and `debugger` fields, load(source) that stashes a source string and logs an entry to the debugger when one is attached.",
	"exports": {
		"new": "() -> Engine"
	},
	"stdout_contract": "The wired stdout must be an object supporting :print(text) — the raw byte-writer, no newline. Caspian-side :puts (adds newline) and everything else the sink surface exposes layer inside the engine on top of the host's :print. Not called from anywhere yet — the eventual execution path will use it. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout.",
	"debugger_contract": "The wired debugger is a Lua sequence — any table into which the engine can table.insert log entries. Each entry is a hash of whatever the engine chose to record at that site (kind, source_length, etc. — no required fields). Permanent slot: coders patching Caspian or diving into engine internals attach any sequence they want and read it back to trace what the engine did. Not spec'd to grow methods — the array shape is the whole surface."
}
]=]

local M = {}
M.__index = M

--[[ {"in": {}, "out": "Engine instance — no wiring attached yet"} ]]
function M.new()
	return setmetatable({
		stdout   = nil,
		debugger = nil,
		source   = nil,
	}, M)
end

--[[ {"in": {"source": "Caspian source string"}, "out": "nil — stashes the source and logs a 'loaded' entry to the debugger if one is attached"} ]]
function M:load(source)
	self.source = source

	if self.debugger then
		table.insert(self.debugger, {kind = 'loaded', source_length = #source})
	end

	return
end

return M
