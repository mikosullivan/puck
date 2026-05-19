--[[
{
  "module": "orlando.page",
  "role": "Markdown-to-HTML rendering plus the page-template chrome (stylesheet link, layout shell, sidebar nav, hero logo). Used by orlando.server for per-request HTML generation and by orlando/lua/render.lua for CLI rendering.",
  "exports": {
    "render":         "markdown string -> body HTML string (lunamark with fenced code + pipe tables enabled)",
    "wrap_minimal":   "body HTML + title -> minimal HTML doc (used by CLI render.lua; no chrome)",
    "render_file":    "path + title -> minimal HTML doc; reads, renders, wraps (CLI)",
    "render_request": "ctx { md_path, title, is_home } -> full HTML page with chrome"
  },
  "no_caching": "every call re-reads source and re-runs the pipeline per the Orlando no-caching design"
}
]]
local lunamark       = require("lunamark")
local quick_builder  = require("orlando.quick_builder")
local nav            = require("orlando.nav")
local json_highlight = require("orlando.json_highlight")

local M = {}

local READER_OPTIONS = {
    fenced_code_blocks = true,
    pipe_tables        = true,
}

local LOGO_URL = "/static/logo.svg"

------------------------------------------------------------
-- Step 1: markdown -> HTML body
------------------------------------------------------------

function M.render(md)
    local writer = lunamark.writer.html5.new()
    local parse  = lunamark.reader.markdown.new(writer, READER_OPTIONS)
    return (parse(md))
end

------------------------------------------------------------
-- Step 2: chrome transforms (post-process the body HTML)
------------------------------------------------------------

-- Insert a hero-logo image into the first <h1>, unless the H1 already
-- contains an <img> (the README hardcodes its own). Wraps the image in
-- a link to the home page.
local function inject_hero_logo(body_html)
    local replaced = false
    return (body_html:gsub("<h1>(.-)</h1>", function(inner)
        if replaced then return nil end
        replaced = true
        if inner:find("<img") then
            return nil  -- H1 already has its own image; link wrapping handled separately
        end
        local logo_html = '<a href="/" class="hero-logo-link"><img src="'
                       .. LOGO_URL .. '" alt="" class="hero-logo"></a> '
        return "<h1>" .. logo_html .. inner .. "</h1>"
    end, 1))
end

-- For an H1 whose first child is already an <img> (the README case), wrap
-- the existing image in a link to the home page.
local function link_existing_hero_logo(body_html)
    return (body_html:gsub('(<h1>%s*)(<img[^>]+>)', function(prefix, img_tag)
        return prefix .. '<a href="/" class="hero-logo-link">' .. img_tag .. '</a>'
    end, 1))
end

-- Rewrite internal href and src URLs to the paths Orlando serves:
--   "documentation/foo/bar.md"       -> "/foo/bar"
--   "foo.md"                         -> "foo"
--   "orlando/static/logo.svg"        -> "/static/logo.svg"
--   "orlando/client-assets/style.css"-> "/client-assets/style.css"
--   "../baz.md#frag"                 -> "../baz#frag"
-- External http(s), # anchors, and mailto: are left alone.
local function rewrite_one_url(url)
    if url:match("^https?://") or url:sub(1,1) == "#" or url:sub(1,7) == "mailto:" then
        return url
    end
    local path, frag = url:match("^([^#]+)(#.*)$")
    if not path then path, frag = url, "" end
    path = path:gsub("^orlando/static/",        "/static/")
    path = path:gsub("^orlando/client%-assets/", "/client-assets/")
    path = path:gsub("^documentation/",         "/")
    path = path:gsub("%.md$", "")
    return path .. frag
end

local function rewrite_links(body_html)
    body_html = body_html:gsub('(href=")([^"]+)(")', function(o, u, c)
        return o .. rewrite_one_url(u) .. c
    end)
    body_html = body_html:gsub('(src=")([^"]+)(")', function(o, u, c)
        return o .. rewrite_one_url(u) .. c
    end)
    return body_html
end

------------------------------------------------------------
-- Auto-TOC: walk the headings in the rendered body and emit a
-- nested <ul class="toc"> with hidden checkboxes + toggle labels.
-- No markdown TOC required — docs just write their content; Orlando
-- generates the navigation.
------------------------------------------------------------

local MIN_HEADINGS_FOR_TOC = 3

local function decode_entities(s)
    return (s:gsub("&amp;",  "&")
             :gsub("&lt;",   "<")
             :gsub("&gt;",   ">")
             :gsub("&quot;", '"')
             :gsub("&#39;",  "'"))
end

