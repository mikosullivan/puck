--[[
{
  "file": "orlando/tests/config/test_config.lua",
  "role": "Unit tests for orlando.config — IP-based gating of edit features. Reads ~/.orlando/config.json; tests just verify the lookup logic against whatever is currently on disk."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local config  = require("orlando.config")

runner.suite("config")

runner.test("load returns a table (even if file missing)", function()
    local c = config.load()
    assert_.equal(type(c), "table")
end)

runner.test("edit_allowed_ips returns a set table", function()
    local set = config.edit_allowed_ips()
    assert_.equal(type(set), "table")
    -- Values should be booleans (true) when present
    for _, v in pairs(set) do
        assert_.equal(v, true)
    end
end)

runner.test("ip_can_edit: nil and empty are false", function()
    assert_.equal(config.ip_can_edit(nil), false)
    assert_.equal(config.ip_can_edit(""),  false)
end)

runner.test("ip_can_edit: obviously bogus IP is false", function()
    assert_.equal(config.ip_can_edit("999.999.999.999"), false)
    assert_.equal(config.ip_can_edit("not-an-ip"),       false)
end)

runner.test("ip_can_edit matches edit_allowed_ips set", function()
    local set = config.edit_allowed_ips()

    for ip in pairs(set) do
        assert_.equal(config.ip_can_edit(ip), true,
            "ip_can_edit must return true for any IP in the allow-list (" .. ip .. ")")
    end
end)
