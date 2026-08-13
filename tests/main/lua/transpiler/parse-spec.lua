--[[
{
	"spec":  "parse-spec",
	"role":  "Loops over the boxed test cases extracted from parse.casp. For 'expects' cases, asserts (a) `transpile(source, {lines: true})` produces the expected full CaspianJ, and (b) `normalize(full)` equals the norm section if the fixture provides one, or equals the full section when the norm section is omitted. Convention: fixtures omit `#--- norm ---` when the norm form is identical to the full form — saves duplicating identical JSON across the file. For 'raises' cases, asserts the snippet causes transpile to raise with an error message containing the expected substring. parse.casp runs in line-annotated mode so each fixture pins the source-line each statement/atom lands on.",
	"input": "tests/main/lua/transpiler/parse.casp",
	"run":   "busted tests/main/lua/transpiler/parse_spec.lua (from repo root)"
}
]]

--[[
# `parse-spec`

Positive-coverage spec for the transpiler. Iterates every fixture
in `parse.casp` and dispatches on the case kind — `expects` cases
compare the CaspJ tree against the fixture's declared JSON, and
`raises` cases confirm the snippet fails with an error message
containing the expected substring.

The `norm` section is optional on `expects` cases; when it's
missing, the fixture is declaring that the norm form is identical
to the full form, and the assertion compares `normalize(full)`
against `full` itself. That convention keeps the `.casp` file
readable — most fixtures don't need to spell out identical JSON
twice.
]]

-- Wire up bare-name requires against ./src/engine/ and ./tests/main/lua/transpiler/.
-- Prepending to package.path preserves luarocks-provided paths (dkjson, etc.).
package.path = "./src/engine/?.lua;./tests/main/lua/transpiler/?.lua;" .. package.path

local transpiler = require("transpiler")
local normalize  = require("normalize")
local extractor  = require("parse-extract")

describe("transpile parse.casp", function()
	local cases = extractor.extract("tests/main/lua/transpiler/parse.casp")

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
