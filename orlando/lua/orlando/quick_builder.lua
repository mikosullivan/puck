--[[
{
  "module": "orlando.quick_builder",
  "role": "Tiny XML-shape builder. Build a document by nesting calls; output is well-formed XML that browsers will also accept as HTML in most cases.",
  "shape": {
    "QuickBuilder.new('root')":       "create a root tag, returns a Tag",
    "tag:tag('name', function(t))":   "add a child tag; call the function with the new child for nesting; returns the parent (self)",
    "tag:text('s')":                  "append a text child; auto-escapes &, <, >; returns self",
    "tag:raw('<i>html</i>')":         "append a pre-rendered HTML/XML string verbatim; CALLER is responsible for safety/escaping; returns self",
    "tag:attr('name', 'value')":      "set an attribute; auto-escapes; preserves insertion order; returns self",
    "tag:render()":                   "serialize the whole tree as a string"
  },
  "empty_tags": "any tag with no children renders self-closing as <x/>. This is XML semantics, not HTML — HTML5 ignores the slash on non-void elements, which can make <label/> parse as an unclosed <label>. To force an explicit close for such elements, give the tag a child (e.g. tag:text('')). Keeping QuickBuilder ignorant of HTML's void-element list is deliberate; that knowledge belongs in the consumer.",
  "escaping": "text escapes & < >; attribute values escape & < > (don't put a literal \" in an attribute value); safe by construction",
  "no_prettification": "output is exactly what was built; no indentation or newlines added"
}
]]
local M = {}

-- The same escape applies to text content and attribute values: just
-- &, <, > in that order. Don't reorder — `&` must be substituted first
-- or the later `<`/`>` substitutions would re-escape the `&` they
-- introduce.
local function escape(s)
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

local Tag = {}
Tag.__index = Tag

function Tag.new(name)
    return setmetatable({
        name       = name,
        attrs      = {},   -- name -> value
        attr_order = {},   -- ordered list of attribute names (preserve insertion order)
        children   = {},   -- list of Tag (child element) or string (text content)
    }, Tag)
end

--[[ { "in": {"name": "string", "fn": "function(child)?"}, "out": "self (parent)", "note": "creates a child tag; if fn is given, calls fn(child) for nesting" } ]]
function Tag:tag(name, fn)
    local child = Tag.new(name)
    table.insert(self.children, child)
    if fn then fn(child) end
    return self
end

--[[ { "in": {"s": "any"}, "out": "self", "note": "append text content; escaped at render time" } ]]
function Tag:text(s)
    table.insert(self.children, tostring(s))
    return self
end

--[[ { "in": {"s": "string"}, "out": "self", "note": "append a pre-rendered HTML/XML string verbatim; NOT escaped — caller is responsible for safety. Use for composing with output from another renderer (e.g. lunamark)." } ]]
function Tag:raw(s)
    table.insert(self.children, { raw_html = tostring(s) })
    return self
end

--[[ { "in": {"name": "string", "value": "any"}, "out": "self", "note": "set an attribute; key is stored as given (XML is case-sensitive); preserves order on first set; subsequent sets with the same case update in place" } ]]
function Tag:attr(name, value)
    if self.attrs[name] == nil then
        table.insert(self.attr_order, name)
    end
    self.attrs[name] = value
    return self
end

local function render_into(tag, parts)
    parts[#parts + 1] = "<"
    parts[#parts + 1] = tag.name
    for _, k in ipairs(tag.attr_order) do
        parts[#parts + 1] = " "
        parts[#parts + 1] = k
        parts[#parts + 1] = '="'
        parts[#parts + 1] = escape(tag.attrs[k])
        parts[#parts + 1] = '"'
    end
    if #tag.children == 0 then
        parts[#parts + 1] = "/>"
        return
    end
    parts[#parts + 1] = ">"
    for _, c in ipairs(tag.children) do
        if type(c) == "string" then
            parts[#parts + 1] = escape(c)
        elseif c.raw_html then
            parts[#parts + 1] = c.raw_html
        else
            render_into(c, parts)
        end
    end
    parts[#parts + 1] = "</"
    parts[#parts + 1] = tag.name
    parts[#parts + 1] = ">"
end

--[[ { "out": "string", "note": "serialize the whole tree; compact, single-line output (pretty-print is a separate concern)" } ]]
function Tag:render()
    local parts = {}
    render_into(self, parts)
    return table.concat(parts)
end

function M.new(root_name)
    return Tag.new(root_name)
end

return M