local function clean_heading_text(html_inner)
    local t = html_inner:gsub("<[^>]+>", "")
    t = decode_entities(t)
    t = t:gsub("^[%d%.]+%s+", "")  -- drop leading section numbers like "1 " or "1.2 "
    return t
end

local function slugify(text)
    local t = text:lower()
    t = t:gsub("[^%w]+", "-")
    t = t:gsub("^%-+", ""):gsub("%-+$", "")
    if t == "" then t = "heading" end
    return t
end

-- Move any `<p><a id="X"></a></p>` that immediately precedes a heading
-- onto the heading itself as `<hN id="X">`.
local function promote_anchors(body_html)
    return (body_html:gsub(
        '<p>%s*<a id="([^"]+)"></a>%s*</p>%s*<(h[2-6])>',
        function(id, tag)
            return "<" .. tag .. ' id="' .. id .. '">'
        end))
end

-- Add id="..." to any heading that doesn't have one yet, deriving the
-- id from the heading's visible text.
local function ensure_heading_ids(body_html)
    local seen = {}
    return (body_html:gsub('<(h[2-6])>(.-)</%1>', function(tag, inner)
        local id = slugify(clean_heading_text(inner))
        if seen[id] then
            local n = 2
            while seen[id .. "-" .. n] do n = n + 1 end
            id = id .. "-" .. n
        end
        seen[id] = true
        return "<" .. tag .. ' id="' .. id .. '">' .. inner .. "</" .. tag .. ">"
    end))
end

