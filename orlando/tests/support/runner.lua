--[[
{
  "module": "tests.support.runner",
  "role": "Minimal test runner — accumulates pass/fail counts and prints a summary",
  "usage": "runner.suite('label'); runner.test('desc', fn); ... runner.report()",
  "state": "module-global; all required test files share one accumulator — do not require from multiple processes"
}
]]
local M = {}

local _pass   = 0
local _fail   = 0
local _errors = {}
local _suite  = ""

--[[ { "in": {"name": "string"}, "note": "sets the label prepended to subsequent test names in failure output; call once per test file" } ]]
function M.suite(name)
    _suite = name
end

--[[ { "in": {"name": "string", "fn": "function"}, "note": "runs fn via pcall; prints '.' on pass or 'F' on fail; failure message stored for report()" } ]]
function M.test(name, fn)
    local full = _suite ~= "" and (_suite .. " / " .. name) or name
    local ok, err = pcall(fn)
    if ok then
        _pass = _pass + 1
        io.write(".")
    else
        _fail   = _fail + 1
        _errors[#_errors + 1] = { name = full, err = tostring(err) }
        io.write("F")
    end
end

--[[ { "out": "bool  (true iff all tests passed)", "note": "prints failure details then the final N/N count; pass return value to os.exit()" } ]]
function M.report()
    io.write("\n")
    if #_errors > 0 then
        print("\nFailures:")
        for _, e in ipairs(_errors) do
            print("  " .. e.name)
            print("  " .. e.err)
            print()
        end
    end
    local total = _pass + _fail
    print(string.format("%d / %d passed", _pass, total))
    return _fail == 0
end

return M
