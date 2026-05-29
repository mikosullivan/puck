--[[
{
  "module": "orlando.page",
  "role": "Markdown-to-HTML rendering plus the page-template chrome (stylesheet link, layout shell, sidebar nav, hero logo). Used by orlando.server for per-request HTML generation and by orlando/lua/render.lua for CLI rendering.",
  "exports": {
    "render":              "markdown string -> body HTML string (lunamark with fenced code + pipe tables enabled)",
    "wrap_minimal":        "body HTML + title -> minimal HTML doc (used by CLI render.lua; no chrome)",
    "render_file":         "path + title -> minimal HTML doc; reads, renders, wraps (CLI)",
    "render_request":      "ctx { md_path, title } -> full HTML page with chrome",
    "render_results_page": "ctx { title, body_html, query? } -> full HTML page with chrome and a body that is not a markdown render (used by orlando.search)",
    "md_path_to_url":      "fs md_path -> canonical Orlando URL (README.md -> /documentation/, dir-index files -> trailing slash form)"
  },
  "no_caching": "every call re-reads source and re-runs the pipeline per the Orlando no-caching design"
}
]]
local lunamark          = require("lunamark")
local quick_builder     = require("orlando.quick_builder")
local nav               = require("orlando.nav")
local json_highlight    = require("orlando.json_highlight")
local caspian_highlight = require("orlando.caspian_highlight")
local issues_fetcher    = require("orlando.issues")
local config            = require("orlando.config")

local M = {}

local READER_OPTIONS = {
    fenced_code_blocks = true,
    pipe_tables        = true,
}

local LOGO_URL = "/static/logo.svg"

------------------------------------------------------------
-- Pre-render: expand <!-- file: PATH --> markers into fenced
-- code blocks containing the named file's contents. PATH is
-- relative to the markdown file's directory; language is
-- inferred from extension (json, casp/caspj -> caspian, lua).
-- Unknown extensions get a tagless fence (still renders as a
-- <pre>). Invisible on GitHub (HTML comment); expanded here.
------------------------------------------------------------

local EXT_TO_LANG = {
    json  = "json",
    casp  = "caspian",
    caspj = "caspian",
    lua   = "lua",
}

local function process_file_includes(md, md_path)
    local md_dir = md_path:match("^(.+)/[^/]+$") or "."
    return (md:gsub("<!%-%- file: (%S+) %-%->", function(rel_path)
        local full = md_dir .. "/" .. rel_path
        local f, err = io.open(full, "r")
        if not f then
            return "<!-- file: " .. rel_path
                .. " (NOT FOUND: " .. (err or "unknown") .. ") -->"
        end
        local content = f:read("*a")
        f:close()
        content = content:gsub("\n+$", "")
        local ext  = rel_path:match("%.([^.]+)$")
        local lang = (ext and EXT_TO_LANG[ext]) or ""
        return "```" .. lang .. "\n" .. content .. "\n```"
    end))
end

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
--   "documentation/foo/bar.md"        -> "/documentation/foo/bar"
--   "foo.md"                          -> "foo"
--   "orlando/static/logo.svg"         -> "/static/logo.svg"
--   "orlando/client-assets/style.css" -> "/client-assets/style.css"
--   "../baz.md#frag"                  -> "../baz#frag"   (relative; browser resolves)
-- External http(s), # anchors, and mailto: are left alone.
local function rewrite_one_url(url)
    if url:match("^https?://") or url:sub(1,1) == "#" or url:sub(1,7) == "mailto:" then
        return url
    end
    local path, frag = url:match("^([^#]+)(#.*)$")
    if not path then path, frag = url, "" end
    path = path:gsub("^orlando/static/",         "/static/")
    path = path:gsub("^orlando/client%-assets/", "/client-assets/")
    path = path:gsub("^documentation/",          "/documentation/")
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
                l:text("")  -- force <label></label>; the arrow is from CSS ::before
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

-- TOC goes directly under the title — immediately after the closing
-- </h1> tag, before any subtitle, vibecode, or intro prose.
local function insert_auto_toc(body_html, toc_html)
    local h1_end = body_html:find("</h1>", 1, true)
    if h1_end then
        return body_html:sub(1, h1_end + 4) .. toc_html .. body_html:sub(h1_end + 5)
    end
    -- Fallback: no H1 — place TOC before the first H2, or prepend.
    local h2_start = body_html:find("<h2", 1, true)
    if h2_start then
        return body_html:sub(1, h2_start - 1) .. toc_html .. body_html:sub(h2_start)
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

