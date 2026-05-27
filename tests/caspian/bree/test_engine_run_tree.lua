--[[
{
  "file":     "tests/caspian/bree/test_engine_run_tree.lua",
  "test_id":  "TB.0.4",
  "verifies": "After the path-to-tree refactor, engine.run(tree) accepts a hand-built CaspianJ Lua table directly and returns the expected value. File reading and JSON parsing are no longer the executor's responsibility.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("bree / TB.0.4 engine_run_tree")

runner.test("engine.run on a hand-built tree returns a value with payload hello", function()
    -- Canonical CaspianJ, hand-built in Lua: [["hello".to_string]]
    local tree = {
        { { value = "hello" }, "to_string" },
    }

    local result = engine.run(tree)
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("engine.run rejects a non-table argument", function()
    assert_.parse_error(function() engine.run("not a tree") end, "engine.run should raise on non-table input")
end)

runner.test("engine.run with an empty tree returns nil", function()
    local result = engine.run({})
    assert_.is_nil(result, "expected nil for empty tree")
end)
