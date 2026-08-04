--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Constructed with no required params — host wiring (stdout, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(), will eventually execute it. Right now the tiniest possible thing: empty constructor, a `stdout` field for the wired stdout, and load(source) that stashes a source string.",
	"exports": {
		"new": "() -> Engine"
	},
	"stdout_contract": "The wired stdout must be an object supporting :puts(text). Not called from anywhere yet — the eventual execution path will use it. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout."
}
]=]

local M = {}
M.__index = M

--[[ {"in": {}, "out": "Engine instance — no wiring attached yet"} ]]
function M.new()
	return setmetatable({
		stdout = nil,
		source = nil,
	}, M)
end

--[[ {"in": {"source": "Caspian source string"}, "out": "nil — stashes the source; does nothing else yet"} ]]
function M:load(source)
	self.source = source
	return
end

return M
