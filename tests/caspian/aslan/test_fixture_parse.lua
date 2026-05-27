--[[
{
  "file":     "tests/caspian/aslan/test_fixture_parse.lua",
  "test_id":  "TA.1",
  "verifies": "caspian.json.parse handles the Aslan fixture and produces the expected nested table shape.",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local json    = require("caspian.json")

runner.suite("aslan / fixture parse")

runner.test("parses the hello_world fixture into the expected shape", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.caspj", "r"))
    local source = f:read("*a")
    f:close()

    local parsed = json.parse(source)
    assert_.not_nil(parsed, "json.parse returned nil")
    assert_.equal(type(parsed), "table")

    -- Outer array: one statement.
    assert_.equal(#parsed, 1, "expected exactly one top-level statement")
    -- The statement: [receiver, method].
    assert_.equal(type(parsed[1]), "table")
    assert_.equal(#parsed[1], 2, "expected statement of shape [receiver, method]")
    -- Receiver is {value: "hello"}.
    assert_.equal(parsed[1][1].value, "hello")
    -- Method name is "to_string".
    assert_.equal(parsed[1][2], "to_string")
end)
