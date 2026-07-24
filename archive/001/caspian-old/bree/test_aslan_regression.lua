--[[
{
  "file":     "tests/caspian/bree/test_aslan_regression.lua",
  "test_id":  "TB.6",
  "verifies": "After the engine API refactor, the Aslan pipeline (io.open + json.parse + stage on engine.caspianj + engine.run()) still returns the same value. Independent regression check at the Bree boundary.",
  "level":    "regression"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")
local json    = require("caspian.json")

runner.suite("bree / TB.6 aslan_regression")

runner.test("aslan pipeline (io.open + json.parse + engine.run) returns payload 'hello'", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.caspj", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = json.parse(source)
    local result    = engine.run()

    assert_.not_nil(result, "engine.run returned nil")
    assert_.equal(result.type,    "puck.uno/string")
    assert_.equal(result.payload, "hello")
end)

runner.test("after aslan-style run, call_stack is back to one top_level frame with role user", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.caspj", "r"))
    local source = f:read("*a")
    f:close()

    engine.caspianj = json.parse(source)
    engine.run()

    local cs = engine.state.call_stack
    assert_.equal(#cs, 1, "expected exactly one frame")
    assert_.equal(cs[1].role.name, "user", "top frame role name")
end)
