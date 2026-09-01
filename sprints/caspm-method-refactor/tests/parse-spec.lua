--[[
{
	"spec":  "parse-spec",
	"role":  "Sprint copy of the transpiler test loop. Iterates fixtures extracted from the sprint's parse.casp. For 'expects' cases, asserts (a) `caspian_caspj.transpile(source, {lines: true})` produces the expected CaspJ, and (b) `caspj_caspm.transpile(CaspJ)` equals the CaspM section if the fixture provides one, or equals the CaspJ section when the CaspM section is omitted. Convention: fixtures omit `#--- CaspM ---` when the CaspM form is identical to the CaspJ form — saves duplicating identical JSON. `#--- CaspM refactor ---` is an alias for `#--- CaspM ---` used to mark fixtures that have been rewritten to the new CaspM shape. For 'raises' cases, asserts the snippet causes transpile to raise with an error message containing the expected substring. Uses the sprint's own copies of caspian-caspj.lua and caspj-caspm.lua (production's copies stay untouched until the sprint lands).",
	"input": "sprints/caspm-method-refactor/tests/parse.casp",
	"run":   "busted sprints/caspm-method-refactor/tests/parse-spec.lua (from repo root)"
}
]]

--[[
# `parse-spec` (sprint copy)

Positive-coverage spec for the sprint's CaspM refactor. Iterates
every fixture in `sprints/caspm-method-refactor/tests/parse.casp`
and dispatches on the case kind — `expects` cases compare the CaspJ
tree against the fixture's declared JSON, and `raises` cases confirm
the snippet fails with an error message containing the expected
substring.

The CaspM section is optional on `expects` cases; when missing, the
fixture is declaring that the CaspM form is identical to the CaspJ
form, and the assertion compares `caspj_caspm.transpile(CaspJ)`
against `CaspJ` itself.

**Split source vs sprint code:**

- **Caspian → CaspJ transpiler:** sprint's copy at
  `sprints/caspm-method-refactor/src/caspian-caspj.lua`. Copied in
  from `production/src/engine/transpiler.lua` and renamed for the
  new naming convention (each layer named `<input>-<output>.lua`).
  Extended for numeric-receiver dot-method calls like
  `10.times do end` that the loops.casp fixtures exercise.
  Production's copy stays untouched until the sprint lands.
- **CaspJ → CaspM transpiler:** sprint's copy at
  `sprints/caspm-method-refactor/src/caspj-caspm.lua`. Iterate here.
]]

-- Wire up requires. Bare-name requires resolve first against the
-- sprint's src/ (for caspian-caspj + caspj-caspm), then against
-- production's src/ (fallback for anything the sprint hasn't
-- overridden), then against the sprint's tests/ (for parse-extract),
-- then against luarocks paths (dkjson, etc.).
package.path = "./sprints/caspm-method-refactor/src/?.lua;"
	.. "./production/src/engine/?.lua;"
	.. "./sprints/caspm-method-refactor/tests/?.lua;"
	.. package.path

local caspian_caspj = require("caspian-caspj")
local caspj_caspm   = require("caspj-caspm")
local extractor     = require("parse-extract")

describe("transpile parse.casp", function()
	local cases = extractor.extract("sprints/caspm-method-refactor/tests/parse.casp")

	for _, case in ipairs(cases) do
		if case.kind == "expects" then
			it(case.name .. " (parse.casp:" .. case.line .. ")", function()
				local caspj = caspian_caspj.transpile(case.source, {lines = true})
				assert.same(case.expected, caspj)

				-- Fixture convention: omitting `#--- CaspM ---` means
				-- CaspM == CaspJ. If CaspM is present, use it;
				-- otherwise fall back to CaspJ.
				local expected_caspm = case.caspm or case.expected
				assert.same(expected_caspm, caspj_caspm.transpile(caspj))
			end)

		else
			it(case.name .. " [raises] (parse.casp:" .. case.line .. ")", function()
				local ok, err = pcall(caspian_caspj.transpile, case.source)

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
