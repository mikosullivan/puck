#!/usr/bin/env lua5.4
--[[
Demo runner for the postnormalize pass.

For each fixture source, transpiles + normalizes via production,
then applies the sprint's postnormalize pass. Prints before / after
CaspM side-by-side so the rewrite is visible.

Invoke from anywhere:

	lua5.4 sprints/expressions/src/demo.lua        -- from repo root
	lua5.4 demo.lua                                -- from src dir

Bare `lua` on this box is Lua 5.1 — use `lua5.4` explicitly.
]]

-- Self-locate. arg[0] is the script path as invoked; peel off the
-- filename to get its directory, then walk up to the repo root.
local script_dir = arg[0]:match('^(.*)/') or '.'
local repo_root  = script_dir .. '/../../..'
local home       = os.getenv('HOME') or ''

package.path = repo_root .. '/production/src/engine/?.lua;'
	.. repo_root .. '/sprints/expressions/src/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local transpiler    = require('transpiler')
local normalize     = require('normalize')
local postnormalize = require('postnormalize')
local dkjson        = require('dkjson')

local FIXTURES = {
	{
		label = "short-circuit `||`",
		src   = "$x = $a || $b",
	},
	{
		label = "short-circuit `&&`",
		src   = "$x = $a && $b",
	},
	{
		label = "if / then / end (one-arm)",
		src   = "if $foo\n\t&bar\nend",
	},
	{
		label = "if / then / else",
		src   = "if $foo\n\t&bar\nelse\n\t&baz\nend",
	},
	{
		label = "if / elsif / else",
		src   = "if $foo\n\t&bar\nelsif $baz\n\t&zap\nelse\n\t&gup\nend",
	},
	{
		label = "while loop",
		src   = "while $x < 10\n\t$x++\nend",
	},
	{
		label = "unless (should flow through if-rewrite)",
		src   = "unless $foo then $bar end",
	},
}

local function pretty(caspm)
	return dkjson.encode(caspm, {indent = true})
end

for _, f in ipairs(FIXTURES) do
	print('==================================================')
	print('label:  ' .. f.label)
	print('==================================================')
	print('source:')
	print(f.src)
	print()

	local ok, caspj = pcall(transpiler.transpile, f.src)

	if not ok then
		print('PARSE-FAIL: ' .. tostring(caspj):match(':%s*(.*)$'))
		print()
		goto continue
	end

	local caspm_before = normalize.normalize(caspj)
	local caspm_after  = postnormalize.process(caspm_before)

	print('caspm (production normalizer):')
	print(pretty(caspm_before))
	print()
	print('caspm (after sprint postnormalize):')
	print(pretty(caspm_after))
	print()

	::continue::
end
