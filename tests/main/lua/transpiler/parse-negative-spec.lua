--[[
{
	"spec":  "parse-negative-spec",
	"role":  "Runs the negative test cases from parse-negative.casp. Each case is a source snippet that must cause transpile to raise with an error message containing the declared substring. Kept as a separate spec (and separate fixture file) so malformed Caspian doesn't affect parse.casp's formatting.",
	"input": "tests/main/lua/transpiler/parse-negative.casp",
	"run":   "busted tests/main/lua/transpiler/parse_negative_spec.lua (from repo root)"
}
]]

--[[
# `parse-negative-spec`

Runs every fixture in `parse-negative.casp`, all of which are
declared as `raises` cases. For each case, calls
`transpile(source)` under `pcall` and asserts that (a) the call
returns unsuccessfully and (b) the error message contains the
substring declared in the fixture. Fixtures without a `raises`
kind trigger a hard `assert` at load time — the file's whole
purpose is negative coverage, so a non-raises fixture there is a
fixture-format bug that must be surfaced loudly.
]]

package.path = "./src/engine/?.lua;./tests/main/lua/transpiler/?.lua;" .. package.path

local transpiler = require("transpiler")
local extractor  = require("parse-extract")

describe("transpile parse-negative.casp", function()
	local cases = extractor.extract("tests/main/lua/transpiler/parse-negative.casp")

	for _, case in ipairs(cases) do
		assert(case.kind == "raises",
			"parse-negative.casp:" .. case.line
				.. ": expected a raises case (%raises heredoc), got kind=" .. tostring(case.kind))

		it(case.name .. " [raises] (parse-negative.casp:" .. case.line .. ")", function()
			local ok, err = pcall(transpiler.transpile, case.source)

			assert.is_false(ok,
				"expected transpile to raise, but it returned successfully")
			assert.truthy(
				tostring(err):find(case.expected, 1, true),
				"expected error containing: " .. case.expected
					.. "\ngot: " .. tostring(err))
		end)
	end
end)
