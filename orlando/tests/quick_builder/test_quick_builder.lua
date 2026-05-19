--[[
{
  "file": "orlando/tests/quick_builder/test_quick_builder.lua",
  "role": "Tests for the QuickBuilder HTML/XML builder."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local QB      = require("orlando.quick_builder")

runner.suite("quick_builder")

runner.test("empty non-void element renders as <x></x>", function()
    local doc = QB.new("html")
    assert_.equal(doc:render(), "<html></html>")
end)

runner.test("attribute on root, no children (non-void)", function()
    local doc = QB.new("html"):attr("lang", "en")
    assert_.equal(doc:render(), '<html lang="en"></html>')
end)

runner.test("multiple attributes preserve insertion order", function()
    local doc = QB.new("a")
        :attr("href", "https://example.com")
        :attr("rel", "noopener")
        :attr("target", "_blank")
    assert_.equal(doc:render(),
        '<a href="https://example.com" rel="noopener" target="_blank"></a>')
end)

runner.test("re-setting an attribute updates in place, does not reorder", function()
    local doc = QB.new("a"):attr("a", "1"):attr("b", "2"):attr("a", "3")
    assert_.equal(doc:render(), '<a a="3" b="2"></a>')
end)

runner.test("text content", function()
    local doc = QB.new("p"):text("hello")
    assert_.equal(doc:render(), "<p>hello</p>")
end)

runner.test("text auto-escapes & < >", function()
    local doc = QB.new("p"):text("a & b < c > d")
    assert_.equal(doc:render(), "<p>a &amp; b &lt; c &gt; d</p>")
end)

runner.test("attribute escape: same as text — & < > only, no \" escape", function()
    local doc = QB.new("a"):attr("title", 'q&q <x> y')
    assert_.equal(doc:render(), '<a title="q&amp;q &lt;x&gt; y"></a>')
end)

runner.test("attribute key is case-sensitive (XML semantics — stored as given)", function()
    local doc = QB.new("a"):attr("Title", "first"):attr("title", "second")
    -- Different slots: both attributes appear in insertion order.
    assert_.equal(doc:render(), '<a Title="first" title="second"></a>')
end)

runner.test("nested tag with block", function()
    local doc = QB.new("html")
    doc:tag("head", function(head)
        head:tag("title", function(title)
            title:text("foo")
        end)
    end)
    assert_.equal(doc:render(), "<html><head><title>foo</title></head></html>")
end)

runner.test("HTML5 void elements self-close, non-void use explicit close tag", function()
    local doc = QB.new("p")
    doc:tag("br")
    doc:tag("img", function(img) img:attr("src", "/x.png") end)
    doc:tag("span")  -- non-void: must NOT self-close or browsers misparse
    assert_.equal(doc:render(), '<p><br/><img src="/x.png"/><span></span></p>')
end)

runner.test("empty <label> renders as <label></label> (not self-closing)", function()
    -- The bug that motivated the void-element list: <label/> is parsed
    -- by HTML5 as an unclosed opening tag, swallowing siblings.
    local doc = QB.new("li")
    doc:tag("label", function(l) l:attr("for", "x") end)
    doc:tag("a", function(a) a:attr("href", "#x"); a:text("X") end)
    assert_.equal(doc:render(),
        '<li><label for="x"></label><a href="#x">X</a></li>')
end)

runner.test("tag with text content closes normally", function()
    local doc = QB.new("p"):text("hi")
    assert_.equal(doc:render(), "<p>hi</p>")
end)

runner.test("tag with child tag closes normally", function()
    local doc = QB.new("div"):tag("span")
    assert_.equal(doc:render(), "<div><span></span></div>")
end)

runner.test("ports the Ruby reference example", function()
    local doc = QB.new("html")
    doc:tag("head", function(head)
        head:tag("title", function(title)
            title:text("foo")
        end)
    end)
    doc:tag("body", function(body)
        body:tag("a", function(a)
            a:attr("href", "https://www.bar.com")
            a:text("Bar")
        end)
    end)
    assert_.equal(doc:render(),
        '<html><head><title>foo</title></head><body><a href="https://www.bar.com">Bar</a></body></html>')
end)

runner.test("mixed text and nested tags in order", function()
    local doc = QB.new("p")
    doc:text("Hello, ")
    doc:tag("strong", function(s) s:text("world") end)
    doc:text("!")
    assert_.equal(doc:render(), "<p>Hello, <strong>world</strong>!</p>")
end)

runner.test("tag() without function still works", function()
    local doc = QB.new("ul")
    doc:tag("li")  -- empty li, no block
    doc:tag("li", function(li) li:text("x") end)
    assert_.equal(doc:render(), "<ul><li></li><li>x</li></ul>")
end)

runner.test("raw() inserts pre-rendered HTML verbatim", function()
    local doc = QB.new("main")
    doc:raw("<p>already <em>html</em></p>")
    assert_.equal(doc:render(), "<main><p>already <em>html</em></p></main>")
end)

runner.test("raw() does not escape & < >", function()
    local doc = QB.new("div")
    doc:raw("a < b && c > d")
    assert_.equal(doc:render(), "<div>a < b && c > d</div>")
end)

runner.test("raw() composes with text and nested tags", function()
    local doc = QB.new("section")
    doc:tag("h1", function(h) h:text("Title") end)
    doc:raw("<p>body from elsewhere</p>")
    doc:text("after")
    assert_.equal(doc:render(),
        "<section><h1>Title</h1><p>body from elsewhere</p>after</section>")
end)

runner.test("raw() makes its parent non-empty (no self-close)", function()
    local doc = QB.new("div")
    doc:raw("")
    assert_.equal(doc:render(), "<div></div>")
end)