-- Pull out {level, text, id} for every h2/h3 in the body, in order.
local function extract_headings(body_html)
    local out = {}
    for tag, attrs, inner in body_html:gmatch('<(h[23])([^>]*)>(.-)</%1>') do
        local id = attrs:match('id="([^"]+)"')
        local text = clean_heading_text(inner)
        if id and text ~= "" then
            out[#out + 1] = { level = tonumber(tag:sub(2)), text = text, id = id }
        end
    end
    return out
end

local function headings_to_tree(headings)
    local root = { children = {} }
    local last = { [1] = root }  -- h1 is page title; we hang h2s off the root
    for _, h in ipairs(headings) do
        local node = { text = h.text, id = h.id, children = {} }
        local parent = last[h.level - 1] or root
        parent.children[#parent.children + 1] = node
        last[h.level] = node
        for d = h.level + 1, 10 do last[d] = nil end
    end
    return root
end

local toc_counter = 0
local function next_toc_id()
    toc_counter = toc_counter + 1
    return "toc-" .. toc_counter
end

local function render_toc_li(parent_qb, item)
    parent_qb:tag("li", function(li)
        if #item.children > 0 then
            local cb_id = next_toc_id()
            li:tag("input", function(inp)
                inp:attr("type",  "checkbox")
                inp:attr("id",    cb_id)
                inp:attr("class", "show-nested")
            end)
            li:tag("label", function(l)
                l:attr("class", "toc")
                l:attr("for",   cb_id)
            end)
            li:text(" ")
            li:tag("a", function(a)
                a:attr("href", "#" .. item.id)
                a:text(item.text)
            end)
            li:tag("ul", function(ul)
                for _, child in ipairs(item.children) do
                    render_toc_li(ul, child)
                end
            end)
        else
            li:tag("label", function(l)
                l:attr("class", "toc")
                l:text("\226\128\162")  -- • U+2022 bullet
            end)
            li:text(" ")
            li:tag("a", function(a)
                a:attr("href", "#" .. item.id)
                a:text(item.text)
            end)
        end
    end)
end

local function render_toc(tree)
    toc_counter = 0
    local wrapper = quick_builder.new("div")
    wrapper:tag("ul", function(ul)
        ul:attr("class", "toc")
        for _, child in ipairs(tree.children) do
            render_toc_li(ul, child)
        end
    end)
    return (wrapper:render():gsub("^<div>", ""):gsub("</div>$", ""))
end

-- Drop any leftover `## Contents` section (heading + its bulleted list)
-- still present in the source markdown.
local function strip_manual_toc(body_html)
    body_html = body_html:gsub(
        '<h2[^>]*>[^<]*Contents%s*</h2>%s*<ul>.-</ul>', "")
    return body_html
end

local function insert_auto_toc(body_html, toc_html)
    local h1_end = body_html:find("</h1>", 1, true)
    if h1_end then
        return body_html:sub(1, h1_end + 4) .. toc_html .. body_html:sub(h1_end + 5)
    end
    return toc_html .. body_html
end

local function transform_toc(body_html)
    body_html = strip_manual_toc(body_html)
    body_html = promote_anchors(body_html)
    body_html = ensure_heading_ids(body_html)

    local headings = extract_headings(body_html)
    if #headings < MIN_HEADINGS_FOR_TOC then
        return body_html
    end

    local toc_html = render_toc(headings_to_tree(headings))
    return insert_auto_toc(body_html, toc_html)
end

-- Wrap any fenced ```json block whose content begins with `{"vibecode":` in
-- a collapsible <details class="vibecode"> shell with Monokai syntax-
-- highlighted JSON inside. style.css handles the dark colouring and the
-- open/closed arrow. Default state: collapsed.
local function decode_html_entities(s)
    return (s:gsub("&quot;", '"')
             :gsub("&lt;",   "<")
             :gsub("&gt;",   ">")
             :gsub("&#39;",  "'")
             :gsub("&amp;",  "&"))
end

local function wrap_vibecode_blocks(body_html)
    return (body_html:gsub(
        '<pre><code class="language%-json">({&quot;vibecode&quot;.-)</code></pre>',
        function(escaped_json)
            local json = decode_html_entities(escaped_json)
            local highlighted = json_highlight.highlight(json)
            return '<details class="vibecode"><summary>vibecode</summary>'
                .. '<div class="vibecode-code"><pre>' .. highlighted
                .. '</pre></div></details>'
        end))
end

-- Add target="_blank" rel="noopener" to any <a> with an external href.
local function mark_external_links(body_html)
    return (body_html:gsub('<a%s+([^>]*)>', function(attrs)
        local href = attrs:match('href="([^"]+)"')
        if not href or not href:match("^https?://") then return nil end
        if attrs:find('target=') then return nil end
        return '<a ' .. attrs .. ' target="_blank" rel="noopener">'
    end))
end

------------------------------------------------------------
-- Step 3: page template (full HTML doc)
------------------------------------------------------------

local function add_head(html_tag, title)
    html_tag:tag("head", function(h)
        h:tag("meta", function(m) m:attr("charset", "utf-8") end)
        h:tag("meta", function(m)
            m:attr("name",    "viewport")
            m:attr("content", "width=device-width, initial-scale=1")
        end)
        h:tag("title", function(t) t:text(title or "") end)
        h:tag("link", function(l)
            l:attr("rel",  "stylesheet")
            l:attr("href", "/client-assets/style.css")
        end)
    end)
end

local function add_sidebar(nav_tag, current_md_path)
    nav_tag:tag("h1", function(h1)
        h1:tag("a", function(a)
            a:attr("href", "/")
            a:tag("img", function(img)
                img:attr("class",  "logo")
                img:attr("src",    LOGO_URL)
                img:attr("alt",    "")
                img:attr("width",  "16")
                img:attr("height", "16")
            end)
            a:text("Home")
        end)
    end)
    nav_tag:raw(nav.build(current_md_path))
end

--[[ {
    "in":  {"ctx": "table { md_path = string (fs path), title = string?, is_home = boolean? }"},
    "out": "string (full HTML page, ready to send over HTTP)"
} ]]
function M.render_request(ctx)
    local f, err = io.open(ctx.md_path, "r")
    if not f then
        error("orlando.page: cannot open " .. tostring(ctx.md_path) .. ": " .. tostring(err))
    end
    local md = f:read("*a")
    f:close()

    local body = M.render(md)
    body = inject_hero_logo(body)
    body = link_existing_hero_logo(body)
    body = rewrite_links(body)
    body = mark_external_links(body)
    body = wrap_vibecode_blocks(body)
    body = transform_toc(body)

    local html = quick_builder.new("html")
    html:attr("lang", "en")
    add_head(html, ctx.title)
    html:tag("body", function(b)
        if ctx.is_home then b:attr("class", "home") end
        b:tag("div", function(layout)
            layout:attr("class", "layout")
            layout:tag("nav", function(n)
                n:attr("class", "sidebar")
                add_sidebar(n, ctx.md_path)
            end)
            layout:tag("main", function(m)
                m:attr("class", "content")
                m:raw(body)
            end)
        end)
    end)

    return "<!DOCTYPE html>\n" .. html:render()
end

------------------------------------------------------------
-- Minimal wrapper (kept for the CLI; no chrome)
------------------------------------------------------------

function M.wrap_minimal(body, title)
    return table.concat({
        '<!DOCTYPE html>\n',
        '<html lang="en">\n',
        '<head><title>', title or "", '</title></head>\n',
        '<body>\n',
        body,
        '\n</body>\n',
        '</html>\n',
    })
end

function M.render_file(path, title)
    local f, err = io.open(path, "r")
    if not f then
        error("orlando.page: cannot open " .. tostring(path) .. ": " .. tostring(err))
    end
    local md = f:read("*a")
    f:close()
    return M.wrap_minimal(M.render(md), title or path)
end

return M
