--[[
{
  "file": "orlando/tests/search/test_search.lua",
  "role": "Unit tests for orlando.search — case-insensitive substring search across markdown files, snippet generation, and URL mapping for results."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local search  = require("orlando.search")

runner.suite("search")

local function find_result(results, md_path)
    for _, r in ipairs(results) do
        if r.md_path == md_path then return r end
    end

    return nil
end

runner.test("empty query returns no results", function()
    assert_.count(search.search(""), 0)
end)

runner.test("nil query returns no results", function()
    assert_.count(search.search(nil), 0)
end)

runner.test("README has at least one match for 'Puck'", function()
    local r = find_result(search.search("Puck"), "README.md")
    assert_.not_nil(r, "expected README.md in results")
    assert_.is_true(r.count >= 1)
end)

runner.test("README result URL is /documentation/", function()
    local r = find_result(search.search("Puck"), "README.md")
    assert_.not_nil(r)
    assert_.equal(r.url, "/documentation/")
end)

runner.test("case insensitive: lowercase query matches mixed-case body", function()
    local lower = find_result(search.search("puck"), "README.md")
    local upper = find_result(search.search("PUCK"), "README.md")
    local mixed = find_result(search.search("Puck"), "README.md")
    assert_.not_nil(lower)
    assert_.not_nil(upper)
    assert_.not_nil(mixed)
    assert_.equal(lower.count, mixed.count)
    assert_.equal(upper.count, mixed.count)
end)

runner.test("nonexistent term returns empty list", function()
    assert_.count(search.search("xyzzy_zorzilla_qwerty_blob_42"), 0)
end)

runner.test("results sorted by count descending", function()
    -- 'the' is a very common word; results should be sorted desc.
    local results = search.search("the")
    if #results < 2 then return end

    for i = 2, #results do
        assert_.is_true(results[i - 1].count >= results[i].count,
            "results[" .. (i - 1) .. "].count >= results[" .. i .. "].count")
    end
end)

runner.test("each result has at least one snippet", function()
    local results = search.search("Puck")
    assert_.is_true(#results > 0)

    for _, r in ipairs(results) do
        assert_.is_true(#r.snippets >= 1)
    end
end)

runner.test("snippet contains <mark> around the match", function()
    local r = find_result(search.search("Puck"), "README.md")
    assert_.not_nil(r)
    local snip = r.snippets[1]
    assert_.not_nil(snip)
    assert_.not_nil(snip:find("<mark>", 1, true), "snippet should contain <mark>")
    assert_.not_nil(snip:find("</mark>", 1, true), "snippet should contain </mark>")
end)

runner.test("snippet HTML-escapes ambient angle brackets", function()
    -- Find any file with `<` (e.g. inline HTML or generics) and ensure
    -- the snippet escapes it. We can't pick a known file, so just trust
    -- the escape goes through: search for a common word and check no
    -- raw '<' appears outside of <mark>/</mark>.
    local results = search.search("the")

    for _, r in ipairs(results) do
        for _, snip in ipairs(r.snippets) do
            -- Strip <mark>...</mark> wrappers, then assert no '<' remains.
            local stripped = snip:gsub("<mark>", ""):gsub("</mark>", "")

            if stripped:find("<") then
                error("snippet leaks raw '<': " .. snip)
            end
        end
    end
end)

runner.test("render returns a full HTML page", function()
    local html = search.render("Puck")
    assert_.not_nil(html:find("<!DOCTYPE html>", 1, true))
    assert_.not_nil(html:find("Search results", 1, true) or html:find("matched", 1, true),
        "expected results-page content")
end)

runner.test("render with empty query returns landing page", function()
    local html = search.render("")
    assert_.not_nil(html:find("<!DOCTYPE html>", 1, true))
    assert_.not_nil(html:find("Search", 1, true))
end)

runner.test("handle: parses ?q=foo from the request path", function()
    -- Construct a path with a URL-encoded query and confirm the response
    -- body reflects the decoded query.
    local resp = search.handle("/search?q=Puck")
    assert_.equal(resp.status, "200 OK")
    assert_.not_nil(resp.body:find(">Puck<", 1, true)
                 or resp.body:find('value="Puck"', 1, true))
end)

runner.test("handle: URL-decodes percent escapes", function()
    -- %20 is a space.
    local resp = search.handle("/search?q=hello%20world")
    assert_.equal(resp.status, "200 OK")
    assert_.not_nil(resp.body:find('value="hello world"', 1, true))
end)

runner.test("handle: no query returns 200 with the landing form", function()
    local resp = search.handle("/search")
    assert_.equal(resp.status, "200 OK")
    assert_.not_nil(resp.body:find("Search", 1, true))
end)

-- Tree-scoped search: when a tree prefix is given, only files whose
-- md_path starts with the prefix are considered.
runner.test("tree filter scopes results to the prefix", function()
    -- Use "documentation/requirements/" which should exist and yield
    -- multiple matches for a common word.
    local results = search.search("the", "documentation/requirements/")
    assert_.is_true(#results > 0, "expected some matches under documentation/requirements/")

    for _, r in ipairs(results) do
        assert_.equal(r.md_path:sub(1, #"documentation/requirements/"),
            "documentation/requirements/",
            "result " .. r.md_path .. " outside tree")
    end
end)

runner.test("tree filter with empty string returns full results", function()
    local full    = search.search("Puck")
    local scoped  = search.search("Puck", "")
    assert_.equal(#full, #scoped)
end)

runner.test("tree filter with nil returns full results", function()
    local full    = search.search("Puck")
    local scoped  = search.search("Puck", nil)
    assert_.equal(#full, #scoped)
end)

runner.test("tree filter that matches nothing returns empty list", function()
    assert_.count(search.search("Puck", "no-such-directory/"), 0)
end)

runner.test("handle: parses &tree= parameter", function()
    local resp = search.handle("/search?q=Puck&tree=documentation%2F")
    assert_.equal(resp.status, "200 OK")
    -- The results-page form should reflect the tree via a checked checkbox.
    assert_.not_nil(resp.body:find('name="tree"', 1, true),
        "expected results page to render the tree checkbox")
    assert_.not_nil(resp.body:find('value="documentation/"', 1, true),
        "expected checkbox value to reflect the URL-decoded tree")
end)

runner.test("render: tree checkbox absent when no tree in query", function()
    local html = search.render("Puck")
    -- No tree given → results-page form should not render the checkbox.
    assert_.is_nil(html:find('name="tree"', 1, true))
end)

runner.test("render: tree checkbox present when tree is passed", function()
    local html = search.render("Puck", "documentation/")
    assert_.not_nil(html:find('name="tree"', 1, true))
    assert_.not_nil(html:find('value="documentation/"', 1, true))
end)
