--[[
{
	"spec":  "parse_negative_spec",
	"role":  "Runs the negative test cases from parse-negative.casp. Each case is a source snippet that must cause transpile to raise with an error message containing the declared substring. Kept as a separate spec (and separate fixture file) so malformed Caspian doesn't affect parse.casp's formatting.",
	"input": "tests/lua/transpiler/parse-negative.casp",
	"run":   "busted tests/lua/transpiler/parse_negative_spec.lua (from repo root)"
}
]]

package.path = "./code/lua/?.lua;./tests/lua/transpiler/?.lua;" .. package.path

local transpiler = require("transpiler")
local extractor  = require("parse_extract")

describe("transpile parse-negative.casp", function()
	local cases = extractor.extract("tests/lua/transpiler/parse-negative.casp")

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
