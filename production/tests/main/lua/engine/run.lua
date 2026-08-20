#!/usr/bin/env lua5.4

--[[
{
	"module": "run",
	"role": "Runner for the engine test suite. Discovers every `test_*.lua` file at or under this directory (recursive), sources each one under a shared `helpers` accumulator, and prints an aggregated pass/fail report. Backend-specific tests live in subdirectories (e.g. `sqlite/`); the runner walks them all. Sets `package.path` so the fresh engine code under `src/engine/` resolves via bare-name requires (`require('engine')`, `require('cvm.sqlite.open')`, etc.).",
	"run": "lua5.4 tests/main/lua/engine/run.lua (from repo root)"
}
]]

--[[
# `run`

Discovers and runs every `test_*.lua` file at or under this
directory. Backend-specific suites live in subdirectories — e.g.
`sqlite/` for tests that assert against the CVM's SQLite
implementation (schema DDL, triggers, table structure). The
non-backend tests (engine dispatch API, Sequence, host-wiring smoke)
sit at the top level. Each file registers cases via `helpers.test`;
`run` calls `helpers.reset` before each file so failures aggregate
per-file, then prints a final summary line and exits 0 on all-pass
/ 1 on any-failure.

`package.path` is set so `require('engine')`, `require('normalize')`,
`require('cvm.sqlite.open')`, and the other bare-name requires the tests
issue resolve against `src/engine/`. `package.cpath` picks up the
system `luarocks` tree for `lsqlite3.so`. `helpers` and `larry`
resolve against this file's directory so subdirectory tests find them
without further configuration.
]]

local script_dir = arg[0]:match('(.*/)') or './'
local home = os.getenv('HOME') or ''
package.path = script_dir .. '../../../../src/engine/?.lua;'
	.. script_dir .. '../../../../src/engine/?/init.lua;'
	.. script_dir .. '?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?.lua;'
	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
	.. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local h = require('helpers')

--[[
Recursively find every `test_*.lua` under `dir`. Returns paths as
they appear relative to `dir` (with subdir prefix), sorted, so the
runner's per-file line prints something like `sqlite/test_schema.lua`
rather than a bare filename that could collide across subdirs.
]]
local function list_test_files(dir)
	local files = {}
	local handle = io.popen('find "' .. dir .. '" -type f -name "test_*.lua" 2>/dev/null')

	if not handle then
		return files
	end

	for line in handle:lines() do
		-- Strip the directory prefix so the returned path is relative to `dir`.
		local rel = line:sub(#dir + 1)
		if rel:match('^test_.*%.lua$') or rel:match('/test_.*%.lua$') then
			table.insert(files, rel)
		end
	end

	handle:close()
	table.sort(files)

	return files
end

local files = list_test_files(script_dir)
local total_passed = 0
local total_failed = 0
local all_failures = {}

for _, file in ipairs(files) do
	h.reset()
	local ok, err = xpcall(function()
		dofile(script_dir .. file)
	end, debug.traceback)

	if not ok then
		h.results.failed = h.results.failed + 1
		table.insert(h.results.failures, {name = '(file load)', err = err})
	end

	print(string.format('%-40s %d passed, %d failed', file, h.results.passed, h.results.failed))
	total_passed = total_passed + h.results.passed
	total_failed = total_failed + h.results.failed

	for _, f in ipairs(h.results.failures) do
		table.insert(all_failures, {file = file, name = f.name, err = f.err})
	end
end

print()
print(string.format('TOTAL: %d passed, %d failed', total_passed, total_failed))

if total_failed > 0 then
	print()
	print('Failures:')

	for _, f in ipairs(all_failures) do
		print(string.format('  [%s] %s:', f.file, f.name))

		for line in tostring(f.err):gmatch('[^\n]+') do
			print('    ' .. line)
		end
	end

	os.exit(1)
end

os.exit(0)
