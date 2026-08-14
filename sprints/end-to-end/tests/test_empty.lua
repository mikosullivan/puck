--[[
{
	"spec": "test_empty",
	"role": "Sprint end-to-end: instantiate a larry, feed it an empty CaspM array, run it, report what happens. No handler manipulation; the stock chain is in place but never gets consulted because the AST has zero rows to dispatch.",
	"status": "sprint-scoped"
}
]]

--[[
# `test_empty`

Diagnostic script — NOT a pass/fail test. Constructs a Larry, hands it an empty CaspM array (`{}`) directly as `larry.caspm`, calls `larry:run()`, and prints out what happened at every observable seam: the return value from `run()`, the debugger log (attached before the run so we capture every event), and the state of the CVM tables that would record a process reaching completion (`processes`, `frames`).

Run from the repo root:

~~~
lua5.4 sprints/end-to-end/tests/test_empty.lua
~~~

The output is the whole point — this is the "tell me what happens" script Miko asked for, not an assertion suite.
]]

package.path = "./tests/main/lua/engine/?.lua;"
	.. "./src/engine/?.lua;"
	.. "./src/engine/?/init.lua;"
	.. (os.getenv("HOME") or "") .. "/.luarocks/share/lua/5.4/?.lua;"
	.. (os.getenv("HOME") or "") .. "/.luarocks/share/lua/5.4/?/init.lua;"
	.. package.path
package.cpath = (os.getenv("HOME") or "") .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

local cjson = require("cjson")
local Larry = require("larry")

print("=== Instantiate ===")
local larry = Larry.new()
print("larry.cvm         =", tostring(larry.cvm))
print("larry.process_pk  =", tostring(larry.process_pk))
print("larry.caspm       =", tostring(larry.caspm))
print("#larry:handlers() =", #larry:handlers())

print()
print("=== Feed empty CaspM ===")
larry.caspm = {}
print("larry.caspm       =", tostring(larry.caspm), "  (cjson:", cjson.encode(larry.caspm) .. ")")

print()
print("=== Attach debugger ===")
larry.debugger = {}
print("larry.debugger    =", tostring(larry.debugger))

print()
print("=== Run ===")
local ok, err = pcall(function() return larry:run() end)

if ok then
	print("larry:run() returned cleanly")
else
	print("larry:run() RAISED:", tostring(err))
end

print()
print("=== Post-run state ===")
print("larry.caspm       =", tostring(larry.caspm), "  (should be nil after fresh run)")
print("larry.process_pk  =", tostring(larry.process_pk))
print("debugger entries  =", #larry.debugger)

for i, entry in ipairs(larry.debugger) do
	print(string.format("  [%d] %s", i, cjson.encode(entry)))
end

print()
print("=== CVM: processes table ===")
local proc_stmt = larry.cvm:prepare("select * from processes")

for row in proc_stmt:nrows() do
	print("  row:", cjson.encode(row))
end

proc_stmt:reset()

print()
print("=== CVM: frames / objects with role=frame ===")
-- Try both — the schema may have a dedicated `frames` view or the frame-role
-- may live in `objects`. Print whatever comes back; ignore errors from either.
for _, sql in ipairs({
	"select object_pk, role from objects where role = 'frame'",
	"select * from frames",
}) do
	print("  query:", sql)
	local ok_q, err_q = pcall(function()
		local stmt = larry.cvm:prepare(sql)

		for row in stmt:nrows() do
			print("    row:", cjson.encode(row))
		end

		stmt:reset()
	end)

	if not ok_q then
		print("    (query failed:", tostring(err_q) .. ")")
	end
end
