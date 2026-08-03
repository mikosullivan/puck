#!/usr/bin/env lua5.4
--[[
{
	"module": "run",
	"role": "Bench runner. Dispatches to per-scenario files by short id, or runs all scenarios when 'all' is passed. Each scenario is a self-contained Lua file that sets up its own disk DB, runs its workload with timing, and prints a report.",
	"usage": "lua5.4 run.lua <scenario-id | 'all'>",
	"scenarios": {
		"a": "wide-flat hash of inline scalars — one hash with N scalar-carrying rows via set_hash_scalar",
		"b": "deep linear-chain teardown — build root → h → h → ... N deep, then time delete_hash_element(1,'top')"
	},
	"env_vars": "N, BUCKET, BATCH, AUTOCOMMIT — passed through to the scenario"
}
]]

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local scenario = arg[1]

local file_map = {
	a = "scenario_a.lua",
	b = "scenario_b.lua",
}

if not scenario then
	print("usage: lua5.4 run.lua <scenario-id | 'all'>")
	print()
	print("scenarios:")
	print("  a    wide-flat hash of inline scalars (default 10k ops via set_hash_scalar)")
	print("  b    deep linear-chain teardown (default 10k-deep via delete_hash_element)")
	print("  all  run every scenario in sequence")
	print()
	print("env vars:")
	print("  N           total ops / chain depth  (default per-scenario)")
	print("  BUCKET      throughput-curve bucket  (default per-scenario)")
	print("  BATCH       transaction chunk        (default per-scenario)")
	print("  AUTOCOMMIT  set to skip transaction wrapping (scenario A only)")
	os.exit(1)
end

if scenario == "all" then
	local ids = {}

	for k in pairs(file_map) do
		ids[#ids + 1] = k
	end

	table.sort(ids)

	for _, id in ipairs(ids) do
		print(string.rep("=", 72))
		print(string.format("SCENARIO %s", id:upper()))
		print(string.rep("=", 72))
		print()
		dofile(script_dir .. file_map[id])
		print()
	end

	os.exit(0)
end

local file = file_map[scenario]

if not file then
	print("unknown scenario: " .. tostring(scenario))
	os.exit(1)
end

dofile(script_dir .. file)
