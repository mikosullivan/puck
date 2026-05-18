--[[
{
  "file": "tests/charlie/v001/test_json_parse.lua",
  "test_id": "T1.1",
  "verifies": "json.parse handles the V0.01 CharlieJSON fixture structure (nested arrays containing an object with a string-keyed string value, and a bare string method name)",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local json     = require("charlie.json")

runner.suite("v0.01 / json parse")

runner.test("parses the canonical hello-world fixture", function()
    local tree = json.parse('[[{"value": "hello"}, "to_string"]]')
    assert_.equal(type(tree), "table",        "top is a table")
    assert_.count(tree, 1,                    "top has one statement")

    local stmt = tree[1]
    assert_.equal(type(stmt), "table",        "statement is a table")
    assert_.count(stmt, 2,                    "statement has receiver + method")

    local recv = stmt[1]
    assert_.equal(type(recv), "table",        "receiver is a table")
    assert_.equal(recv.value, "hello",        "receiver.value == 'hello'")

    assert_.equal(stmt[2], "to_string",       "method name == 'to_string'")
end)
