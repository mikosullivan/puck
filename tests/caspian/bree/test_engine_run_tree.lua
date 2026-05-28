--[[
{
  "file":     "tests/caspian/bree/test_engine_run_tree.lua",
  "test_id":  "TB.0.4",
  "verifies": "engine.run() accepts a hand-built CaspianJ Lua table staged on engine.caspianj and returns the expected value. File reading and JSON parsing are not the executor's responsibility; nor is the tree a per-call argument.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("bree / TB.0.4 engine_run_tree")

runner.test("engine.run on a hand-built tree (via engine.caspianj) returns a value with payload hello", function()
    engine.caspianj = {
        { { value = "hello" }, "to_string" },
    }

    local result = engine.run()
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("engine.run rejects a non-table engine.caspianj", function()
    engine.caspianj = "not a tree"
    assert_.parse_error(function() engine.run() end, "engine.run should raise on non-table engine.caspianj")
end)

runner.test("engine.run with an empty tree returns nil", function()
    engine.caspianj = {}
    local result = engine.run()
    assert_.is_nil(result, "expected nil for empty tree")
end)
