--[[
{
  "file": "tests/sanity/test_framework_sanity.lua",
  "test_id": "T0.4",
  "verifies": "the existing test framework (support/runner + support/assert) executes tests, reports pass/fail, and the assertion helpers behave as documented. If the framework is broken, every other test result is meaningless.",
  "level": "unit"
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")

runner.suite("sanity / framework")

runner.test("equal passes for matching values", function()
    assert_.equal(1 + 1, 2)
end)

runner.test("not_equal works for differing values", function()
    assert_.not_nil("anything", "non-nil string")
    assert_.not_equal(1, 2)
end)

runner.test("is_true and is_false distinguish booleans from truthiness", function()
    assert_.is_true(true)
    assert_.is_false(false)
end)

runner.test("parse_error fires when fn raises", function()
    assert_.parse_error(function() error("boom") end,
        "parse_error must catch a raising fn")
end)
