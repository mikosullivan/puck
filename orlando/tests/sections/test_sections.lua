--[[
{
  "file": "orlando/tests/sections/test_sections.lua",
  "role": "Unit tests for orlando.sections — extracting section-level markdown from a doc file by anchor (used by the per-section Edit form to pre-populate its textarea)."
}
]]
local runner   = require("support.runner")
local assert_  = require("support.assert")
local sections = require("orlando.sections")

runner.suite("sections")

-- Build a temp file and run sections.extract against it. The test
-- writes content via io.open so we don't depend on any specific
-- project fixture path.
local function with_tmp(content, fn)
    local path = os.tmpname() .. ".md"
    local f = io.open(path, "wb")
    assert_.not_nil(f, "could not open tmp file " .. path)
    f:write(content)
    f:close()

    local ok, err = pcall(fn, path)
    os.remove(path)

    if not ok then error(err, 0) end
end

runner.test("extract: empty file gives empty by_anchor", function()
    with_tmp("", function(p)
        local s = sections.extract(p)
        assert_.equal(s.whole_file, "")
        local n = 0
        for _ in pairs(s.by_anchor) do n = n + 1 end
        assert_.equal(n, 0)
    end)
end)

runner.test("extract: single H2 captures heading + body", function()
    local md = "# Title\n\n## Foo\n\nline 1\nline 2\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        local foo = s.by_anchor["foo"]
        assert_.not_nil(foo)
        assert_.not_nil(foo:find("## Foo", 1, true))
        assert_.not_nil(foo:find("line 1", 1, true))
        assert_.not_nil(foo:find("line 2", 1, true))
    end)
end)

runner.test("extract: section ends at next same-level heading", function()
    local md = "# T\n\n## Foo\n\nfoo body\n\n## Bar\n\nbar body\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        local foo = s.by_anchor["foo"]
        assert_.not_nil(foo)
        assert_.not_nil(foo:find("foo body", 1, true))
        assert_.is_nil(foo:find("bar body", 1, true)
            and (function() return true end)())  -- foo must NOT include bar's body
    end)
end)

runner.test("extract: section includes nested subsections", function()
    local md = "# T\n\n## Foo\n\nfoo body\n\n### Foo Sub\n\nsub body\n\n## Bar\n\nbar body\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        local foo = s.by_anchor["foo"]
        assert_.not_nil(foo)
        assert_.not_nil(foo:find("foo body",  1, true))
        assert_.not_nil(foo:find("### Foo Sub", 1, true))
        assert_.not_nil(foo:find("sub body",  1, true))
        assert_.is_nil((foo:find("bar body", 1, true)))
    end)
end)

runner.test("extract: explicit <a id=...> anchor wins over slug", function()
    local md = '# T\n\n<a id="custom-anchor"></a>\n## Some Heading\n\nbody\n'
    with_tmp(md, function(p)
        local s = sections.extract(p)
        assert_.not_nil(s.by_anchor["custom-anchor"])
        -- Should NOT also be at the slug "some-heading"
        assert_.is_nil(s.by_anchor["some-heading"])
    end)
end)

runner.test("extract: duplicate slugs get -2 / -3 suffix", function()
    local md = "# T\n\n## Foo\n\nA\n\n## Foo\n\nB\n\n## Foo\n\nC\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        assert_.not_nil(s.by_anchor["foo"])
        assert_.not_nil(s.by_anchor["foo-2"])
        assert_.not_nil(s.by_anchor["foo-3"])
        assert_.not_nil(s.by_anchor["foo"]:find("\nA",   1, true))
        assert_.not_nil(s.by_anchor["foo-2"]:find("\nB", 1, true))
        assert_.not_nil(s.by_anchor["foo-3"]:find("\nC", 1, true))
    end)
end)

runner.test("extract: # inside fenced code block is not a heading", function()
    local md = "# T\n\n## Foo\n\n```python\n# this is a comment, not a heading\n```\n\n## Bar\n\nbar body\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        -- Should still see exactly: T (h1), Foo (h2), Bar (h2)
        local n = 0
        for _ in pairs(s.by_anchor) do n = n + 1 end
        assert_.equal(n, 3)
        assert_.not_nil(s.by_anchor["foo"])
        assert_.not_nil(s.by_anchor["bar"])
        assert_.not_nil(s.by_anchor["foo"]:find("# this is a comment", 1, true))
    end)
end)

runner.test("extract: ~~~ fence is also recognized", function()
    local md = "# T\n\n## Foo\n\n~~~caspian\n# inside caspian fence\n~~~\n\n## Bar\n\nbar body\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        local n = 0
        for _ in pairs(s.by_anchor) do n = n + 1 end
        assert_.equal(n, 3)
        assert_.not_nil(s.by_anchor["foo"]:find("# inside caspian fence", 1, true))
    end)
end)

runner.test("extract: H3 inside H2 doesn't terminate the H2", function()
    local md = "# T\n\n## Foo\n\nfoo body\n\n### Inner\n\ninner body\n\n## Bar\n\nbar body\n"
    with_tmp(md, function(p)
        local s = sections.extract(p)
        local foo = s.by_anchor["foo"]
        assert_.not_nil(foo:find("### Inner", 1, true))
        assert_.not_nil(foo:find("inner body", 1, true))
        assert_.is_nil((foo:find("bar body", 1, true)))
    end)
end)

runner.test("section_for: nil anchor returns whole_file", function()
    with_tmp("# T\n\n## Foo\n\nbody\n", function(p)
        local body = sections.section_for(p, nil)
        assert_.not_nil(body)
        assert_.not_nil(body:find("# T",   1, true))
        assert_.not_nil(body:find("## Foo", 1, true))
    end)
end)

runner.test("section_for: empty anchor returns whole_file", function()
    with_tmp("# T\n\n## Foo\n\nbody\n", function(p)
        local body = sections.section_for(p, "")
        assert_.not_nil(body)
        assert_.not_nil(body:find("# T", 1, true))
    end)
end)

runner.test("section_for: unknown anchor returns nil", function()
    with_tmp("# T\n\n## Foo\n\nbody\n", function(p)
        assert_.is_nil(sections.section_for(p, "no-such-anchor"))
    end)
end)

runner.test("extract: on a real project file (README.md)", function()
    -- Smoke test against a real file. README has at least an H1 and a few sections.
    local s = sections.extract("README.md")
    assert_.is_true(s.whole_file:len() > 0, "README.md whole_file should be non-empty")
end)
