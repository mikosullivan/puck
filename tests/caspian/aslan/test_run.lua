--[[
{
  "file":     "tests/caspian/aslan/test_run.lua",
  "test_id":  "TA.7",
  "verifies": "engine.run on a pre-parsed CaspianJ tree (from the hello_world fixture) returns a value whose payload is 'hello'. End-to-end integration test; the caller composes io.open + json.parse + engine.run.",
  "level":    "integration",
  "note":     "Updated in Bree (2026-05-27): engine.run takes a tree, not a path. File reading and JSON parsing moved to the caller."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

local FIXTURE = "tests/caspian/fixtures/hello_world.caspj"

local function load_tree(path)
    local f = assert(io.open(path, "r"))
    local source = f:read("*a")
    f:close()
    return json.parse(source)
end

runner.suite("aslan / engine.run")

runner.test("running the hello_world fixture returns a value with payload hello", function()
    local tree   = load_tree(FIXTURE)
    local result = engine.run(tree)
    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("after engine.run, the call stack is back to one top_level frame", function()
    local tree = load_tree(FIXTURE)
    engine.run(tree)
    assert_.equal(#engine.state.call_stack, 1)
    assert_.equal(engine.state.call_stack[1].action, "top_level")
end)
