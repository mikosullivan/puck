--[[
{
  "file": "orlando/tests/json_highlight/test_json_highlight.lua",
  "role": "Tests for the JSON syntax highlighter."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local H       = require("orlando.json_highlight")

runner.suite("json_highlight")

runner.test("object keys get class nt, string values get class s2", function()
    assert_.equal(H.highlight('{"k":"v"}'),
        '<span class="p">{</span><span class="nt">"k"</span><span class="p">:</span><span class="s2">"v"</span><span class="p">}</span>')
end)

runner.test("integers get class mi, floats get class mf", function()
    assert_.equal(H.highlight("42"),  '<span class="mi">42</span>')
    assert_.equal(H.highlight("3.14"),'<span class="mf">3.14</span>')
    assert_.equal(H.highlight("-7"),  '<span class="mi">-7</span>')
    assert_.equal(H.highlight("1e9"), '<span class="mf">1e9</span>')
end)

runner.test("true / false / null get class kc", function()
    assert_.equal(H.highlight("true"),  '<span class="kc">true</span>')
    assert_.equal(H.highlight("false"), '<span class="kc">false</span>')
    assert_.equal(H.highlight("null"),  '<span class="kc">null</span>')
end)

runner.test("whitespace passes through as plain text", function()
    assert_.equal(H.highlight(" "),    " ")
    assert_.equal(H.highlight("\n\t"), "\n\t")
end)

runner.test("strings containing escaped quotes are scanned as one token", function()
    assert_.equal(H.highlight('"a\\"b"'),
        '<span class="s2">"a\\"b"</span>')
end)

runner.test("HTML metacharacters inside strings are escaped in output", function()
    -- String value "<x>" should appear inside a span with &lt; and &gt;.
    assert_.equal(H.highlight('"<x>"'),
        '<span class="s2">"&lt;x&gt;"</span>')
end)

runner.test("vibecode-shaped object: key class then nested object", function()
    local out = H.highlight('{"vibecode":{"doc":"x"}}')
    -- Key "vibecode" tagged as nt; value structure preserved.
    assert_.equal(out,
        '<span class="p">{</span><span class="nt">"vibecode"</span><span class="p">:</span>'
        .. '<span class="p">{</span><span class="nt">"doc"</span><span class="p">:</span><span class="s2">"x"</span><span class="p">}</span>'
        .. '<span class="p">}</span>')
end)
