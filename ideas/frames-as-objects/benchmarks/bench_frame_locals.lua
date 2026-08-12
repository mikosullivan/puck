-- Benchmark for frame:locals() and frame:ensure_locals(). Same shape
-- as bench_bucket.lua — hot path (memoized) + cold path (fresh
-- wrapper each iter) for each method.
--
-- Run from the repo root:
--     lua5.4 ideas/frames-as-objects/benchmarks/bench_frame_locals.lua
--
-- Setup: each iteration needs a fresh frame-object (primitive = 'f',
-- ast set to a non-null CaspM literal, owner_role = user). The `ast`
-- column is biconditional with `primitive = 'f'`, so both must be
-- set together. Bulk-created in a transaction OUTSIDE the timed
-- region.
--
-- Not a test. Not run by tests/main/lua/engine/run.lua.
--
-- Baseline (2026-08-12, before frame:locals memoization opt):
--   ensure_locals hot   100,000 iters in 1.143s →  11.433 µs/call  (   87,462 calls/s)
--   ensure_locals cold   10,000 iters in 3.097s → 309.699 µs/call  (    3,228 calls/s)
--   locals hot          100,000 iters in 1.162s →  11.617 µs/call  (   86,078 calls/s)
--
-- After self._locals memoization (shared cache between .locals and .ensure_locals):
--   ensure_locals hot   100,000 iters in 0.005s →   0.052 µs/call  (19,197,542 calls/s)  ≈220× faster
--   ensure_locals cold   10,000 iters in 2.588s → 258.822 µs/call  (    3,863 calls/s)   ≈17% faster
--   locals hot          100,000 iters in 0.005s →   0.052 µs/call  (19,135,093 calls/s)  ≈223× faster
--
-- Hot paths now sit at the same ≈50 ns/call floor as object:bucket()
-- after its wrapper-cache pass — one metatable method lookup + one
-- instance-field read + a branch + a return.

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

-- A frame is an objects row with `primitive = 'f'` (biconditional
-- with a non-null `ast`). Content of ast doesn't matter for this
-- benchmark — object.new routes on `row.primitive`, not on ast
-- content. Detached shape (no process / idx / stmt_idx), which is
-- legal for tests that only exercise the wrapper and its accessors.
local function insert_frame(db, user)
	local sql = string.format(
		"insert into objects (primitive, ast, owner_role) values ('f', '[]', '%s') returning object_pk",
		user
	)

	for row in db:nrows(sql) do
		return row.object_pk
	end
end

local function make_frames(db, user, n)
	local pks = {}

	db:exec("begin;")

	for i = 1, n do
		pks[i] = insert_frame(db, user)
	end

	db:exec("commit;")
	return pks
end

-- ------------------------------------------------------------
-- ensure_locals — cold (fresh frame each iter, first call materializes)
-- ------------------------------------------------------------
local function bench_ensure_locals_cold(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pks = make_frames(db, user, iterations)

	local frames = {}
	for i = 1, iterations do frames[i] = e:object_by_pk(pks[i]) end

	local start = os.clock()

	for i = 1, iterations do
		frames[i]:ensure_locals()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- ensure_locals — hot (same frame, locals already materialized)
-- ------------------------------------------------------------
-- No memoization on frame:ensure_locals yet — every iter still does
-- self:bucket() + get_ref_child + object_by_pk. Bucket() itself is
-- memoized (that's the bench_bucket win); the get_ref_child SELECT
-- and the object_by_pk SELECT+wrap fire every iter.
local function bench_ensure_locals_hot(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pk = insert_frame(db, user)
	local frame = e:object_by_pk(pk)

	-- Prime the locals hash so the timed loop is purely the hot path.
	frame:ensure_locals()

	local start = os.clock()

	for _ = 1, iterations do
		frame:ensure_locals()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- locals — hot (locals already exist, read-only path)
-- ------------------------------------------------------------
local function bench_locals_hot(iterations)
	local db = fresh_db()
	local e = engine.new(db)
	local user = user_pk(db)
	local pk = insert_frame(db, user)
	local frame = e:object_by_pk(pk)

	-- Materialize the locals hash so :locals() returns it, not nil.
	frame:ensure_locals()

	local start = os.clock()

	for _ = 1, iterations do
		frame:locals()
	end

	local elapsed = os.clock() - start
	db:close()
	return elapsed
end

-- ------------------------------------------------------------
-- Driver
-- ------------------------------------------------------------

local BENCHES = {
	{name = "ensure_locals hot",  fn = bench_ensure_locals_hot,  n = 100000},
	{name = "ensure_locals cold", fn = bench_ensure_locals_cold, n = 10000},
	{name = "locals hot",         fn = bench_locals_hot,         n = 100000},
}

print("frame:locals / frame:ensure_locals benchmark")
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
		"%-22s  %8d iters in %7.3fs  →  %9.3f µs/call  (%d calls/s)",
		b.name, b.n, elapsed, per_call, math.floor(b.n / elapsed)
	))
end
