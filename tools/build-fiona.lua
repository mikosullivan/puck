#!/usr/bin/env lua5.4
--[[
{
	"module": "build-fiona",
	"role": "Phase-1 of the build. Produces a self-contained fiona.lua source string: minifies fiona.sql and fiona-temp.sql via tools/sql-minify.lua, inlines them as string constants at the top of fiona.lua, and rewrites the file-reading block so the resulting module has no filesystem dependency for its schema. Consumers: tools/build.lua (calls .build() directly and hands the result to bundle-caspian) and the eventual standalone Fiona release build.",
	"exports": {
		"build": "() -> bundled fiona.lua source (string)"
	},
	"cli": "lua5.4 tools/build-fiona.lua > /tmp/fiona.lua — same output as .build(), written to stdout"
}
]]

local script_dir = arg[0]:match("(.*/)")
package.path = script_dir .. "?.lua;" .. package.path
local sql_minify = require("sql-minify")

local repo = script_dir .. "../"

local function slurp(path)
	local f, err = io.open(path, "r")
	if not f then error("cannot open " .. path .. ": " .. tostring(err)) end
	local s = f:read("*a")
	f:close()
	return s
end

local M = {}

--[[ {"in": {}, "out": "self-contained fiona.lua source (string)"} ]]
function M.build()
	local fiona_sql      = sql_minify.minify(slurp(repo .. "src/fiona/fiona.sql"))
	local fiona_temp_sql = sql_minify.minify(slurp(repo .. "src/fiona/fiona-temp.sql"))
	local fiona_lua      = slurp(repo .. "src/fiona/fiona.lua")

	-- Delimiter choice for the heredoc. Minified SQL contains no `]==]`;
	-- assert catches a future edit that would break the heredoc.
	for _, sql in ipairs({fiona_sql, fiona_temp_sql}) do
		assert(not sql:find("]==]"), "build-fiona: SQL contains ']==]' — bump heredoc delimiter")
	end

	local inlined = [[
------------------------------------------------------------
-- Bundled schemas — inlined by tools/build-fiona.lua at build time.
-- The source-tree fiona.lua reads these from sibling .sql files; the
-- bundled fiona.lua carries them as string constants so the shipped
-- module has no filesystem dependency.
------------------------------------------------------------

local FIONA_SQL = [==[]] .. fiona_sql .. [[]==]

local FIONA_TEMP_SQL = [==[]] .. fiona_temp_sql .. [[]==]

local SCHEMA_PATH      = "<bundled>"
local TEMP_SCHEMA_PATH = "<bundled-temp>"

local function read_file(path)
	if path == SCHEMA_PATH      then return FIONA_SQL      end
	if path == TEMP_SCHEMA_PATH then return FIONA_TEMP_SQL end
	error("read_file: bundled fiona.lua only knows its own schemas; got " .. tostring(path))
end
]]

	-- Locate and replace the "Locate fiona.sql" block. Start = the
	-- section-header comment; end = read_file's closing `end`.
	local start_anchor = "------------------------------------------------------------\n-- Locate fiona.sql"
	local end_anchor   = "\treturn content\nend"

	local block_start = fiona_lua:find(start_anchor, 1, true)
	if not block_start then error("build-fiona: could not locate start anchor in fiona.lua") end

	local end_pos = fiona_lua:find(end_anchor, block_start, true)
	if not end_pos then error("build-fiona: could not locate end anchor in fiona.lua") end

	local block_end = end_pos + #end_anchor

	return fiona_lua:sub(1, block_start - 1) .. inlined .. fiona_lua:sub(block_end + 1)
end

-- CLI shim: writes M.build() to stdout when invoked directly.
if arg and arg[0] and arg[0]:match("build%-fiona%.lua$") then
	io.write(M.build())
end

return M
