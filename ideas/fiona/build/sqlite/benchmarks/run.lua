#!/usr/bin/env lua5.4
--[[
{
	"module": "run",
	"role": "Bench runner. Dispatches to per-scenario files by short id. Each scenario is a self-contained Lua file that sets up its own disk DB, runs its workload with timing, and prints a report.",
	"usage": "lua5.4 run.lua <scenario-id>",
	"scenarios": {
		"a": "wide-flat hash — one hash with N fresh keys"
	},
	"env_vars": "N, BUCKET, BATCH — passed through to the scenario for tunable size"
}
]]

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local scenario = arg[1]

if not scenario then
	print("usage: lua5.4 run.lua <scenario-id>")
	print()
	print("scenarios:")
	print("  a  wide-flat hash (100k keys via set_hash_element)")
	print()
	print("env vars:")
	print("  N        total ops                (default per-scenario)")
	print("  BUCKET   throughput-curve bucket  (default per-scenario)")
	print("  BATCH    transaction chunk        (default per-scenario)")
	os.exit(1)
end

local file_map = {
	a = "scenario_a.lua",
}

local file = file_map[scenario]

if not file then
	print("unknown scenario: " .. tostring(scenario))
	os.exit(1)
end

dofile(script_dir .. file)
