--[[
{
  "file": "orlando/tests/route/test_route.lua",
  "role": "Unit tests for orlando.route — URL-to-source-file resolution."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local route   = require("orlando.route")

runner.suite("route")

-- These tests assume the project's actual file layout: README.md at root,
-- documentation/ with .md files, graphics/logo.svg present.

runner.test("home: empty path resolves to README.md", function()
    local r = route.resolve("/")
    assert_.equal(r.kind, "home")
    assert_.equal(r.path, "README.md")
end)

runner.test("home: bare /index resolves to README.md", function()
    local r = route.resolve("/index")
    assert_.equal(r.kind, "home")
end)

runner.test("home: /index.html resolves to README.md", function()
    local r = route.resolve("/index.html")
    assert_.equal(r.kind, "home")
end)

runner.test("markdown: /overview resolves to documentation/overview.md", function()
    local r = route.resolve("/overview")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)

runner.test("markdown: /overview.html resolves to documentation/overview.md", function()
    local r = route.resolve("/overview.html")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)

runner.test("redirect: /charlie/charlie collapses to /charlie/", function()
    local r = route.resolve("/charlie/charlie")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/charlie/")
end)

runner.test("redirect: /charlie/charlie.html also collapses to /charlie/", function()
    local r = route.resolve("/charlie/charlie.html")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/charlie/")
end)

runner.test("dir_index: /charlie/ serves documentation/charlie/charlie.md", function()
    local r = route.resolve("/charlie/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/charlie.md")
end)

runner.test("dir_index: /charlie (no trailing slash) also serves the index", function()
    local r = route.resolve("/charlie")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/charlie.md")
end)

runner.test("dir_index: deeply nested /charlie/jasmine/ serves jasmine.md", function()
    local r = route.resolve("/charlie/jasmine/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/jasmine/jasmine.md")
end)

runner.test("dir_index: directory without same-named index is 404", function()
    -- /charlie/built-in-classes/ has no built-in-classes.md inside it.
    local r = route.resolve("/charlie/built-in-classes/")
    assert_.equal(r.kind, "not_found")
end)

runner.test("static: /static/* resolves under orlando/static/", function()
    local r = route.resolve("/static/README.md")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "orlando/static/README.md")
end)

runner.test("static: /client-assets/* resolves under orlando/client-assets/", function()
    local r = route.resolve("/client-assets/style.css")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "orlando/client-assets/style.css")
end)

runner.test("static: /graphics/* no longer mounted", function()
    -- We used to special-case /graphics/ as a mount; that's gone. Now the
    -- request falls through to documentation/, where graphics/ does not
    -- live, so the result is not_found.
    local r = route.resolve("/graphics/logo.svg")
    assert_.equal(r.kind, "not_found")
end)

runner.test("static: a JSON in documentation/ resolves under it", function()
    local r = route.resolve("/mikobase/AI2AI/ai2ai.json")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "documentation/mikobase/AI2AI/ai2ai.json")
end)

runner.test("static: a worldlet JSON in documentation/ resolves", function()
    local r = route.resolve("/mikobase/worldlets/division-by-zero-impasse.json")
    assert_.equal(r.kind, "static")
end)

runner.test("not_found: nonexistent path returns not_found", function()
    local r = route.resolve("/this/does/not/exist.svg")
    assert_.equal(r.kind, "not_found")
end)

runner.test("unsafe: path with .. is rejected", function()
    local r = route.resolve("/../README.md")
    assert_.equal(r.kind, "not_found")
end)

runner.test("unsafe: nested .. inside path is rejected", function()
    local r = route.resolve("/foo/../../etc/passwd")
    assert_.equal(r.kind, "not_found")
end)

runner.test("query string is stripped before lookup", function()
    local r = route.resolve("/overview?foo=bar&baz=1")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)
