--[=[
{
	"module": "test-base",
	"role": "Central testing library for Caspian — loads and runs Caspian source as an embedded language inside the Lua test process. Serves the same role the eventual Caspian CLI will fill (transpile, normalize, execute), except every test gets its own fresh engine and a fake STDOUT that captures output for assertion instead of writing to the real terminal. Tests build on this rather than reimplementing the load path per file. Real engine-population libraries live under src/engine/; test-base is deliberately in tests/ because it only exists to make tests possible.",
	"exports": {
		"new":         "() -> Engine (fresh instance with its own FakeStdout)",
		"Engine":      "class — the embedding surface",
		"FakeStdout":  "class — captures writes; use engine.stdout in tests"
	},
	"cli_analogue": "The eventual caspian CLI will run the same load path (transpile source → normalize to AST → hand to interpreter) but wire real STDOUT/STDIN. test-base swaps STDOUT for a capturable object; everything else is the same code path so bugs in the embedding surface get caught by tests."
}
]=]

-- Locate ourselves so package.path finds the engine modules regardless
-- of the test's own cwd. Using debug.getinfo(1, "S") because arg[0]
-- points at the outermost script, not this module's own file.
local this_source = debug.getinfo(1, "S").source

if this_source:sub(1, 1) == "@" then
	this_source = this_source:sub(2)
end

local this_dir = this_source:match("(.*/)") or "./"

package.path = this_dir .. "../src/engine/?.lua;" .. package.path

-- Wire the per-user luarocks install so external Lua deps resolve
-- (dkjson is what transpiler.lua reaches for). Optional — silent if
-- luarocks isn't set up on this host.
local home = os.getenv("HOME") or "."

package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath
package.path  = home .. "/.luarocks/share/lua/5.4/?.lua;" .. package.path

local M = {}

------------------------------------------------------------
-- FakeStdout — captures writes so tests can inspect output.
--
-- Same call surface (approximately) as the eventual real stdout the
-- CLI wires: `:write(...)` appends, `:puts(text)` appends with a
-- trailing newline. Extra methods (`get_all`, `get_lines`, `clear`,
-- `has_output`) exist for assertions and don't appear on real stdout.
------------------------------------------------------------

local FakeStdout = {}
FakeStdout.__index = FakeStdout

--[[ {"in": {}, "out": "FakeStdout instance"} ]]
function FakeStdout.new()
	return setmetatable({buffer = {}}, FakeStdout)
end

--[[ {"in": {"...": "any values"}, "out": "nil — appends the stringified args to the buffer"} ]]
function FakeStdout:write(...)
	local args = {...}

	for i = 1, #args do
		table.insert(self.buffer, tostring(args[i]))
	end

	return
end

--[[ {"in": {"text": "any — stringified"}, "out": "nil — appends text + newline"} ]]
function FakeStdout:puts(text)
	self:write(tostring(text) .. "\n")
	return
end

--[[ {"in": {}, "out": "string — everything written so far, concatenated"} ]]
function FakeStdout:get_all()
	return table.concat(self.buffer)
end

--[[ {"in": {}, "out": "list of strings — output split on newlines. Trailing newline (if any) does NOT produce a trailing empty line."} ]]
function FakeStdout:get_lines()
	local text = self:get_all()

	if text == "" then
		return {}
	end

	local lines = {}

	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end

	-- Strip the trailing empty line the gmatch loop appended when the
	-- source text ended with a newline (the last "\n" produces an empty
	-- captured segment that isn't a real line of output).
	if lines[#lines] == "" and text:sub(-1) == "\n" then
		table.remove(lines)
	end

	return lines
end

--[[ {"in": {}, "out": "nil — empties the buffer"} ]]
function FakeStdout:clear()
	self.buffer = {}
	return
end

--[[ {"in": {}, "out": "boolean — true iff anything has been written"} ]]
function FakeStdout:has_output()
	return #self.buffer > 0
end

------------------------------------------------------------
-- Engine — the embedding surface.
--
-- Fresh instance per test, each with its own FakeStdout. The engine
-- holds references to the loaded engine modules so tests can reach
-- them directly (`engine.transpiler.transpile(...)`, etc.) as well as
-- via the curated methods below. Both the raw reach and the curated
-- methods are supported on purpose — different tests want different
-- levels of directness.
------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

--[[ {"in": {}, "out": "Engine instance"} ]]
function Engine.new()
	local transpiler = require("transpiler")
	local normalize  = require("normalize")
	local trivet     = require("trivet")

	return setmetatable({
		stdout     = FakeStdout.new(),
		transpiler = transpiler,
		normalize  = normalize,
		trivet     = trivet,
	}, Engine)
end

--[[ {"in": {"source": "Caspian source string", "opts": "table? — passed through to transpiler.transpile"}, "out": "CaspJ table — the full-format AST before normalization"} ]]
function Engine:transpile(source, opts)
	return self.transpiler.transpile(source, opts)
end

--[[ {"in": {"source": "Caspian source string"}, "out": "CaspJ table — the normalized AST the interpreter would walk"} ]]
function Engine:load(source)
	local full = self.transpiler.transpile(source)
	local norm = self.normalize.normalize(full)

	return norm
end

--[[ {"in": {"source": "Caspian source string"}, "out": "whatever the program returns. For now, the normalized AST — the interpreter isn't wired yet; :run() returns :load()'s result until it is. Once the interpreter lands, this will walk the AST against self.stdout and return the program's actual return value."} ]]
function Engine:run(source)
	local ast = self:load(source)
	return ast
end

------------------------------------------------------------
-- Module exports
------------------------------------------------------------

M.Engine     = Engine
M.FakeStdout = FakeStdout

--[[ {"in": {}, "out": "Engine instance — shorthand for Engine.new()"} ]]
function M.new()
	return Engine.new()
end

return M
