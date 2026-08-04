--[=[
{
	"module": "engine",
	"role": "Caspian's runtime. Takes host wiring (stdout, eventually stdin/stderr and whatever else) at construction, accepts Caspian source via load(), will eventually execute it. Right now the tiniest possible thing: a constructor that captures its stdout, a load() that stashes a source string, and a hi() method that writes 'hi' to the wired stdout — enough to prove the stdout wiring works and to grow outward from.",
	"exports": {
		"new": "opts -> Engine (opts.stdout required; the object must respond to :puts(text))"
	},
	"stdout_contract": "The wired stdout must be an object supporting :puts(text). :write(...) may be called by future engine features but hi() only uses :puts. Tests wire a FakeStdout; the eventual CLI wires an object over io.stdout."
}
]=]

local M = {}
M.__index = M

--[[ {"in": {"opts": "table with .stdout — the host-provided stdout object"}, "out": "Engine instance"} ]]
function M.new(opts)
	opts = opts or {}

	if opts.stdout == nil then
		error("engine.new: opts.stdout is required", 2)
	end

	return setmetatable({
		stdout = opts.stdout,
		source = nil,
	}, M)
end

--[[ {"in": {"source": "Caspian source string"}, "out": "nil — stashes the source; does nothing else yet"} ]]
function M:load(source)
	self.source = source
	return
end

--[[ {"in": {}, "out": "nil — writes the literal line 'hi' to the wired stdout via :puts"} ]]
function M:hi()
	self.stdout:puts("hi")
	return
end

return M
