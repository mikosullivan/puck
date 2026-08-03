--[[
{
	"module": "scenario_a",
	"role": "Wide-flat hash stress test. Builds one hash with N inline scalar values via set_hash_scalar, measuring per-bucket throughput. Isolates: (parent, key) unique-index insert cost, the coalesce(max(idx) + 1, 0) scan the max-idx lookup does, per-insert CHECK cost. The per-bucket throughput curve is the point — flat curve means indexes hold; degrading curve means something is scanning.",
	"transaction_model": "Default: one SQLite transaction wraps every BATCH ops (bench measures index/CHECK/trigger cost, not fsync throughput). AUTOCOMMIT=1: skip all wrapping, so each API call autocommits and fsync-per-op governs throughput — the durable-write mode a real user gets without ceremony.",
	"knobs": {
		"N":          "total ops (default 10_000; via env var N)",
		"BUCKET":     "throughput-curve bucket size (default 1_000; via env var BUCKET)",
		"BATCH":      "transaction chunk size (default 2_000; via env var BATCH; ignored when AUTOCOMMIT=1)",
		"AUTOCOMMIT": "if set (any non-empty value), skip the transaction wrapping; each op autocommits"
	}
}
]]

local script_dir = arg[0] and arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

local N = tonumber(os.getenv("N")) or 10000
local BUCKET = tonumber(os.getenv("BUCKET")) or 1000
local BATCH = tonumber(os.getenv("BATCH")) or 2000
local AUTOCOMMIT = os.getenv("AUTOCOMMIT") ~= nil and os.getenv("AUTOCOMMIT") ~= ""

print(string.format("Scenario A — wide-flat hash of inline scalars"))
print(string.format("  N      = %s ops", h.fmt_int(N)))
print(string.format("  bucket = %s ops", h.fmt_int(BUCKET)))

if AUTOCOMMIT then
	print("  mode   = AUTOCOMMIT (per-op fsync)")
else
	print(string.format("  batch  = %s ops (per transaction)", h.fmt_int(BATCH)))
end

print()

local db, path = h.fresh_disk_db("a")
print("DB path:      " .. path)
print("Initial size: " .. h.fmt_bytes(h.file_size(path)))
print()

-- Parent hash lives outside the timing loop — it's setup, not workload.
local parent = db:add_hash()

------------------------------------------------------------
-- Preflight — EXPLAIN QUERY PLAN on the three hot statements
-- set_hash_scalar runs per op. If any of these SCAN, throughput
-- will degrade with N and we want to see it in the plan first.
------------------------------------------------------------

print("Preflight — EXPLAIN QUERY PLAN on set_hash_scalar's hot statements:")
print()
h.explain(db._conn,
	"select child, st, scalar from relationships where parent = 1 and key = 'foo'",
	"[existing-row lookup]")
h.explain(db._conn,
	"select coalesce(max(idx) + 1, 0) from relationships where parent = 1",
	"[max-idx lookup]")
h.explain(db._conn,
	"insert into relationships (parent, key, idx, st, scalar) values (1, 'foo', 0, 'n', 42)",
	"[relationships insert]")
print()

------------------------------------------------------------
-- Bench loop — per-bucket throughput curve
------------------------------------------------------------

print(string.format("%-14s %-14s %-14s %-14s",
	"ops", "bucket_time", "cum_time", "bucket_rate"))
print(string.rep("-", 60))

if not AUTOCOMMIT then
	db._conn:exec("begin")
end

local total_start = h.now()
local bucket_start = total_start

for i = 1, N do
	db:set_hash_scalar(parent, "k_" .. i, i)

	if not AUTOCOMMIT and i % BATCH == 0 then
		db._conn:exec("commit")
		db._conn:exec("begin")
	end

	if i % BUCKET == 0 then
		local bucket_end = h.now()
		local bucket_secs = bucket_end - bucket_start
		local cum_secs = bucket_end - total_start
		local rate = math.floor(BUCKET / math.max(bucket_secs, 0.000001))

		print(string.format("%-14s %-14s %-14s %-14s",
			h.fmt_int(i),
			h.fmt_secs(bucket_secs),
			h.fmt_secs(cum_secs),
			h.fmt_int(rate) .. " ops/s"))

		bucket_start = h.now()
	end
end

if not AUTOCOMMIT then
	db._conn:exec("commit")
end

local total_end = h.now()
local total_secs = total_end - total_start

------------------------------------------------------------
-- Report
------------------------------------------------------------

print(string.rep("-", 60))
print()
print("Total time:     " .. h.fmt_secs(total_secs))
print("Overall rate:   " .. h.fmt_int(math.floor(N / math.max(total_secs, 0.000001))) .. " ops/sec")
print("Final DB size:  " .. h.fmt_bytes(h.file_size(path)))
print()

local rel_count
for row in db._conn:nrows("select count(*) as c from relationships") do
	rel_count = row.c
end

local coll_count
for row in db._conn:nrows("select count(*) as c from collections") do
	coll_count = row.c
end

print("Post-run row counts:")
print("  relationships: " .. h.fmt_int(rel_count))
print("  collections:   " .. h.fmt_int(coll_count))
print()

if rel_count ~= N then
	print(string.format("WARNING: expected %s relationships, got %s",
		h.fmt_int(N), h.fmt_int(rel_count)))
end

-- Root + parent hash = 2 collection rows (scalars now inline in relationships).
if coll_count ~= 2 then
	print(string.format("WARNING: expected 2 collections (root + parent), got %s",
		h.fmt_int(coll_count)))
end

h.cleanup_db(path)
