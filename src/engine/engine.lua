--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Constructed with no required params — host wiring (stdout, eventually stdin/stderr and whatever else) attaches through plain field assignment on the engine (`engine.stdout = my_stdout`) so a program that doesn't need a given resource doesn't force its host to provide one. Accepts Caspian source via load(), will eventually execute it. Right now the tiniest possible thing: empty constructor, `stdout` field for the wired stdout, load(source) that stashes a source string, and hi() that writes 'hi' to the wired stdout — enough to prove the wiring works and to grow outward from.",
	"exports": {
		"new": "() -> Engine"
	},
	"stdout_contract": "The wired stdout must be an object supporting :puts(text). :write(...) may be called by future engine features but hi() only uses :puts. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout."
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

--[[ {"in": {}, "out": "nil — writes the literal line 'hi' to the wired stdout via :puts. Raises if stdout isn't wired."} ]]
function M:hi()
	if self.stdout == nil then
		error("engine:hi() — no stdout is wired; set engine.stdout first", 2)
	end

	self.stdout:puts("hi")
	return
end

return M
