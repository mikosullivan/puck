--[[
{
	"module": "helpers",
	"role": "Shared bench helpers. Wires the fiona module (via ../lua/src/) and the per-user luarocks lsqlite3 install, provides disk-backed temp-file DB setup, timing utilities, formatted output, and an EXPLAIN QUERY PLAN printer used by scenarios to verify indexes are being hit.",
	"exports": {
		"fresh_disk_db": "() -> (db, path) — creates a fresh disk-backed Fiona DB in /tmp",
		"cleanup_db":    "path -> nil — removes the DB file and its journal/WAL siblings",
		"now":           "() -> number — CPU seconds via os.clock()",
		"fmt_secs":      "seconds -> string — formatted as N.NNN s",
		"fmt_int":       "integer -> string — thousands-separated",
		"fmt_bytes":     "bytes -> string — KB / MB with 1 decimal",
		"file_size":     "path -> integer — file size in bytes, 0 if missing",
		"explain":       "conn, sql, label? -> nil — prints EXPLAIN QUERY PLAN"
	},
	"backend": "SQLite via lsqlite3"
}
]]

-- Wire the per-user luarocks install so lsqlite3 resolves.
local home = os.getenv("HOME") or "."
package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath
package.path  = home .. "/.luarocks/share/lua/5.4/?.lua;" .. package.path

-- Add src/fiona/ to package.path so bench scenarios can require("fiona").
-- From tests/benchmarks/fiona/ (depth 3), three ups land at repo root,
-- then into src/fiona/.
local script_dir = arg[0] and arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "../../../src/fiona/?.lua;" .. package.path

local fiona = require("fiona")

local H = {}

------------------------------------------------------------
-- Disk-backed temp DB
------------------------------------------------------------

-- Fixed path per scenario so re-runs overwrite instead of littering /tmp.
-- The caller passes a label; keeps concurrent scenarios from stepping on
-- each other if we ever run more than one at a time.
--[[ {"in": {"label": "string — short scenario id, e.g. 'a'"}, "out": "db (Fiona Db), path (string)"} ]]
function H.fresh_disk_db(label)
	local path = "/tmp/fiona-bench-" .. label .. ".db"

	-- Blow away any stale artifacts from a previous run before we open.
	H.cleanup_db(path)

	local db = fiona.get_db(path, "rw")
	return db, path
end

--[[ {"in": {"path": "string"}, "out": "nil"} ]]
function H.cleanup_db(path)
	os.remove(path)
	os.remove(path .. "-journal")
	os.remove(path .. "-wal")
	os.remove(path .. "-shm")
end

------------------------------------------------------------
-- Timing
------------------------------------------------------------

-- Wall-clock time via `date +%s.%N`. Deliberately wall, not CPU: benches
-- that measure autocommit throughput spend most of their time waiting on
-- fsync, which os.clock() doesn't count. One shell fork per call, only
-- invoked at bucket boundaries and totals, so the overhead is negligible.
--[[ {"in": {}, "out": "number — wall-clock seconds since epoch, sub-second resolution"} ]]
function H.now()
	local f = io.popen("date +%s.%N")
	local out = f:read("*a")
	f:close()
	return tonumber(out) or 0
end

------------------------------------------------------------
-- Formatting
------------------------------------------------------------

--[[ {"in": {"secs": "number"}, "out": "string — 'N.NNN s'"} ]]
function H.fmt_secs(secs)
	return string.format("%.3f s", secs)
end

--[[ {"in": {"n": "integer"}, "out": "string — thousands-separated"} ]]
function H.fmt_int(n)
	local s = string.format("%d", n)
	local rev = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	local out = rev:gsub("^,", "")
	return out
end

--[[ {"in": {"bytes": "integer"}, "out": "string — 'N.N KB' or 'N.N MB'"} ]]
function H.fmt_bytes(bytes)
	if bytes >= 1024 * 1024 then
		return string.format("%.1f MB", bytes / (1024 * 1024))
	end

	return string.format("%.1f KB", bytes / 1024)
end

--[[ {"in": {"path": "string"}, "out": "integer — bytes on disk, 0 if missing"} ]]
function H.file_size(path)
	local f = io.open(path, "rb")

	if not f then
		return 0
	end

	local size = f:seek("end")
	f:close()
	return size
end

------------------------------------------------------------
-- EXPLAIN QUERY PLAN — printed to confirm indexes are used
------------------------------------------------------------

--[[ {"in": {"conn": "lsqlite3 db", "sql": "string", "label": "string?"}, "out": "nil — prints the plan"} ]]
function H.explain(conn, sql, label)
	print(string.format("  %s", label or sql))

	for row in conn:nrows("explain query plan " .. sql) do
		print(string.format("      %s", tostring(row.detail)))
	end
end

return H
