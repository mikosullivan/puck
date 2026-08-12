-- Benchmark for object:bucket() to establish a baseline for future
-- optimization work.
--
-- Run from the repo root:
--     lua5.4 ideas/frames-as-objects/benchmarks/bench_bucket.lua
--
-- Two paths measured:
--   * Hot  — same wrapped object, bucket_pk memoized; every call goes
--            straight to object_by_pk.
--   * Cold — fresh wrapped object each call, bucket_pk starts nil;
--            every call triggers add_bucket + object_by_pk.
--
-- Cold-path measurement pre-creates and pre-wraps N target objects
-- OUTSIDE the timed region, so the numbers reflect only :bucket() itself
-- (its INSERT + trigger + SELECT), not the setup.
--
-- Not a test. Not run by tests/main/lua/engine/run.lua.
--
-- Baseline (2026-08-12, before wrapper-cache optimization):
--   Hot  (memoized):  1,000,000 iters in  8.05s →    8.05 µs/call  (   124,199 calls/s)
--   Cold (fresh):        10,000 iters in 19.40s → 1939.57 µs/call  (       515 calls/s)
--
-- Hot-path cost was dominated by rebuilding a fresh object wrapper
-- (engine:object_by_pk → SELECT + object.new + _wrap) on every call
-- even though the bucket row itself never changed.
--
-- After wrapper-cache pass (self._bucket / self._stack memoization):
--   Hot  (memoized):  1,000,000 iters in  0.046s →   0.046 µs/call  (21,802,642 calls/s)  ≈175× faster
--   Cold (fresh):        10,000 iters in 22.853s → 2285.28 µs/call  (       437 calls/s)  ≈unchanged
--
-- After _wrap-row-as-instance + single-scalar engine methods:
--   Hot  (memoized):  1,000,000 iters in  0.044s →   0.044 µs/call  (22,505,795 calls/s)  ≈unchanged
--   Cold (fresh):        10,000 iters in  8.294s → 829.375 µs/call  (     1,205 calls/s)  ≈2.75× faster
--
-- Cold path drops from ≈2.3 ms → ≈0.83 ms per call. The `_wrap` shortcut
-- kills the row-column-copy loop that fired on every uncached wrapper
-- construction; the engine methods' step + get_value(0) skips a
-- per-row table allocation on every INSERT ... RETURNING.
--
-- Hot path now sits at ≈46 ns/call — a metatable method lookup + one
-- instance-field read + a branch + a return. That's within a few
-- multiples of the Lua noise floor for a method call.
--
-- Cold-path cost is INSERT + objects_denormalize_bucket trigger +
-- SELECT round-tripping ≈2 ms/call. That's the SQLite floor for this
-- shape of work, not something object:bucket() can shave without
-- changing the storage model.

package.path  = "/home/miko/.luarocks/share/lua/5.4/?.lua;./ideas/frames-as-objects/src/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite = require("lsqlite3")
local engine = require("engine")

local SCHEMA_PATH = "ideas/frames-as-objects/src/cvm.sql"

local function slurp(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local text = f:read("*a")
	f:close()
	return text
end

local function fresh_db()
	local db = sqlite.open_memory()
	db:exec("pragma foreign_keys = on;")
	db:exec("pragma recursive_triggers = on;")
	local rc = db:exec(slurp(SCHEMA_PATH))
	assert(rc == sqlite.OK, "schema apply failed: " .. tostring(db:errmsg()))
	return db
end

local function user_pk(db)
	for row in db:nrows("select object_pk from objects where user") do
		return row.object_pk
	end
end

local function insert_target(db, user)
	local sql = string.format(
		"insert into objects (primitive, owner_role) values ('o', '%s') returning object_pk",
		user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

-- Hot path: one wrapped object, memoized bucket_pk after the warmup call.
-- Every timed iteration is just: bucket_pk lookup + object_by_pk.
local function bench_hot(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)
	local obj = e:object_by_pk(target)

	-- Prime the memoization so the timed loop is purely the hot path.
	obj:bucket()

	local start = os.clock()

	for _ = 1, iterations do
		obj:bucket()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- Cold path: pre-wrap N fresh targets, then time only the :bucket()
-- calls. Each iteration triggers add_bucket (INSERT + denormalization
-- trigger) + object_by_pk (SELECT).
local function bench_cold(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local objs = {}

	-- Setup is not what we're measuring. Wrap it in a transaction so
	-- pre-creating N targets doesn't drown the timed region under
	-- per-row fsync cost.
	db:exec("begin;")

	for i = 1, iterations do
		local pk = insert_target(db, user)
		objs[i] = e:object_by_pk(pk)
	end

	db:exec("commit;")

	local start = os.clock()

	for i = 1, iterations do
		objs[i]:bucket()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

local HOT_N  = 1000000
local COLD_N = 10000

print("object:bucket() benchmark")
print("-------------------------------------------------")
print(string.format("Lua:    %s", _VERSION))
print(string.format("SQLite: %s", sqlite.version()))
print(string.format("Date:   %s", os.date("%Y-%m-%d %H:%M:%S")))
print(string.format("Host:   %s (see uname -a for details)", os.getenv("HOSTNAME") or "unknown"))
print("-------------------------------------------------")

local hot_elapsed  = bench_hot(HOT_N)
local hot_per_call = (hot_elapsed / HOT_N) * 1e6
print(string.format(
	"Hot  (memoized):  %8d iterations in %6.3fs  →  %7.3f µs/call  (%d calls/s)",
	HOT_N, hot_elapsed, hot_per_call, math.floor(HOT_N / hot_elapsed)
))

local cold_elapsed  = bench_cold(COLD_N)
local cold_per_call = (cold_elapsed / COLD_N) * 1e6
print(string.format(
	"Cold (fresh):     %8d iterations in %6.3fs  →  %7.3f µs/call  (%d calls/s)",
	COLD_N, cold_elapsed, cold_per_call, math.floor(COLD_N / cold_elapsed)
))