------------------------------------------------------------
-- GitHub issue links on H1 and every H2/H3 heading.
-- Each link prefills a GitHub issue with the file path (and
-- section title + anchor, for H2/H3) so a reader can open a
-- doc bug straight from the page.
------------------------------------------------------------

local GITHUB_REPO = "https://github.com/mikosullivan/puck"

local function url_encode(s)
    return (s:gsub("[^%w%-._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function issue_link(md_path, section_text, section_id)
    local title, body
    if section_text then
        title = md_path .. " § " .. section_text
        body  = "File: " .. md_path .. "\n\nSection: " .. section_text
        if section_id then
            body = body .. "\nAnchor: #" .. section_id
        end
    else
        title = md_path
        body  = "File: " .. md_path
    end
    local href = GITHUB_REPO .. "/issues/new?title=" .. url_encode(title)
        .. "&body=" .. url_encode(body)
    return '<a href="' .. href .. '" class="section-issue" '
        .. 'target="_blank" rel="noopener">GitHub issue</a>'
end

-- HTML-escape suitable for attribute values AND textarea content.
local function html_escape(s)
    return (s:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub('"', "&quot;"))
end

-- Build the "Quick add" toggle label + the hidden checkbox + the form.
-- The form POSTs to Orlando's /api/quick-add-issue endpoint, which calls
-- `gh issue create` server-side. target="qa-target" sends the response
-- into a single hidden iframe at the page bottom — the reader stays put.
-- quick-add.js handles two concerns:
--   1. focus the body textarea when the toggle flips on (autofocus
--      can't fire on a hidden form);
--   2. on submit, swap the form for a "Issue submitted" status that
--      links to the created issue (read from the iframe response).
local function quick_add_block(md_path, section_text, section_id, dom_id)
    local title_prefill = "File: " .. md_path
    if section_text then
        title_prefill = title_prefill .. " § " .. section_text
        if section_id then
            title_prefill = title_prefill .. " (#" .. section_id .. ")"
        end
    end
    return table.concat({
        '\n<input type="checkbox" hidden class="quick-add-toggle" id="', dom_id, '"/>',
        '\n<div class="quick-add-form">',
        '<form action="/api/quick-add-issue" method="POST" target="qa-target">',
        '<input type="text" name="title" value="', html_escape(title_prefill), '" required>',
        '<textarea name="body" rows="6"></textarea>',
        '<div class="quick-add-actions">',
        '<button type="submit">Submit issue</button>',
        '<label for="', dom_id, '" class="quick-add-cancel">Cancel</label>',
        '</div>',
        '</form>',
        '</div>',
        '<div class="quick-add-status" hidden></div>',
    })
end

local function quick_add_label(dom_id)
    return '<label class="section-issue" for="' .. dom_id .. '">Quick add</label>'
end

-- Edit form: a "Edit" toggle next to GitHub-issue / Quick-add, plus a
-- hidden checkbox + form. The textarea is empty in the rendered HTML;
-- edit.js fetches the section's current markdown from
-- /api/section-markdown and populates the textarea when the form first
-- opens. Submission POSTs to /api/edit-suggestion which creates a
-- labelled GitHub issue with the user's proposed replacement.
local function edit_label(dom_id)
    return '<label class="section-issue edit-label" for="' .. dom_id .. '">Edit</label>'
end

local function edit_block(md_path, section_text, section_id, dom_id)
    local anchor_value = section_id or ""
    local title_value  = section_text or ""
    return table.concat({
        '\n<input type="checkbox" hidden class="edit-toggle" id="', dom_id, '"/>',
        '\n<div class="edit-form">',
        '<form action="/api/edit-suggestion" method="POST" target="edit-target" '
            .. 'data-md-path="', html_escape(md_path), '" '
            .. 'data-anchor="', html_escape(anchor_value), '">',
        '<input type="hidden" name="path" value="',          html_escape(md_path),      '">',
        '<input type="hidden" name="anchor" value="',        html_escape(anchor_value), '">',
        '<input type="hidden" name="section_title" value="', html_escape(title_value),  '">',
        '<textarea name="markdown" rows="16" placeholder="Loading section…" required></textarea>',
        '<div class="edit-actions">',
        '<button type="submit">Submit edit</button>',
        '<label for="', dom_id, '" class="edit-cancel">Cancel</label>',
        '</div>',
        '</form>',
        '</div>',
        '<div class="edit-status" hidden></div>',
    })
end

-- Render the comments list under an issue. Returns "" for issues with
-- no comments. Each comment shows author, date (YYYY-MM-DD), and body
-- (run through the markdown renderer just like the issue body).
local function render_issue_comments(comments)
    if not comments or #comments == 0 then return "" end
    local parts = { '<ul class="issue-comments">' }
    for _, c in ipairs(comments) do
        local date = (c.created_at or ""):sub(1, 10)
        local body_html = ""
        if c.body and c.body ~= "" then
            body_html = M.render(c.body)
        end
        parts[#parts + 1] = '<li class="issue-comment">'
            .. '<div class="comment-head">'
            ..   '<span class="comment-author">' .. html_escape(c.author or "") .. '</span>'
            ..   ' <span class="comment-date">' .. html_escape(date) .. '</span>'
            .. '</div>'
            .. '<div class="comment-body">' .. body_html .. '</div>'
            .. '</li>'
    end
    parts[#parts + 1] = '</ul>'
    return table.concat(parts)
end

-- Render the per-section open-issues panel (used under each H2-H6 heading
-- that has issues whose title ends with `(#<anchor>)`). Same look as the
-- page-top panel, but the section-context is implied so the "§ Section"
-- chip on each item is omitted. Returns "" when the section has no issues.
local function render_section_issues_panel(md_path, anchor)
    local issues = issues_fetcher.fetch_section(md_path, anchor)
    if not issues or #issues == 0 then return "" end
    local parts = {}
    parts[#parts + 1] = '<details class="issues-panel section-issues-panel">'
    parts[#parts + 1] = '<summary>Open issues (' .. tostring(#issues) .. ')</summary>'
    parts[#parts + 1] = '<ul class="issues-list">'
    for _, issue in ipairs(issues) do
        local body_html = ""
        if issue.body and issue.body ~= "" then
            body_html = M.render(issue.body)
        end
        parts[#parts + 1] = '<li class="issue-item">'
            .. '<div class="issue-head">'
            ..   '<a href="' .. html_escape(issue.url or "#") .. '" '
            ..     'class="issue-number" target="_blank" rel="noopener">#'
            ..     tostring(issue.number) .. '</a>'
            ..   ' <button type="button" class="issue-close" '
            ..     'data-issue-number="' .. tostring(issue.number) .. '">'
            ..     'Close</button>'
            .. '</div>'
            .. '<div class="issue-body">' .. body_html .. '</div>'
            .. render_issue_comments(issue.comments)
            .. '</li>'
    end
    parts[#parts + 1] = '</ul>'
    parts[#parts + 1] = '</details>'
    return table.concat(parts)
end

-- Wrap the per-heading chip group ("GitHub issue", "Quick add",
-- optional "Edit") in a jqmin .nowrap span so they always stay on a
-- single line. The group as a whole still wraps to the next line if
-- the heading is too wide; only the chips' internal arrangement is
-- locked together.
local function chip_group(chips)
    return ' <span class="nowrap">' .. chips .. '</span>'
end

local function inject_issue_links(body_html, md_path, client_ip)
    -- Both Quick add and Edit are gated on the same IP allowlist —
    -- Quick add was previously open to anyone, but bulk-spam from
    -- public IPs (e.g., the 122 "katana" issues) prompted closing it.
    -- See config.ip_can_edit and ~/.orlando/config.json.
    local privileged = config.ip_can_edit(client_ip)

    -- Page H1: issue link, (Quick add if allowed), (Edit if allowed) —
    -- then checkbox + form blocks after.
    body_html = body_html:gsub("(<h1[^>]*>)(.-)(</h1>)", function(open, inner, close)
        local qa_id   = "qa-h1"
        local edit_id = "edit-h1"
        local chips = issue_link(md_path)

        if privileged then
            chips = chips
                .. " " .. quick_add_label(qa_id)
                .. " " .. edit_label(edit_id)
        end

        local tail = open .. inner .. chip_group(chips) .. close

        if privileged then
            tail = tail
                .. quick_add_block(md_path, nil, nil, qa_id)
                .. edit_block(md_path, nil, nil, edit_id)
        end

        return tail
    end, 1)

    -- Each H2 through H6: same treatment, plus a per-section issues panel
    -- if the section has issues filed against it.
    body_html = body_html:gsub("(<(h[2-6])([^>]*)>)(.-)(</%2>)",
        function(open, _, attrs, inner, close)
            local id      = attrs:match('id="([^"]+)"')
            local text    = clean_heading_text(inner)
            local slug    = id or slugify(text)
            local qa_id   = "qa-" .. slug
            local edit_id = "edit-" .. slug
            local chips = issue_link(md_path, text, id)

            if privileged then
                chips = chips
                    .. " " .. quick_add_label(qa_id)
                    .. " " .. edit_label(edit_id)
            end

            local tail = open .. inner .. chip_group(chips) .. close

            if privileged then
                tail = tail
                    .. quick_add_block(md_path, text, id, qa_id)
                    .. edit_block(md_path, text, id, edit_id)
            end

            tail = tail .. render_section_issues_panel(md_path, id)
            return tail
        end)

    return body_html
end

-- Highlight every fenced ```json block in the rendered body.
-- Blocks whose content begins with `{"vibecode":` get wrapped in a
-- collapsible <details class="vibecode"> shell with the Monokai
-- (dark) theme inside; every other JSON block is highlighted in place
-- with the pygments default (light) theme. style.css supplies both
-- palettes.
local function decode_html_entities(s)
    return (s:gsub("&quot;", '"')
             :gsub("&lt;",   "<")
             :gsub("&gt;",   ">")
             :gsub("&#39;",  "'")
             :gsub("&amp;",  "&"))
end

local function highlight_json_blocks(body_html)
    return (body_html:gsub(
        '<pre><code class="language%-json">(.-)</code></pre>',
        function(escaped_json)
            local json = decode_html_entities(escaped_json)
            local highlighted = json_highlight.highlight(json)
            if escaped_json:match("^{&quot;vibecode&quot;") then
                return '<details class="vibecode"><summary>vibecode</summary>'
                    .. '<div class="vibecode-code"><pre>' .. highlighted
                    .. '</pre></div></details>'
            end
            return '<pre class="highlight"><code>' .. highlighted .. '</code></pre>'
        end))
end

-- Mark JSON code blocks that sit under a Skeletor-snapshot subheading
-- so style.css can give them a distinguishing border. Walks the body
-- in section order: each heading whose id contains "skeletor" claims
-- every <pre class="highlight"> between it and the next heading.
local function mark_skeletor_blocks(body_html)
    local result = {}
    local pos = 1
    local pattern = '<h(%d)[^>]*id="[^"]*skeletor[^"]*"[^>]*>.-</h%1>'
    while true do
        local s, e = body_html:find(pattern, pos)
        if not s then
            result[#result + 1] = body_html:sub(pos)
            break
        end
        result[#result + 1] = body_html:sub(pos, e)
        local next_h = body_html:find("<h%d", e + 1)
        local section_end = next_h and (next_h - 1) or #body_html
        local section = body_html:sub(e + 1, section_end)
        section = section:gsub(
            '<pre class="highlight">',
            '<pre class="highlight skeletor-state">')
        result[#result + 1] = section
        pos = section_end + 1
    end
    return table.concat(result)
end

local function highlight_caspian_blocks(body_html)
    return (body_html:gsub(
        '<pre><code class="language%-caspian">(.-)</code></pre>',
        function(escaped_source)
            local source = decode_html_entities(escaped_source)
            local highlighted = caspian_highlight.highlight(source)
            return '<pre class="highlight"><code>' .. highlighted .. '</code></pre>'
        end))
end

------------------------------------------------------------
-- Open-issues panel at the top of each page.
-- Lists every open GitHub issue whose title is "File: <md_path> ..."
-- (the prefix the per-section Quick-add panel files issues with).
-- Rendered as a collapsible <details open> just below the vibecode,
-- or just below the H1 if the page has no vibecode.
------------------------------------------------------------

local function render_issues_panel(issues)
    if not issues or #issues == 0 then return "" end
    local parts = {}
    parts[#parts + 1] = '<details class="issues-panel">'
    parts[#parts + 1] = '<summary>Open issues (' .. tostring(#issues) .. ')</summary>'
    parts[#parts + 1] = '<ul class="issues-list">'
    for _, issue in ipairs(issues) do
        local section = ""
        -- Title format is "File: <path>" or "File: <path> § Section (#anchor)"
        local sect = (issue.title or ""):match("§%s*(.-)%s*%(")
        if not sect then sect = (issue.title or ""):match("§%s*(.+)$") end
        if sect then
            section = ' <span class="issue-section">§ ' .. html_escape(sect) .. '</span>'
        end
        local body_html = ""
        if issue.body and issue.body ~= "" then
            body_html = M.render(issue.body)
        end
        parts[#parts + 1] = '<li class="issue-item">'
            .. '<div class="issue-head">'
            ..   '<a href="' .. html_escape(issue.url or "#") .. '" '
            ..     'class="issue-number" target="_blank" rel="noopener">#'
            ..     tostring(issue.number) .. '</a>'
            ..   ' <button type="button" class="issue-close" '
            ..     'data-issue-number="' .. tostring(issue.number) .. '">'
            ..     'Close</button>'
            ..   section
            .. '</div>'
            .. '<div class="issue-body">' .. body_html .. '</div>'
            .. render_issue_comments(issue.comments)
            .. '</li>'
    end
    parts[#parts + 1] = '</ul>'
    parts[#parts + 1] = '</details>'
    return table.concat(parts)
end

-- Inject the panel just below the first vibecode <details> (the page-level
-- vibecode block). If no vibecode is present, insert just after the first
-- </h1>. If neither exists, prepend to the body.
local function inject_issues_panel(body_html, md_path)
    local issues = issues_fetcher.fetch(md_path)
    local panel = render_issues_panel(issues)
    if panel == "" then return body_html end

    -- The vibecode wrapper is '<details class="vibecode">...</details>'.
    -- Find its closing tag.
    local vc_start = body_html:find('<details class="vibecode">', 1, true)
    if vc_start then
        local close = body_html:find('</details>', vc_start, true)
        if close then
            local cut = close + #'</details>'
            return body_html:sub(1, cut) .. panel .. body_html:sub(cut + 1)
        end
    end

    -- Fallback: after the first </h1>.
    local h1_end = body_html:find('</h1>', 1, true)
    if h1_end then
        local cut = h1_end + #'</h1>'
        return body_html:sub(1, cut) .. panel .. body_html:sub(cut + 1)
    end

    return panel .. body_html
end

-- Add target="_blank" rel="noopener" to any <a> that points elsewhere:
--   - External (http://, https://) URLs.
--   - Local URLs pointing at a non-markdown file (.html, .css, .js,
--     .casp, .json, images, etc.) — these are static assets the
--     reader expects to view alongside the doc, not navigate to.
-- Same-tab links: extensionless URLs (markdown renders), .md URLs (raw
-- markdown), pure-anchor hrefs (#section), and any <a> that already has
-- a target attribute.
local function mark_external_links(body_html)
    return (body_html:gsub('<a%s+([^>]*)>', function(attrs)
        local href = attrs:match('href="([^"]+)"')
        if not href then return nil end
        if attrs:find('target=') then return nil end
        if href:match("^https?://") then
            return '<a ' .. attrs .. ' target="_blank" rel="noopener">'
        end
        -- Local link: check extension, strip any query or anchor first.
        local clean = href:gsub("[?#].*$", "")
        local ext = clean:match("%.([a-zA-Z0-9]+)$")
        if ext and ext:lower() ~= "md" then
            return '<a ' .. attrs .. ' target="_blank" rel="noopener">'
        end
        return nil
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
        -- jqmin is the puck.uno site's default client-side framework
        -- (see documentation/site/frameworks/jqmin/index.md). Served
        -- straight from its canonical source under /documentation/.
        h:tag("link", function(l)
            l:attr("rel",  "stylesheet")
            l:attr("href", "/documentation/site/frameworks/jqmin/jqmin.css")
        end)
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/quick-add.js")
            s:attr("defer", "")
            s:text("")  -- force <script></script>; QuickBuilder would self-close otherwise
        end)
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/issue-actions.js")
            s:attr("defer", "")
            s:text("")
        end)
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/edit.js")
            s:attr("defer", "")
            s:text("")
        end)
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/copy-code.js")
            s:attr("defer", "")
            s:text("")
        end)
    end)
end

-- True if documentation/<rel>/<lastpart>.md exists — i.e., the dir has a
-- same-named index file we can link the breadcrumb segment to.
local function has_dir_index(rel)
    if rel == "" then return false end
    local last = rel:match("([^/]+)$")
    if not last then return false end
    local f = io.open("documentation/" .. rel .. "/" .. last .. ".md", "rb")
    if not f then return false end
    local _, err = f:read(1)
    f:close()
    return err == nil
end

-- Map an fs md_path to the canonical URL Orlando serves it at.
-- README.md is served at /documentation/ (the docs entry); everything
-- else lives under /documentation/<path>.
local function md_path_to_url(md_path)
    if md_path == "README.md" then return "/documentation/" end
    local rel = md_path:gsub("^documentation/", ""):gsub("%.md$", "")
    local parent, name = rel:match("^(.*)/([^/]+)$")
    if parent and name then
        local parent_last = parent:match("([^/]+)$") or parent
        if parent_last == name then
            return "/documentation/" .. parent .. "/"
        end
    end
    return "/documentation/" .. rel
end

M.md_path_to_url = md_path_to_url

-- Does a given URL path serve a markdown page? Used by the breadcrumb
-- to decide whether each intermediate segment links somewhere.
local function url_has_index(url_path)
    if url_path == "/documentation" then return true end  -- README.md is the index
    local rel = url_path:gsub("^/documentation/", "")
    if rel == url_path then return false end  -- not under /documentation/
    return has_dir_index(rel)
end

local function add_breadcrumb(parent_qb, md_path)
    parent_qb:tag("nav", function(bc)
        bc:attr("class", "breadcrumb")
        local segments = {}
        for s in md_path_to_url(md_path):gmatch("[^/]+") do
            segments[#segments + 1] = s
        end
        -- Site root link is always first.
        bc:tag("a", function(a) a:attr("href", "/"); a:text("home") end)
        local cumulative = ""
        for i, seg in ipairs(segments) do
            bc:tag("span", function(s) s:attr("class", "sep"); s:text("/") end)
            cumulative = cumulative .. "/" .. seg
            local is_last = (i == #segments)
            if is_last then
                bc:tag("span", function(s) s:attr("class", "current"); s:text(seg) end)
            elseif url_has_index(cumulative) then
                bc:tag("a", function(a)
                    a:attr("href", cumulative .. "/")
                    a:text(seg)
                end)
            else
                bc:tag("span", function(s) s:text(seg) end)
            end
        end
    end)
end

local function add_search_form(nav_tag, prefill)
    nav_tag:tag("form", function(form)
        form:attr("class",  "sidebar-search")
        form:attr("action", "/search")
        form:attr("method", "get")
        form:tag("input", function(i)
            i:attr("type",        "search")
            i:attr("name",        "q")
            i:attr("placeholder", "Search")

            if prefill and prefill ~= "" then
                i:attr("value", prefill)
            end
        end)
    end)
end

local function add_random_link(nav_tag)
    nav_tag:tag("a", function(a)
        a:attr("class", "sidebar-random")
        a:attr("href",  "/random")
        a:text("Random page")
    end)
end

local function add_sidebar(nav_tag, current_md_path, search_query)
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

    add_search_form(nav_tag, search_query)
    add_random_link(nav_tag)
    nav_tag:raw(nav.build(current_md_path))
end

--[[ {
    "in":  {"ctx": "table { md_path = string (fs path), title = string?, client_ip = string? — used to gate the per-section Edit chip }"},
    "out": "string (full HTML page, ready to send over HTTP)"
} ]]
function M.render_request(ctx)
    local f, err = io.open(ctx.md_path, "r")
    if not f then
        error("orlando.page: cannot open " .. tostring(ctx.md_path) .. ": " .. tostring(err))
    end
    local md = f:read("*a")
    f:close()

    md = process_file_includes(md, ctx.md_path)

    local body = M.render(md)
    body = inject_hero_logo(body)
    body = link_existing_hero_logo(body)
    body = rewrite_links(body)
    body = mark_external_links(body)
    body = highlight_json_blocks(body)
    body = highlight_caspian_blocks(body)
    body = inject_issues_panel(body, ctx.md_path)
    body = transform_toc(body)
    body = mark_skeletor_blocks(body)
    body = inject_issue_links(body, ctx.md_path, ctx.client_ip)

    local html = quick_builder.new("html")
    html:attr("lang", "en")
    add_head(html, ctx.title)
    html:tag("body", function(b)
        b:tag("div", function(layout)
            layout:attr("class", "layout")
            layout:tag("nav", function(n)
                n:attr("class", "sidebar")
                add_sidebar(n, ctx.md_path)
            end)
            layout:tag("main", function(m)
                m:attr("class", "content")
                add_breadcrumb(m, ctx.md_path)
                m:raw(body)
            end)
        end)
        -- Shared hidden target for every Quick-add form on the page.
        b:tag("iframe", function(f)
            f:attr("name",   "qa-target")
            f:attr("class",  "quick-add-iframe")
            f:attr("hidden", "")
            f:text("")
        end)

        -- Separate hidden target for Edit-suggestion forms so the two
        -- submit flows don't share state or step on each other's iframe
        -- load events.
        b:tag("iframe", function(f)
            f:attr("name",   "edit-target")
            f:attr("class",  "quick-add-iframe")
            f:attr("hidden", "")
            f:text("")
        end)
        b:tag("hr", function(_) end)
        b:tag("span", function(s)
            s:attr("class", "about")
            s:text("© 2026 Puck.uno")
        end)
    end)

    return "<!DOCTYPE html>\n" .. html:render()
end

--[[ {
    "in":  {"ctx": "table { fs_path = string, url_path = string, title = string?, client_ip = string? }"},
    "out": "string (full HTML page, ready to send over HTTP)",
    "note": "Renders a directory listing for directories that have no index.md. Shows subdirs and md/asset files as a simple list, with the standard site chrome."
} ]]
function M.render_dir_listing(ctx)
    local fs_path  = ctx.fs_path
    local url_path = ctx.url_path  -- e.g. "/documentation/ideas/" — always trailing-slash
    if url_path:sub(-1) ~= "/" then url_path = url_path .. "/" end

    -- Use `ls -1aF` (same convention as nav.lua) so dirs get a trailing /.
    local entries = {}
    local handle = io.popen('ls -1aF "' .. fs_path .. '" 2>/dev/null')
    if handle then
        for entry in handle:lines() do
            if entry ~= "./" and entry ~= "../" then
                local is_dir = entry:sub(-1) == "/"
                local name   = is_dir and entry:sub(1, -2)
                                       or entry:gsub("[%*%@%|%=]$", "")
                if name:sub(1, 1) ~= "." then
                    entries[#entries + 1] = { name = name, is_dir = is_dir }
                end
            end
        end
        handle:close()
    end
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)

    -- Build the listing body as HTML.
    local body = quick_builder.new("div")
    body:tag("h1", function(h) h:text(ctx.title or url_path) end)

    if #entries == 0 then
        body:tag("p", function(p) p:text("(empty directory)") end)
    else
        body:tag("ul", function(ul)
            ul:attr("class", "dir-listing")
            for _, e in ipairs(entries) do
                ul:tag("li", function(li)
                    local label, href
                    if e.is_dir then
                        label = e.name .. "/"
                        href  = url_path .. e.name .. "/"
                    elseif e.name:sub(-3) == ".md" then
                        label = e.name:sub(1, -4)
                        href  = url_path .. label
                    else
                        label = e.name
                        href  = url_path .. e.name
                    end
                    li:tag("a", function(a)
                        a:attr("href", href)
                        a:text(label)
                    end)
                end)
            end
        end)
    end

    return M.render_results_page({
        title     = ctx.title or url_path,
        body_html = body:render():gsub("^<div>", ""):gsub("</div>$", ""),
    })
end

--[[ {
    "in":  {"ctx": "table { title = string?, body_html = string, query = string? }"},
    "out": "string (full HTML page, ready to send over HTTP)",
    "note": "Same chrome as render_request but the content body is supplied verbatim (not derived from a markdown source). Used by orlando.search."
} ]]
function M.render_results_page(ctx)
    local html = quick_builder.new("html")
    html:attr("lang", "en")
    add_head(html, ctx.title)

    html:tag("body", function(b)
        b:tag("div", function(layout)
            layout:attr("class", "layout")

            layout:tag("nav", function(n)
                n:attr("class", "sidebar")
                add_sidebar(n, nil, ctx.query)
            end)

            layout:tag("main", function(m)
                m:attr("class", "content")
                m:raw(ctx.body_html)
            end)
        end)

        b:tag("hr", function(_) end)

        b:tag("span", function(s)
            s:attr("class", "about")
            s:text("© 2026 Puck.uno")
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
