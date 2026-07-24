--[[
{
	"spec":  "parse_lines_spec",
	"role":  "Exercises the opt-in line-annotation mode of the transpiler (transpile(source, {lines = true})). Confirms that (a) atom-objects carry a `line` field, (b) statement rows get a trailing `{line: N}` meta-atom, and (c) line numbers reflect the actual source-line each construct appeared on.",
	"run":   "busted tests/lua/transpiler/parse_lines_spec.lua (from repo root)"
}
]]

package.path = "./code/lua/?.lua;" .. package.path

local transpiler = require("transpiler")

describe("transpile with opts.lines", function()
	it("single setvar carries line=1 on both value-atom and trailing meta-atom", function()
		local out = transpiler.transpile("$x = 42", {lines = true})

		assert.same({
			{
				"scope", "setvar", "x",
				{value = 42, line = 1},
				{line = 1},
			},
		}, out)
	end)

	it("three setvars on lines 1/2/3", function()
		local src = "$a = 1\n$b = 2\n$c = 3\n"
		local out = transpiler.transpile(src, {lines = true})

		assert.equals(1, out[1][4].line)
		assert.equals(1, out[1][5].line)
		assert.equals(2, out[2][4].line)
		assert.equals(2, out[2][5].line)
		assert.equals(3, out[3][4].line)
		assert.equals(3, out[3][5].line)
	end)

	it("blank lines between statements skip the line count correctly", function()
		local src = "$a = 1\n\n\n$b = 2"
		local out = transpiler.transpile(src, {lines = true})

		assert.equals(1, out[1][5].line)
		assert.equals(4, out[2][5].line)
	end)

	it("comment atoms get line set as a field, not a trailing meta-atom", function()
		local out = transpiler.transpile("# hello", {lines = true})

		assert.same({{comment = "hello", line = 1}}, out)
	end)

	it("opts.lines defaults to off — no line annotations", function()
		local out = transpiler.transpile("$x = 42")

		assert.same({{"scope", "setvar", "x", {value = 42}}}, out)
	end)

	it("opts.lines = false is equivalent to omitting opts", function()
		local out = transpiler.transpile("$x = 42", {lines = false})

		assert.same({{"scope", "setvar", "x", {value = 42}}}, out)
	end)
end)
