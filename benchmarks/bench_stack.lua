-- Benchmark for object:stack() — the array-side parallel to
-- object:bucket(). Same shape, same measurement discipline.
--
-- Run from the repo root:
--     lua5.4 benchmarks/bench_stack.lua
--
-- Two paths measured:
--   * Hot  — same wrapped object, stack_pk memoized; every call goes
--            straight to the cached wrapper.
--   * Cold — fresh wrapped object each call, stack_pk starts nil;
--            every call triggers add_stack + object_by_pk.
--
-- Cold-path measurement pre-creates and pre-wraps N target objects
-- OUTSIDE the timed region, so the numbers reflect only :stack() itself
-- (its INSERT + trigger + SELECT), not the setup.
--
-- Not a test. Not run by tests/main/lua/engine/run.lua.
--
-- object:stack() got the wrapper-cache optimization at the same time
-- as object:bucket() — see bench_bucket.lua's header for the
-- before/after story. The two methods are structurally identical, so
-- this benchmark isn't producing a novel "before" number. It exists to
-- confirm the array-side performance profile matches the hash side.
--
-- After wrapper-cache (baseline for this file):
--   Hot  (memoized):  1,000,000 iters in  0.052s →   0.052 µs/call  (19,091,985 calls/s)
--   Cold (fresh):        10,000 iters in 20.879s → 2087.87 µs/call  (       478 calls/s)
--
-- After _wrap-row-as-instance + single-scalar engine methods:
--   Hot  (memoized):  1,000,000 iters in  0.056s →   0.056 µs/call  (17,720,128 calls/s)  ≈unchanged
--   Cold (fresh):        10,000 iters in  7.632s → 763.213 µs/call  (     1,310 calls/s)  ≈2.7× faster

package.path  = "/home/miko/.luarocks/share/lua/5.4/?.lua;./src/engine/?.lua;" .. package.path
package.cpath = "/home/miko/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local sqlite = require("lsqlite3")
local engine = require("cvm.engine")

local SCHEMA_PATH = "src/engine/cvm/schema.sql"

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

-- Hot path: one wrapped object, memoized wrapper after the warmup call.
-- Every timed iteration is just: field read + return.
local function bench_hot(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local target = insert_target(db, user)
	local obj = e:object_by_pk(target)

	-- Prime the memoization so the timed loop is purely the hot path.
	obj:stack()

	local start = os.clock()

	for _ = 1, iterations do
		obj:stack()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- Cold path: pre-wrap N fresh targets, then time only the :stack()
-- calls. Each iteration triggers add_stack (INSERT + denormalization
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
		objs[i]:stack()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

local HOT_N  = 1000000
local COLD_N = 10000

print("object:stack() benchmark")
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
