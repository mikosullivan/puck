-- Benchmark for engine methods, one section per method. Establishes
-- baselines before the next round of optimization work:
--
--   * object_by_pk  — SELECT + row wrap; every iter builds a fresh wrapper.
--                     This is the perf ceiling for uncached bucket / stack /
--                     locals lookups, and covers `_wrap`'s per-column loop.
--   * add_bucket    — INSERT + denormalize trigger + RETURNING; fresh target per iter.
--   * add_stack     — INSERT + denormalize trigger + RETURNING; fresh target per iter.
--   * add_scalar    — INSERT + RETURNING; owner_role = user each time.
--   * add_hash      — INSERT + RETURNING; owner_role = user each time.
--   * add_array     — INSERT + RETURNING; owner_role = user each time.
--   * add_ref       — INSERT + coalesce(max(idx)+1) + RETURNING; fresh key per iter
--                     to avoid the unique(parent, key) collision.
--   * get_ref_child — SELECT via the unique(parent, key) index.
--
-- Run from the repo root:
--     lua5.4 benchmarks/bench_engine.lua
--
-- Setup (creating targets / seeding refs) happens OUTSIDE the timed
-- region and is wrapped in a transaction so setup fsync cost doesn't
-- drown the measurement.
--
-- Not a test. Not run by tests/main/lua/engine/run.lua.
--
-- Baseline (2026-08-12, before _wrap + single-scalar engine-method opts):
--   object_by_pk     100,000 iters in  0.721s →   7.208 µs/call  (138,740 calls/s)
--   add_bucket        10,000 iters in 33.362s → 3336.19 µs/call  (    299 calls/s)
--   add_stack         10,000 iters in 96.366s → 9636.57 µs/call  (    103 calls/s)
--   add_scalar        10,000 iters in  0.724s →  72.404 µs/call  ( 13,811 calls/s)
--   add_hash          10,000 iters in  0.625s →  62.463 µs/call  ( 16,009 calls/s)
--   add_array         10,000 iters in  0.576s →  57.629 µs/call  ( 17,352 calls/s)
--   add_ref           10,000 iters in  0.307s →  30.690 µs/call  ( 32,583 calls/s)
--   get_ref_child    100,000 iters in  0.567s →   5.666 µs/call  (176,480 calls/s)
--
-- After _wrap-row-as-instance (object.lua) + single-scalar step/get_value:
--   object_by_pk     100,000 iters in  0.631s →   6.306 µs/call  (158,577 calls/s)  ≈14% faster
--   add_bucket        10,000 iters in 20.108s → 2010.78 µs/call  (    497 calls/s)  ≈40% faster*
--   add_stack         10,000 iters in 21.997s → 2199.72 µs/call  (    454 calls/s)  ≈4× faster*
--   add_scalar        10,000 iters in  0.622s →  62.163 µs/call  ( 16,086 calls/s)  ≈14% faster
--   add_hash          10,000 iters in  0.451s →  45.086 µs/call  ( 22,179 calls/s)  ≈28% faster
--   add_array         10,000 iters in  0.406s →  40.601 µs/call  ( 24,630 calls/s)  ≈30% faster
--   add_ref           10,000 iters in  0.228s →  22.810 µs/call  ( 43,840 calls/s)  ≈26% faster
--   get_ref_child    100,000 iters in  0.406s →   4.057 µs/call  (246,500 calls/s)  ≈28% faster
--
-- * add_bucket / add_stack baseline numbers were noisy (bucket 3336
--   vs stack 9636 despite identical SQL shape). Second run has them
--   both around 2 ms/call, which is the honest reading. The step/get_value
--   opt is real; the "4× faster" for add_stack is partly measurement
--   normalization on top of the real win.

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

-- Bulk pre-create N target objects inside one transaction, return the
-- pks as an array.
local function make_targets(db, user, n)
	local pks = {}

	db:exec("begin;")

	for i = 1, n do
		pks[i] = insert_target(db, user)
	end

	db:exec("commit;")
	return pks
