--[[
{
	"module":  "parse-extract",
	"role":    "Extracts test cases from a Caspian source file that uses the boxed fixture format. Each fixture is delimited by `#===...` outer borders and carries a `#--- code ---` section plus one of: `#--- CaspJ ---` (JSON — the expected CaspJ from `transpile(source, {lines: true})`), `#--- CaspM ---` (JSON — the expected CaspM from `normalize(CaspJ)`), or `#--- raises ---` (plain-text error substring). An 'expects' fixture has both `CaspJ` and `CaspM`. Also accepts `#--- CaspM refactor ---` — same shape as `CaspM`, used to mark fixtures already converted to the refactored CaspM form; the extractor treats it identically. Section content ends at the next `#-----...` bare closing border. Regex-based; does not depend on the transpiler.",
	"exports": {
		"extract": "path (string) -> [ {name, line, kind, expected, caspm?, source}, ... ]"
	},
	"case_shape": {
		"name":           "string — from a '# name: LABEL' comment (opener; the trailing closer of the same fixture is optional and ignored if present)",
		"line":           "integer — line in the source file where the fixture opens",
		"kind":           "'expects' | 'raises'",
		"expected":       "for 'expects': the decoded CaspJ (Lua table). for 'raises': a plain-text substring the error message must contain.",
		"caspm":          "for 'expects' only: the decoded CaspM (Lua table). Absent when the fixture has no `#--- CaspM ---` section — by convention, that means the CaspM form is identical to the CaspJ form, and parse-spec.lua defaults to comparing normalize(CaspJ) against the CaspJ section itself.",
		"source":         "Caspian source snippet (from the code section); leading/trailing whitespace trimmed"
	}
}
]]

--[[
# `parse-extract`

Fixture extractor for the transpiler test suite. `parse-spec.lua`
feeds it a `.casp` file whose fixtures are delimited by boxed
comments (`#=== ... ===`, `#--- code ---`, `#--- CaspJ ---`,
`#--- CaspM ---`, `#--- CaspM refactor ---`, `#--- raises ---`);
`extract` walks the file line-by-line and returns a list of case
tables the spec files iterate through.

Purely regex-based — the transpiler is not in the require chain,
so this module can be loaded and exercised independently. Its
`extract` function is one of the surfaces `infrastructure_spec`
smoke-checks.

The fixture format keeps expected / raised strings visually
adjacent to the source they belong to, which makes hand-editing the
`.casp` files tractable — the alternative is a Lua table wall.
]]

local json = require("dkjson")

local M = {}

local function trim(s)
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

--[[
{
	"in":   {"path": "string — path to a .casp file"},
	"out":  "list of case tables (see case_shape)",
	"raises": "when a `CaspJ` section does not contain valid JSON"
}
]]
function M.extract(path)
	local file = assert(io.open(path, "r"))
	local content = file:read("*a")
	file:close()

	local cases = {}

	-- Fixture-in-progress state
	local current = nil        -- {name, line, kind?, expected?, source?}
	local section_name = nil   -- "code" | "CaspJ" | "CaspM" | "raises" while inside one
	local section_lines = {}

	local function finalize_section()
		if not section_name then return end
		local body = table.concat(section_lines, "\n")

		if section_name == "code" then
			current.source = trim(body)

		elseif section_name == "CaspJ" then
			-- Pass json.null as the third arg so JSON null decodes to the dkjson
			-- null sentinel (not Lua nil, which would silently drop the key).
			local decoded, _, err = json.decode(body, 1, json.null)
			if not decoded then
				error(path .. ":" .. current.line
					.. ": CaspJ is not valid JSON: " .. tostring(err))
			end
			current.kind = "expects"
			current.expected = decoded

		elseif section_name == "CaspM" then
			local decoded, _, err = json.decode(body, 1, json.null)
			if not decoded then
				error(path .. ":" .. current.line
					.. ": CaspM is not valid JSON: " .. tostring(err))
			end
			current.caspm = decoded

		elseif section_name == "raises" then
			current.kind = "raises"
			current.expected = trim(body)
		end

		section_name = nil
		section_lines = {}
	end

	local function commit_current()
		if current and current.kind then
			table.insert(cases, current)
		end
		current = nil
	end

	local lineno = 0
	for line in content:gmatch("([^\n]*)\n?") do
		lineno = lineno + 1
		local t = trim(line)

		if section_name then
			-- Inside a section — accumulate until we hit the bare `#-----...` closer.
			if t:match("^#%-+$") then
				finalize_section()
			else
				table.insert(section_lines, line)
			end

		else
			-- Outer boundaries and headers.
			if t:match("^#=+$") then
				-- outer border, cosmetic — skip

			else
				local name = line:match("^%s*#%s*name:%s*(.-)%s*$")
				-- Strip a trailing `[ghi]` marker (with any preceding
				-- whitespace) — it's an issue-filing button in the
				-- rendered .casp view (see orlando.caspian_page), not
				-- part of the fixture name. Opener lines carry it;
				-- closers currently don't. Stripping here keeps opener
				-- and closer names comparable and keeps `[ghi]` out of
				-- the busted test-name output.
				if name then
					name = name:gsub("%s*%[ghi%]%s*$", "")
				end
				-- Non-greedy `.-` so multi-word section labels like
				-- `CaspM refactor` are captured whole (up to the trailing
				-- dashes), not just the first word.
				local sec_open = t:match("^#%-%-%-+%s+(.-)%s+%-+$")

				if name and name ~= "" then
					if current and current.name == name then
						-- Closing marker for the current fixture. Finalize.
						commit_current()
					else
						-- Opener for a new fixture. Finalize any predecessor
						-- (should be nil when reached, but be defensive).
						commit_current()
						current = {name = name, line = lineno}
					end

				elseif sec_open then
					-- `CaspM refactor` is an alias for `CaspM` — used to
					-- mark fixtures that have been rewritten to the new
					-- shape. The extractor treats them identically; the
					-- distinction is a human-facing marker only.
					if sec_open == "CaspM refactor" then
						section_name = "CaspM"
					else
						section_name = sec_open
					end
					section_lines = {}
				end
			end
		end
	end

	-- End-of-file safety net.
	finalize_section()
	commit_current()

	return cases
end

return M
