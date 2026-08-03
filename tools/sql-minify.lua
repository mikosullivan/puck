#!/usr/bin/env lua5.4
--[[
{
	"module": "sql-minify",
	"role": "Build-time SQL minifier. Follows the four-step algorithm Miko settled on (comment-only line strip, whitespace collapse, whitespace strip around parens, whitespace strip around punctuation). Used at build time on fiona.sql and fiona-temp.sql so the shipped bytes are ≈38% of raw. See requirements/core/build.md.",
	"exports": {
		"minify": "sql (string) -> minified sql (string)"
	},
	"cli": "lua5.4 tools/sql-minify.lua < input.sql > output.sql — reads stdin, writes stdout"
}
]]

local M = {}

-- Escape a single character for use in a Lua pattern.
local function pattern_escape(c)
	if c:match("[%(%)%.%%%+%-%*%?%[%]%^%$]") then
		return "%" .. c
	end
	return c
end

--- Minify SQL source. The four-step process:
--- (1) Delete comment-only lines (whole line is `-- comment`).
--- (2) Collapse contiguous whitespace runs to a single space; trim ends.
--- (3) Strip whitespace around parens.
--- (4) Strip whitespace around ,;=<>+-*/! — except omit `-` from the set
---     if the intermediate text contains a `- -` sequence, since stripping
---     it there would produce `--` and SQL would read the rest as a line
---     comment.
---
--- Assumes no mid-line comments (`code -- comment`) and no string literals
--- carrying meaningful whitespace. Both hold for the SQL Caspian ships;
--- raises an error at the mid-line-comment case so a caller finds out
--- rather than shipping a broken minified file.
--[[ {"in": "sql (string)", "out": "minified sql (string)"} ]]
function M.minify(sql)
	-- Guardrail: mid-line comments break this algorithm. A `-- comment`
	-- with code before it on the same line survives step 1 (only whole-
	-- line comments strip), then step 2 collapses the terminating newline
	-- into a space, and the `--` proceeds to swallow the rest of the
	-- input. Raise so the caller notices.
	for line in sql:gmatch("[^\n]+") do
		-- Check for `--` NOT at the start of the line's non-whitespace
		-- content. `^%s*%-%-` is a leading comment (fine); anything else
		-- with `--` is mid-line.
		if line:match("%-%-") and not line:match("^%s*%-%-") then
			error("sql-minify: mid-line comment detected — algorithm assumes only whole-line comments. Offending line: " .. line, 2)
		end
	end

	-- Step 1: delete comment-only lines.
	local lines = {}
	for line in sql:gmatch("[^\n]+") do
		if not line:match("^%s*%-%-") then
			table.insert(lines, line)
		end
	end
	local text = table.concat(lines, "\n")

	-- Step 2: collapse contiguous whitespace runs to a single space; trim.
	text = text:gsub("%s+", " ")
	text = text:gsub("^ ", ""):gsub(" $", "")

	-- Step 3: strip whitespace around parens.
	text = text:gsub(" *%( *", "(")
	text = text:gsub(" *%) *", ")")

	-- Step 4: strip whitespace around punctuation. Detect `- -` first —
	-- if present, omit `-` from the strip set (otherwise the result would
	-- contain `--` and SQL would read the rest as a line comment).
	local puncts = ",;=<>+*/!"
	if not text:find("%- %-") then
		puncts = puncts .. "-"
	end

	for i = 1, #puncts do
		local c = puncts:sub(i, i)
		local pattern = " *" .. pattern_escape(c) .. " *"
		text = text:gsub(pattern, c)
	end

	return text
end

-- CLI entry point: run when invoked directly (not `require`d).
if arg and arg[0] and arg[0]:match("sql%-minify%.lua$") then
	local input = io.read("*a")
	io.write(M.minify(input))
end

return M