end

-- ------------------------------------------------------------
-- object_by_pk
-- ------------------------------------------------------------
-- One target, N iterations. Each iter re-runs the SELECT and rebuilds
-- the wrapper via object.new → _wrap. No memoization at this layer.
local function bench_object_by_pk(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pk = insert_target(db, user)

	local start = os.clock()

	for _ = 1, iterations do
		e:object_by_pk(pk)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- add_bucket / add_stack
-- ------------------------------------------------------------
-- One target per iter (each target can only get one bucket / one
-- stack). Pre-create the targets in a transaction; measure only the
-- add_bucket / add_stack calls.
local function bench_add_bucket(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pks = make_targets(db, user, iterations)

	local start = os.clock()

	for i = 1, iterations do
		e:add_bucket(pks[i])
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

local function bench_add_stack(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pks = make_targets(db, user, iterations)

	local start = os.clock()

	for i = 1, iterations do
		e:add_stack(pks[i])
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- add_scalar / add_hash / add_array
-- ------------------------------------------------------------
-- No per-iter setup — same owner_role every call. Straight INSERT.
local function bench_add_scalar(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local start = os.clock()

	for i = 1, iterations do
		e:add_scalar('n', i, user)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

local function bench_add_hash(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local start = os.clock()

	for _ = 1, iterations do
		e:add_hash(user)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

local function bench_add_array(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)

	local start = os.clock()

	for _ = 1, iterations do
		e:add_array(user)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- add_ref
-- ------------------------------------------------------------
-- One shared parent (a hash), one shared child (a scalar), fresh key
-- per iter to avoid the unique(parent, key) collision. The coalesce
-- (select max(idx)+1) subquery scans the (parent, idx) unique index
-- per insert.
local function bench_add_ref(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)
	local child  = e:add_scalar('n', 0, user)

	local start = os.clock()

	for i = 1, iterations do
		e:add_ref(parent, "k" .. i, child)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- get_ref_child
-- ------------------------------------------------------------
-- Pre-seed N refs under one parent, then measure repeated hits on
-- known-present keys. Each iter is a SELECT via the unique index.
local function bench_get_ref_child(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local parent = e:add_hash(user)
	local child  = e:add_scalar('n', 0, user)

	db:exec("begin;")

	for i = 1, iterations do
		e:add_ref(parent, "k" .. i, child)
	end

	db:exec("commit;")

	local start = os.clock()

	for i = 1, iterations do
		e:get_ref_child(parent, "k" .. i)
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- Driver
-- ------------------------------------------------------------

local BENCHES = {
	{name = "object_by_pk",  fn = bench_object_by_pk,  n = 100000},
	{name = "add_bucket",    fn = bench_add_bucket,    n = 10000},
	{name = "add_stack",     fn = bench_add_stack,     n = 10000},
	{name = "add_scalar",    fn = bench_add_scalar,    n = 10000},
	{name = "add_hash",      fn = bench_add_hash,      n = 10000},
	{name = "add_array",     fn = bench_add_array,     n = 10000},
	{name = "add_ref",       fn = bench_add_ref,       n = 10000},
	{name = "get_ref_child", fn = bench_get_ref_child, n = 100000},
}

print("engine methods benchmark")
print("-------------------------------------------------")
print(string.format("Lua:    %s", _VERSION))
print(string.format("SQLite: %s", sqlite.version()))
print(string.format("Date:   %s", os.date("%Y-%m-%d %H:%M:%S")))
print(string.format("Host:   %s (see uname -a for details)", os.getenv("HOSTNAME") or "unknown"))
print("-------------------------------------------------")

for _, b in ipairs(BENCHES) do
	local elapsed  = b.fn(b.n)
	local per_call = (elapsed / b.n) * 1e6
	print(string.format(
		"%-14s  %8d iters in %7.3fs  →  %9.3f µs/call  (%d calls/s)",
		b.name, b.n, elapsed, per_call, math.floor(b.n / elapsed)
	))
end
