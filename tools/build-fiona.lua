#!/usr/bin/env lua5.4
--[[
{
	"module": "build-fiona",
	"role": "Phase-1 of the build. Produces a self-contained fiona.lua on stdout: minifies fiona.sql and fiona-temp.sql via tools/sql-minify.lua, inlines them as string constants at the top of fiona.lua, and rewrites the file-reading block so the resulting module has no filesystem dependency for its schema. Consumers: tools/build.sh (writes stdout to a temp file that phase-2 then bundles into caspian.lua) and the eventual standalone Fiona release build.",
	"usage": "lua5.4 tools/build-fiona.lua > /tmp/fiona.lua"
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

local fiona_sql       = sql_minify.minify(slurp(repo .. "src/fiona/fiona.sql"))
local fiona_temp_sql  = sql_minify.minify(slurp(repo .. "src/fiona/fiona-temp.sql"))
local fiona_lua       = slurp(repo .. "src/fiona/fiona.lua")

-- Delimiter choice for the heredoc string. The minified SQL contains no
-- `]==]`, so `[==[...]==]` is safe. If a future SQL edit adds `]==]`
-- somehow, this assertion catches it before the shipped file breaks.
for _, sql in ipairs({fiona_sql, fiona_temp_sql}) do
	assert(not sql:find("]==]"), "build-fiona: SQL contains ']==]' — bump heredoc delimiter")
end

-- Replacement for the "Locate fiona.sql" block. The original derives
-- SCHEMA_PATH / TEMP_SCHEMA_PATH from the on-disk source location and
-- defines read_file() to slurp them. In the bundled build, we inline
-- the minified SQL directly and shim read_file() so callers still work.
local inlined_block = [[
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

-- Locate and replace the "Locate fiona.sql" block in the source. The
-- start anchor is the section-header comment that opens the block; the
-- end anchor is read_file's closing `end`. Both are matched as plain
-- (non-pattern) strings on distinctive lines that only appear once.
local start_anchor = "------------------------------------------------------------\n-- Locate fiona.sql"
local end_anchor   = "\treturn content\nend"

local block_start = fiona_lua:find(start_anchor, 1, true)
if not block_start then error("build-fiona: could not locate start anchor in fiona.lua") end

local end_pos = fiona_lua:find(end_anchor, block_start, true)
if not end_pos then error("build-fiona: could not locate end anchor in fiona.lua") end

local block_end = end_pos + #end_anchor

-- Emit: everything before the block, the inlined replacement, everything after.
io.write(fiona_lua:sub(1, block_start - 1))
io.write(inlined_block)
io.write(fiona_lua:sub(block_end + 1))
