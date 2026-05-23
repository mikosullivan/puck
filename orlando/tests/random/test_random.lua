--[[
{
  "file": "orlando/tests/random/test_random.lua",
  "role": "Unit tests for orlando.random — random markdown-page picker and 302 redirect handler."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local random  = require("orlando.random")
local search  = require("orlando.search")

runner.suite("random")

local function as_set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

runner.test("pick returns a string that exists in the md file list", function()
    local picked = random.pick()
    assert_.not_nil(picked)
    local valid = as_set(search.list_md_files())
    assert_.is_true(valid[picked] == true,
        "pick returned a path not in the file list: " .. tostring(picked))
end)

runner.test("pick produces at least two distinct values over 50 calls", function()
    -- With hundreds of files in the tree, 50 consecutive identical picks
    -- is astronomically unlikely. Failure here means math.random is stuck.
    math.randomseed(12345)
    local seen = {}

    for _ = 1, 50 do
        seen[random.pick()] = true
    end

    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    assert_.is_true(n >= 2, "expected >= 2 distinct picks, got " .. n)
end)

runner.test("handle returns 302 with Location header", function()
    local resp = random.handle("/random")
    assert_.equal(resp.status, "302 Found")
    assert_.not_nil(resp.headers)
    local found_location = false

    for _, h in ipairs(resp.headers) do
        if h:sub(1, 10):lower() == "location: " then
            found_location = true
        end
    end

    assert_.is_true(found_location, "expected a Location header")
end)

runner.test("handle's Location header points under / (canonical Orlando URL)", function()
    local resp = random.handle("/random")
    local location

    for _, h in ipairs(resp.headers) do
        local v = h:match("^[Ll]ocation: (.+)$")
        if v then location = v end
    end

    assert_.not_nil(location)
    assert_.equal(location:sub(1, 1), "/",
        "expected Location to start with /, got: " .. tostring(location))
end)

runner.test("handle includes Cache-Control: no-store so refresh re-rolls", function()
    local resp = random.handle("/random")
    local found = false

    for _, h in ipairs(resp.headers) do
        if h:lower():find("cache-control: no-store", 1, true) then
            found = true
        end
    end

    assert_.is_true(found, "expected Cache-Control: no-store header")
end)
