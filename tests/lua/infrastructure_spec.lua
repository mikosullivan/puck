--[[
{
	"spec":  "infrastructure_spec",
	"role":  "Smoke test — verifies every Lua library the transpiler test suite depends on loads and exposes its expected surface. Runs first so infrastructure failures are diagnosed cleanly, before any construct-specific test noise.",
	"run":   "busted tests/lua/ (from repo root; runs alongside the transpiler specs)"
}
]]

-- Wire up bare-name requires against ./code/lua/ and ./tests/lua/transpiler/.
-- Prepending preserves luarocks-provided paths (dkjson, busted itself, etc.).
package.path = "./code/lua/?.lua;./tests/lua/transpiler/?.lua;" .. package.path

describe("infrastructure", function()

	it("dkjson loads and exposes decode / encode", function()
		local ok, mod = pcall(require, "dkjson")
		assert.is_true(ok, "dkjson failed to load: " .. tostring(mod))
		assert.is_function(mod.decode)
		assert.is_function(mod.encode)
	end)

	it("transpiler loads and exposes transpile", function()
		local ok, mod = pcall(require, "transpiler")
		assert.is_true(ok, "transpiler failed to load: " .. tostring(mod))
		assert.is_function(mod.transpile)
	end)

	it("parse_extract loads and exposes extract", function()
		local ok, mod = pcall(require, "parse_extract")
		assert.is_true(ok, "parse_extract failed to load: " .. tostring(mod))
		assert.is_function(mod.extract)
	end)

	it("parse.casp is readable at the expected path", function()
		local f, err = io.open("tests/lua/transpiler/parse.casp", "r")
		assert.is_not_nil(f, "parse.casp not readable: " .. tostring(err))
		f:close()
	end)

	it("parse.casp yields at least one test case", function()
		local extractor = require("parse-extract")
		local cases = extractor.extract("tests/lua/transpiler/parse.casp")
		assert.is_true(#cases >= 1,
			"expected at least one test case in parse.casp, got " .. #cases)
	end)

end)
