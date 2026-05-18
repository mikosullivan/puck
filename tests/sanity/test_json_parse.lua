--[[
{
  "file": "tests/sanity/test_json_parse.lua",
  "test_id": "T0.5",
  "verifies": "charlie.json provides a parse function that handles the minimum JSON forms the engine needs to consume CharlieJSON fixtures (objects with string keys, integer numbers).",
  "level": "unit",
  "context": "complements tests/charlie/v001/test_json_parse.lua which asserts on the V0.01 hello-world fixture shape; this test verifies the minimum parse contract"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local json     = require("charlie.json")

runner.suite("sanity / json parse")

runner.test("parse exists as a function", function()
    assert_.equal(type(json.parse), "function",
        "json.parse must be a callable function")
end)

runner.test("parses a simple object {\"a\": 1}", function()
    local parsed = json.parse('{"a": 1}')
    assert_.not_nil(parsed, "parse must not return nil")
    assert_.equal(parsed.a, 1, "object value preserved")
end)
