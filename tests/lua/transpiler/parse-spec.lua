--[[
{
	"spec":  "parse-spec",
	"role":  "Loops over the boxed test cases extracted from parse.casp. For 'expects' cases, asserts (a) `transpile(source, {lines: true})` produces the expected full CaspianJ, and (b) `normalize(full)` equals the norm section if the fixture provides one, or equals the full section when the norm section is omitted. Convention: fixtures omit `#--- norm ---` when the norm form is identical to the full form — saves duplicating identical JSON across the file. For 'raises' cases, asserts the snippet causes transpile to raise with an error message containing the expected substring. parse.casp runs in line-annotated mode so each fixture pins the source-line each statement/atom lands on.",
	"input": "tests/lua/transpiler/parse.casp",
	"run":   "busted tests/lua/transpiler/parse_spec.lua (from repo root)"
}
]]

-- Wire up bare-name requires against ./code/lua/ and ./tests/lua/transpiler/.
-- Prepending to package.path preserves luarocks-provided paths (dkjson, etc.).
package.path = "./code/lua/?.lua;./tests/lua/transpiler/?.lua;" .. package.path

local transpiler = require("transpiler")
local normalize  = require("normalize")
local extractor  = require("parse-extract")

describe("transpile parse.casp", function()
	local cases = extractor.extract("tests/lua/transpiler/parse.casp")

	for _, case in ipairs(cases) do
		if case.kind == "expects" then
			it(case.name .. " (parse.casp:" .. case.line .. ")", function()
				local full = transpiler.transpile(case.source, {lines = true})
				assert.same(case.expected, full)

				-- Fixture convention: omitting `#--- norm ---` means norm == full.
				-- If norm is present, use it; otherwise fall back to full.
				local expected_norm = case.norm or case.expected
				assert.same(expected_norm, normalize.normalize(full))
			end)

		else
			it(case.name .. " [raises] (parse.casp:" .. case.line .. ")", function()
				local ok, err = pcall(transpiler.transpile, case.source)

				assert.is_false(ok,
					"expected transpile to raise, but it returned successfully")
				assert.truthy(
					tostring(err):find(case.expected, 1, true),
					"expected error containing: " .. case.expected
						.. "\ngot: " .. tostring(err))
			end)
		end
	end
end)
