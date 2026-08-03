--[[
{
	"module": "scenario_b",
	"role": "Deep linear-chain teardown. Build root → h → h → ... → h (N deep), then measure how long the single delete_hash_element(1, 'top') call takes to sweep the whole chain via the Drinian-style Lua drain. Exercises the drain's iteration behavior: one seed per loop iteration, cascade-driven needs_trace population, and the (parent, key) / relationships_child indexes doing per-iteration lookups.",
	"transaction_model": "Build phase wraps in one db:atomic() (setup, not measured). Teardown is a bare delete_hash_element call — the library wraps it in its own atomic() savepoint internally, so we measure exactly what a caller sees from one API call. No manual batching.",
	"knobs": {
		"N": "chain depth (default 10_000; via env var N)"
	}
}
]]

local script_dir = arg[0] and arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

local N = tonumber(os.getenv("N")) or 10000

print(string.format("Scenario B — deep linear-chain teardown"))
print(string.format("  N = %s hashes deep", h.fmt_int(N)))
print()

local db, path = h.fresh_disk_db("b")
print("DB path:      " .. path)
print("Initial size: " .. h.fmt_bytes(h.file_size(path)))
print()

------------------------------------------------------------
-- Build (setup — not measured)
------------------------------------------------------------

print("Building chain...")

local build_start = h.now()

db:atomic(function()
	local parent = 1

	for i = 1, N do
		local h_pk = db:add_hash()

		if i == 1 then
			db:set_hash_ref(1, "top", h_pk)
		else
			db:set_hash_ref(parent, "next", h_pk)
		end

		parent = h_pk
	end
end)

local build_secs = h.now() - build_start

local pre
for row in db._conn:nrows("select count(*) as c from collections") do
	pre = row.c
end

print(string.format("Built %s collections in %s (%d ops/sec)",
	h.fmt_int(pre),
	h.fmt_secs(build_secs),
	math.floor(N / math.max(build_secs, 0.000001))))
print("After-build size: " .. h.fmt_bytes(h.file_size(path)))
print()

------------------------------------------------------------
-- Preflight — EXPLAIN QUERY PLAN on the drain's hot statements
------------------------------------------------------------

print("Preflight — EXPLAIN QUERY PLAN on drain's hot statements:")
print()
h.explain(db._conn,
	"select collection_pk from collections where needs_trace = 1 limit 1",
	"[seed lookup — uses partial index]")
h.explain(db._conn,
	"select in_trace from collections where collection_pk = 1",
	"[alive check — root primary-key read]")
h.explain(db._conn,
	"delete from collections where in_trace = 1",
	"[dead-set delete — partial index]")
print()

------------------------------------------------------------
-- Teardown (the measurement)
------------------------------------------------------------

print("Tearing down chain via one delete_hash_element(1, 'top')...")

local teardown_start = h.now()
db:delete_hash_element(1, "top")
local teardown_secs = h.now() - teardown_start

------------------------------------------------------------
-- Report
------------------------------------------------------------

print()
print("Teardown time:  " .. h.fmt_secs(teardown_secs))
print("Rate:           " .. h.fmt_int(math.floor(N / math.max(teardown_secs, 0.000001))) .. " collections collected / sec")
print("Per-collection: " .. string.format("%.1f µs", teardown_secs * 1e6 / N))
print("Final DB size:  " .. h.fmt_bytes(h.file_size(path)))
print()

local post
for row in db._conn:nrows("select count(*) as c from collections") do
	post = row.c
end

local rel_count
for row in db._conn:nrows("select count(*) as c from relationships") do
	rel_count = row.c
end

print("Post-run row counts:")
print("  collections:   " .. h.fmt_int(post) .. " (expected: 1)")
print("  relationships: " .. h.fmt_int(rel_count) .. " (expected: 0)")

if post ~= 1 or rel_count ~= 0 then
	print()
	print("WARNING: expected 1 collection (root) and 0 relationships after teardown")
end

h.cleanup_db(path)
