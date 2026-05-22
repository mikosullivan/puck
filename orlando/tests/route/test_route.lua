--[[
{
  "file": "orlando/tests/route/test_route.lua",
  "role": "Unit tests for orlando.route — URL-to-source-file resolution under the /documentation/ prefix."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local route   = require("orlando.route")

runner.suite("route")

-- These tests assume the project's actual file layout: README.md at root,
-- documentation/ with .md files, orlando/static/index.html present.

runner.test("site root /: serves the hand-edited index.html", function()
    local r = route.resolve("/")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "orlando/static/index.html")
end)

runner.test("site root /index: serves index.html", function()
    local r = route.resolve("/index")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "orlando/static/index.html")
end)

runner.test("site root /index.html: serves index.html", function()
    local r = route.resolve("/index.html")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "orlando/static/index.html")
end)

runner.test("doc root: /documentation/ serves README.md", function()
    local r = route.resolve("/documentation/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "README.md")
end)

runner.test("doc root: /documentation (no slash) 301s to /documentation/", function()
    local r = route.resolve("/documentation")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/documentation/")
end)

runner.test("markdown: /documentation/overview resolves to documentation/overview.md", function()
    local r = route.resolve("/documentation/overview")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)

runner.test("markdown: .html suffix is stripped", function()
    local r = route.resolve("/documentation/overview.html")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)

runner.test("redirect: /documentation/charlie/charlie collapses to /documentation/charlie/", function()
    local r = route.resolve("/documentation/charlie/charlie")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/documentation/charlie/")
end)

runner.test("redirect: .html variant also collapses", function()
    local r = route.resolve("/documentation/charlie/charlie.html")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/documentation/charlie/")
end)

runner.test("dir_index: /documentation/charlie/ serves documentation/charlie/charlie.md", function()
    local r = route.resolve("/documentation/charlie/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/charlie.md")
end)

runner.test("dir_index: /documentation/charlie (no slash) 301s to /documentation/charlie/", function()
    local r = route.resolve("/documentation/charlie")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/documentation/charlie/")
end)

runner.test("dir_index: /documentation/charlie/utils 301s to /documentation/charlie/utils/", function()
    local r = route.resolve("/documentation/charlie/utils")
    assert_.equal(r.kind, "redirect")
    assert_.equal(r.location, "/documentation/charlie/utils/")
end)

runner.test("dir_index: /documentation/charlie/utils/ serves utils.md", function()
    local r = route.resolve("/documentation/charlie/utils/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/utils/utils.md")
end)

runner.test("dir_index: deeply nested /documentation/charlie/packages/jasmine/ serves jasmine.md", function()
    local r = route.resolve("/documentation/charlie/packages/jasmine/")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/charlie/packages/jasmine/jasmine.md")
end)

runner.test("dir_index: directory without same-named index is 404", function()
    -- /documentation/charlie/examples/ has no examples.md (it only holds
    -- .charlie files served as static assets).
    local r = route.resolve("/documentation/charlie/examples/")
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

runner.test("legacy: /overview (no /documentation/ prefix) is 404", function()
    -- Old URL scheme is not auto-redirected; everything lives under /documentation/.
    local r = route.resolve("/overview")
    assert_.equal(r.kind, "not_found")
end)

runner.test("static: a JSON in documentation/ resolves under /documentation/", function()
    local r = route.resolve("/documentation/mikobase/AI2AI/ai2ai.json")
    assert_.equal(r.kind, "static")
    assert_.equal(r.path, "documentation/mikobase/AI2AI/ai2ai.json")
end)

runner.test("static: a worldlet JSON resolves", function()
    local r = route.resolve("/documentation/mikobase/AI2AI/examples/division-by-zero-impasse.json")
    assert_.equal(r.kind, "static")
end)

runner.test("not_found: nonexistent path returns not_found", function()
    local r = route.resolve("/documentation/this/does/not/exist.svg")
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
    local r = route.resolve("/documentation/overview?foo=bar&baz=1")
    assert_.equal(r.kind, "markdown")
    assert_.equal(r.path, "documentation/overview.md")
end)
