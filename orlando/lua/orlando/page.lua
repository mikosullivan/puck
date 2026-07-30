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
local issue_panel       = require("orlando.issue_panel")
local config            = require("orlando.config")

local M = {}

local READER_OPTIONS = {
    fenced_code_blocks = true,
    pipe_tables        = true,
    preserve_tabs      = true,
}

local LOGO_URL = "/static/logo.svg"

------------------------------------------------------------
-- Pre-render: expand <!-- file: PATH --> markers into fenced
-- code blocks containing the named file's contents. PATH is
-- relative to the markdown file's directory; language is
-- inferred from extension (json, casp/caspj -> caspian, lua).
-- Unknown extensions get a tagless fence (still renders as a
-- <pre>). Invisible on GitHub (HTML comment); expanded here.
--
-- The directive must be ALONE ON ITS OWN LINE — only optional
-- whitespace around it. This is what makes it safe to mention
-- the literal `<!-- file: ... -->` syntax inside prose backticks
-- (as documentation) without that mention being expanded too.
------------------------------------------------------------

local EXT_TO_LANG = {
    json  = "json",
    casp  = "caspian",
    caspj = "caspian",
    lua   = "lua",
}

local function expand_include(md_dir, rel_path)
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
end

local function process_file_includes(md, md_path)
    local md_dir = md_path:match("^(.+)/[^/]+$") or "."

    -- Walk the markdown one line at a time. Replace lines that are
    -- ONLY a "<!-- file: PATH -->" directive (with optional
    -- surrounding whitespace) with the expanded fenced block.
    -- Lines that merely contain the directive somewhere within them
    -- — for example, inside backticks in a prose paragraph — are
    -- left alone.
    local DIRECTIVE_LINE = "^%s*<!%-%- file: (%S+) %-%->%s*$"
    local out = {}
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        local rel_path = line:match(DIRECTIVE_LINE)
        if rel_path then
            out[#out + 1] = expand_include(md_dir, rel_path)
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

------------------------------------------------------------
-- GitHub-issue directives.
--
-- Two directives, both expanded at render time against the live
-- open-issue list (filtered to issues whose title references a
-- file under documentation/<PATH_PREFIX>/ AND whose referenced
-- file currently exists on disk):
--
--   <!-- github-issues-against: PATH_PREFIX -->
--      Renders each matching issue verbatim: H3 heading
--      "#NUM — short title" linked to GitHub, followed by the
--      issue body as markdown. Used by audit.md to display
--      tracked problems without maintaining a static snapshot.
--
--   <!-- github-issues-summary: PATH_PREFIX -->
--      Renders a one-line executive summary: "All clear" when no
--      issues match, "Issues need attention" when at least one
--      does.
--
-- Same line-alone rule as the `file:` directive — only directives
-- on their own line expand.
------------------------------------------------------------

local function file_path_from_issue_title(title)
    -- Issue titles filed via the per-section "GitHub issue" chip start
    -- with "File: <repo-relative-path>". The path may reference either
    -- a specific .md file or a tree prefix (for sweep-style issues that
    -- span multiple files across a tree). Under the whole-repo-as-root
    -- layout, the path is any top-level tree (requirements/,
    -- documentation/, ideas/, skills/, etc.); previously it was forced
    -- to start with "documentation/".
    return title and title:match("^File:%s+(%S+)")
end

local function file_exists_on_disk(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local function matching_issues(prefix)
    -- Normalize the prefix — strip leading slash, ensure trailing slash
    -- so the match is exact at a directory boundary (avoids
    -- "requirements" matching "requirements-old"). The prefix is
    -- repo-relative (e.g. "requirements/", "documentation/foo/"), NOT
    -- wrapped in any parent directory.
    local needle = prefix:gsub("^/+", "")
    if needle:sub(-1) ~= "/" then needle = needle .. "/" end

    local issues = issues_fetcher.fetch_all()
    local matching = {}
    for _, issue in ipairs(issues or {}) do
        local fpath = file_path_from_issue_title(issue.title)
        if fpath
            and fpath:sub(1, #needle) == needle
            and file_exists_on_disk(fpath)
        then
            matching[#matching + 1] = issue
        end
    end
    return matching
end

-- Issue-card helpers (shift_body_headings / escape_loose_html_in_md /
-- esc_attr_text / short_title) used to live here. They moved into
-- orlando.issue_panel along with the rest of the per-issue rendering
-- so /issues, the per-doc panel, the per-section panel, and the
-- github-issues-against directive all share one card format.

-- Shift ATX headings in an issue body so the shallowest body heading
-- becomes H4 (one level below the H3 the issue itself renders as).
-- Skips lines inside fenced code blocks so `# comment` stays intact.
local function expand_github_issues(prefix, can_edit)
    local matching = matching_issues(prefix)
    if #matching == 0 then
        return "*No active issues.*"
    end
    -- One shared renderer for /issues, the per-doc panel, the
    -- per-section panels, and this directive. See orlando.issue_panel.
    return issue_panel.render_list(matching, { can_edit = can_edit })
end
local function expand_github_issues_summary(prefix)
    local matching = matching_issues(prefix)
    if #matching == 0 then
        return "**All clear** — no open consistency problems against files in `" .. prefix .. "`."
    end
    local n = #matching
    local noun = (n == 1) and "issue" or "issues"
    return string.format(
        "**Attention** — %d open %s below describe consistency problems against files in `%s`.",
        n, noun, prefix
    )
end

local function process_github_issues_directives(md, can_edit)
    local LIST_LINE    = "^%s*<!%-%- github%-issues%-against:%s*(%S+)%s*%-%->%s*$"
    local SUMMARY_LINE = "^%s*<!%-%- github%-issues%-summary:%s*(%S+)%s*%-%->%s*$"
    local out = {}
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        local list_prefix    = line:match(LIST_LINE)
        local summary_prefix = line:match(SUMMARY_LINE)
        if list_prefix then
            out[#out + 1] = expand_github_issues(list_prefix, can_edit)
        elseif summary_prefix then
            out[#out + 1] = expand_github_issues_summary(summary_prefix)
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

------------------------------------------------------------
-- Tag list directive: `<!-- tag-list -->` expands into a
-- table of every tag defined across documentation/, with a
-- link to the tag's canonical target and the source path(s)
-- of the marker(s). Multiple sources for one tag means the
-- tag is duplicated — flagged as an audit error inline.
------------------------------------------------------------

local function expand_tag_list()
    local tags = require("orlando.tags").list_all()
    if #tags == 0 then
        return "*No tags defined. Add `<span class=\"tag\">NAME</span>` to a doc's heading to register one.*"
    end
    local lines = {}
    lines[#lines + 1] = "| Tag | Target | Source |"
    lines[#lines + 1] = "|---|---|---|"
    local duplicates = 0
    for _, entry in ipairs(tags) do
        local sources = {}
        for _, path in ipairs(entry.sources) do
            sources[#sources + 1] = "`" .. path .. "`"
        end
        local source_cell = table.concat(sources, "<br/>")
        local dup_marker = ""
        if #entry.sources > 1 then
            duplicates = duplicates + 1
            dup_marker = " <span class=\"tag tag-duplicate\">duplicate</span>"
        end
        lines[#lines + 1] = string.format(
            "| [%s](%s) | [%s](%s)%s | %s |",
            entry.name, "/tag/" .. entry.name,
            entry.url, entry.url, dup_marker,
            source_cell
        )
    end
    if duplicates > 0 then
        local noun = (duplicates == 1) and "duplicate" or "duplicates"
        table.insert(lines, 1, string.format(
            "**%d %s detected.** A tag defined in more than one doc is an audit error — the resolver returns only the first source's URL.\n",
            duplicates, noun
        ))
        table.insert(lines, 1, "")
    end
    return table.concat(lines, "\n")
end

local function process_tag_list_directive(md)
    local TAG_LIST_LINE = "^%s*<!%-%- tag%-list %-%->%s*$"
    local out = {}
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        if line:match(TAG_LIST_LINE) then
            out[#out + 1] = expand_tag_list()
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
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
--   "tag:name#frag"                   -> "/documentation/..." + "#frag" via tag lookup
-- External http(s), # anchors, and mailto: are left alone. A missing tag
-- rewrites to "/tag/name" so the click yields a clear 404 from Orlando's
-- route module — dead references stay visible during audit.
local function rewrite_one_url(url)
    if url:match("^https?://") or url:sub(1,1) == "#" or url:sub(1,7) == "mailto:" then
        return url
    end
    -- tag:name or tag:name#frag → resolved URL at render time
    if url:sub(1, 4) == "tag:" then
        local raw = url:sub(5)
        local tag_name, anchor = raw:match("^([^#]+)(#.*)$")
        if not tag_name then tag_name, anchor = raw, "" end
        local target = require("orlando.tags").lookup(tag_name)
        if target then
            return target .. anchor
        end
        return "/tag/" .. raw
    end
    local path, frag = url:match("^([^#]+)(#.*)$")
    if not path then path, frag = url, "" end
    path = path:gsub("^orlando/static/",         "/static/")
    path = path:gsub("^orlando/client%-assets/", "/client-assets/")
    -- Any top-level doc-tree path (documentation/, requirements/, ideas/,
    -- skills/, README.md, etc.) IS the URL: repo layout is the URL layout.
    -- Just strip .md and prefix with /.
    if path:sub(1,1) ~= "/" and not path:match("^%.%./") and not path:match("^%./") then
        path = "/" .. path
    end
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
-- CSP compliance: lunamark generates inline `style="text-align: X"`
-- attributes for markdown pipe-table column alignment (from `|---:|`,
-- `|:-:|`, etc.). Our CSP header sets `style-src 'self'`, so browsers
-- strip those inline styles. Rewrite them to class attributes that
-- style.css has rules for (.align-right, .align-center, .align-left).
------------------------------------------------------------

local function convert_table_align_to_classes(body_html)
    return (body_html:gsub('style="text%-align:%s*(%w+);?"', 'class="align-%1"'))
end

------------------------------------------------------------
-- Auto-TOC: walk the headings in the rendered body and emit a
-- nested <ul class="toc"> with hidden checkboxes + toggle labels.
-- No markdown TOC required — docs just write their content; Orlando
-- generates the navigation.
------------------------------------------------------------

local MIN_HEADINGS_FOR_TOC = 2

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

-- Strip the most common inline markdown from raw heading text so the
-- slug we compute matches what ensure_heading_ids will compute from the
-- rendered HTML. Covers `code`, **bold**, *italic*, _x_, [text](url),
-- and trailing ATX-close hashes.
--
-- Intraword underscores are LEFT ALONE, matching CommonMark's rule:
-- `foo_bar_baz` is not emphasized. The old naive `_+([^_]+)_+ → %1`
-- consumed underscores inside identifiers, producing wrong slugs for
-- headings like "`.freeze_bucket` / `.freeze_stack` / `.freeze`" —
-- the TOC's href stripped to `freezebucket-freezestack-freeze` while
-- ensure_heading_ids (working from lunamark's correct HTML) generated
-- `freeze_bucket-freeze_stack-freeze`, so the anchor never matched.
local function md_heading_text_to_plain(text)
    text = text:gsub("%s+#+%s*$", "")               -- ATX close: `## Title ##`
    text = text:gsub("!%[([^%]]*)%]%([^)]*%)", "%1") -- ![alt](url) -> alt
    text = text:gsub("%[([^%]]*)%]%([^)]*%)", "%1")  -- [text](url) -> text
    text = text:gsub("`+([^`]*)`+", "%1")           -- inline code
    text = text:gsub("%*+([^%*]+)%*+", "%1")        -- **bold** / *italic*
    -- _emphasis_ — only when the underscores are NOT surrounded by word
    -- chars (CommonMark's intraword rule). Position captures let us
    -- inspect the char immediately before / after the match in the
    -- original string.
    text = text:gsub("()(_+)([^_]+)(_+)()",
        function(a, open, content, close, b)
            local pre  = a > 1        and text:sub(a - 1, a - 1) or ""
            local post = b <= #text   and text:sub(b, b)         or ""
            if pre:match("%w") or post:match("%w") then
                return open .. content .. close  -- intraword; leave alone
            end
            return content
        end)
    return text
end

-- Pull h2-h6 headings out of the ORIGINAL markdown source — before any
-- directive expansion or file-include substitution. The TOC reflects
-- what the author wrote, not what the renderer dynamically inserted
-- (issue cards, included sections, etc.); the same list also tells
-- inject_issue_links which headings are eligible for the section chip
-- group. Skips lines inside fenced code blocks so `## not really a
-- heading` inside an example doesn't land in the result.
local function extract_headings_from_md(md)
    local out = {}
    local seen = {}
    local in_fence = false
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^```") or line:match("^~~~") then
            in_fence = not in_fence
        elseif not in_fence then
            local hashes, raw = line:match("^(#+)%s+(.+)$")
            if hashes then
                local level = #hashes
                if level >= 2 and level <= 6 then
                    local plain = md_heading_text_to_plain(raw)
                    plain = plain:gsub("^[%d%.]+%s+", "")  -- drop "1 " / "1.2 "
                    plain = plain:gsub("^%s+", ""):gsub("%s+$", "")
                    if plain ~= "" then
                        local base = slugify(plain)
                        local id = base
                        local n = 1
                        while seen[id] do
                            id = base .. "-" .. n
                            n = n + 1
                        end
                        seen[id] = true
                        out[#out + 1] = { level = level, text = plain, id = id }
                    end
                end
            end
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

local function transform_toc(body_html, toc_headings)
    body_html = strip_manual_toc(body_html)
    body_html = ensure_heading_ids(body_html)

    if not toc_headings or #toc_headings < MIN_HEADINGS_FOR_TOC then
        return body_html
    end

    local toc_html = render_toc(headings_to_tree(toc_headings))
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

-- Does the file exist in origin/master? Returns true/false. Probes with
-- `git ls-tree`; a non-empty output means the file is in the remote tree.
-- Used to decide whether to render a "GitHub page" link or a "not uploaded"
-- badge at the top of each page.
local function file_is_on_github(md_path)
    if not md_path or md_path == "" then return false end
    -- Reject anything that could break out of the path or inject shell.
    -- Path is engine-side trusted (route.lua only emits doc-tree paths),
    -- but defensive anyway.
    if md_path:find("'", 1, true) or md_path:find("\n", 1, true) then
        return false
    end
    local cmd = "git ls-tree origin/master -- '" .. md_path .. "' 2>/dev/null"
    local handle = io.popen(cmd)
    if not handle then return false end
    local out = handle:read("*a")
    handle:close()
    return out ~= nil and out ~= ""
end

-- Render the GitHub-page chip: a link to the file on GitHub if it's been
-- pushed, or a "not uploaded" badge otherwise.
local function github_page_link(md_path)
    if file_is_on_github(md_path) then
        local href = GITHUB_REPO .. "/blob/master/" .. md_path
        return '<a href="' .. href .. '" class="section-issue" '
            .. 'target="_blank" rel="noopener">GitHub page</a>'
    else
        return '<span class="section-issue">not uploaded</span>'
    end
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
-- that has issues whose title ends with `(#<anchor>)`). Section context is
-- implied so the "§ Section" chip on each item is omitted. Returns "" when
-- the section has no issues. Uses the shared orlando.issue_panel renderer
-- so /issues and the doc-page panels share one format.
local function render_section_issues_panel(md_path, anchor, client_ip)
    local issues = issues_fetcher.fetch_section(md_path, anchor)
    if not issues or #issues == 0 then return "" end
    local can_edit = client_ip ~= nil and config.ip_can_edit(client_ip)
    local parts = {
        '<details class="issues-panel section-issues-panel">',
        '<summary>Open issues (', tostring(#issues), ')</summary>',
        '<div class="issues-list">',
        issue_panel.render_list(issues, { can_edit = can_edit }),
        '</div>',
        '</details>',
    }
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

local function inject_issue_links(body_html, md_path, client_ip, original_heading_ids)
    -- Both Quick add and Edit are gated on the same IP allowlist —
    -- Quick add was previously open to anyone, but bulk-spam from
    -- public IPs (e.g., the 122 "katana" issues) prompted closing it.
    -- See config.ip_can_edit and ~/.orlando/config.json.
    local privileged = config.ip_can_edit(client_ip)
    original_heading_ids = original_heading_ids or {}

    -- Page H1: github-page link, issue link, (Quick add if allowed),
    -- (Edit if allowed) — then checkbox + form blocks after.
    body_html = body_html:gsub("(<h1[^>]*>)(.-)(</h1>)", function(open, inner, close)
        local qa_id   = "qa-h1"
        local edit_id = "edit-h1"
        local chips = github_page_link(md_path)
            .. " " .. issue_link(md_path)

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

    -- Each H2 through H6 in the rendered body. The standard chip
    -- group (file-issue, Quick add, Edit) is only injected when the
    -- heading came from the original .md source — that is, its id
    -- appears in original_heading_ids. Directive-generated headings
    -- (issue cards from anywhere — audit.md, /issues, per-doc
    -- panels, per-section panels — and their subsections) are not
    -- document sections of THIS file. Issue-card H3s also self-render
    -- their own chip group (copy badge + Comment + Close) inside the
    -- card, so we skip them entirely here to avoid double-chips.
    body_html = body_html:gsub("(<(h[2-6])([^>]*)>)(.-)(</%2>)",
        function(open, _, attrs, inner, close)
            if attrs:find('issue%-panel%-title', 1, false) then
                return open .. inner .. close
            end
            if attrs:find('data%-issue%-number', 1, false) then
                return open .. inner .. close
            end
            local id          = attrs:match('id="([^"]+)"')
            local is_original = id and original_heading_ids[id]
            if not is_original then
                return open .. inner .. close
            end

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

            tail = tail .. render_section_issues_panel(md_path, id, client_ip)
            return tail
        end)

    return body_html
end

-- Wrap each fenced code block that carries a language hint with a
-- labeled wrapper. Lunamark emits `<pre><code class="language-X">...</code></pre>`
-- for ```X ... ``` fences; this pass surrounds that with
-- `<div class="code-block"><div class="code-lang">X</div>...</div>`
-- so style.css can render a colored bar above the block displaying X.
-- Runs BEFORE the JSON/Caspian highlighters since those strip the
-- `language-X` class — the wrapper survives intact and the highlighter
-- output sits inside it.
-- Skips vibecode JSON (content starting with `{"vibecode":`) since those
-- get their own collapsible <details> treatment downstream and a blue
-- "json" bar above the collapsed details would be redundant.
local function decode_html_entities(s)
    return (s:gsub("&quot;", '"')
             :gsub("&lt;",   "<")
             :gsub("&gt;",   ">")
             :gsub("&#39;",  "'")
             :gsub("&amp;",  "&"))
end

-- Vibecode blocks are explicitly geofenced with ~~~vibecode (or raw HTML
-- <pre><code class="language-vibecode">). No content-based auto-detection.
-- Skip the language-label wrap for them since they get the collapsible
-- <details> wrap downstream.
local function wrap_code_blocks_with_language_label(body_html)
    return (body_html:gsub(
        '<pre><code class="language%-([%w_%-]+)">(.-)</code></pre>',
        function(lang, content)
            if lang == "vibecode" then return nil end
            return '<div class="code-block">'
                .. '<div class="code-lang">' .. lang .. '</div>'
                .. '<pre><code class="language-' .. lang .. '">' .. content .. '</code></pre>'
                .. '</div>'
        end))
end

-- Highlight fenced ```json blocks and ~~~vibecode blocks.
-- - language-vibecode → collapsible <details class="vibecode"> shell with
--   the Monokai (dark) theme inside.
-- - language-json → highlighted in place with the pygments default
--   (light) theme.
-- style.css supplies both palettes.

local function highlight_json_blocks(body_html)
    -- Pre-attribute matcher: anything between `<pre` and the closing `>`
    -- that isn't itself a `>`. Lua's `.-` is lazy but doesn't respect
    -- HTML boundaries — it would cross over intervening tags and match
    -- the wrong code block.
    -- Pass 1: vibecode blocks (explicitly geofenced).
    body_html = body_html:gsub(
        '<pre([^>]*)><code class="language%-vibecode">(.-)</code></pre>',
        function(_pre_attrs, escaped_json)
            local json = decode_html_entities(escaped_json)
            local highlighted = json_highlight.highlight(json)
            return '<details class="vibecode"><summary>vibecode</summary>'
                .. '<div class="vibecode-code"><pre>' .. highlighted
                .. '</pre></div></details>'
        end)
    -- Pass 2: plain JSON blocks — highlighted in place, never collapsed.
    body_html = body_html:gsub(
        '<pre([^>]*)><code class="language%-json">(.-)</code></pre>',
        function(pre_attrs, escaped_json)
            local json = decode_html_entities(escaped_json)
            local highlighted = json_highlight.highlight(json)
            return '<pre' .. pre_attrs .. ' class="highlight"><code>' .. highlighted .. '</code></pre>'
        end)
    return body_html
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

local function render_issues_panel(issues, client_ip)
    if not issues or #issues == 0 then return "" end
    local can_edit = client_ip ~= nil and config.ip_can_edit(client_ip)
    local parts = {
        '<details class="issues-panel">',
        '<summary>Open issues (', tostring(#issues), ')</summary>',
        '<div class="issues-list">',
        issue_panel.render_list(issues, {
            can_edit          = can_edit,
            show_section_chip = true,
        }),
        '</div>',
        '</details>',
    }
    return table.concat(parts)
end

-- Inject the panel just below the first vibecode <details> (the page-level
-- vibecode block). If no vibecode is present, insert just after the first
-- </h1>. If neither exists, prepend to the body.
local function inject_issues_panel(body_html, md_path, client_ip)
    local issues = issues_fetcher.fetch(md_path)
    local panel = render_issues_panel(issues, client_ip)
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
            l:attr("rel",  "icon")
            l:attr("type", "image/x-icon")
            l:attr("href", "/favicon.ico")
        end)
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
        -- Sidebar toggle: loaded non-defer so its IIFE can apply the
        -- persisted hidden state to <html> before body renders.
        h:tag("script", function(s)
            s:attr("src", "/client-assets/sidebar-toggle.js")
            s:text("")
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
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/issue-copy.js")
            s:attr("defer", "")
            s:text("")
        end)
        h:tag("script", function(s)
            s:attr("src",   "/client-assets/ghi.js")
            s:attr("defer", "")
            s:text("")
        end)
    end)
end

-- True if <rel> is a directory that Orlando can serve at /<rel>/ — covers
-- any of three ways a dir is navigable:
--   1. index.md (the standard dir-index convention)
--   2. same-named index file (legacy <rel>/<lastpart>.md convention)
--   3. auto-generated directory listing (route.lua's fallback for dirs
--      without an index file)
-- Any actual directory hits one of these, so a plain dir-existence check
-- is enough to decide the breadcrumb segment can be a link.
local function has_dir_index(rel)
    if rel == "" then return false end
    local f = io.open(rel, "rb")
    if not f then return false end
    local _, err = f:read(1)
    f:close()
    -- On Linux, opening a directory succeeds but reading one byte errors —
    -- err ~= nil means it's a directory, err == nil means it's a regular file.
    return err ~= nil
end

-- Map an fs md_path to the canonical URL Orlando serves it at.
-- README.md is served at /documentation/ (the docs entry).
-- <dir>/index.md (the dir-index convention) serves at /documentation/<dir>/.
-- <dir>/<dir>.md (legacy same-named convention) serves at /documentation/<dir>/.
-- Everything else serves at /documentation/<rel> (no trailing slash).
local function md_path_to_url(md_path)
    -- README.md at repo root IS the home page.
    if md_path == "README.md" then return "/" end
    local rel = md_path:gsub("%.md$", "")
    -- index.md convention: foo/bar/index → /foo/bar/
    local parent_idx = rel:match("^(.*)/index$")
    if parent_idx then
        return "/" .. parent_idx .. "/"
    end
    -- Same-named convention: foo/foo → /foo/
    local parent, name = rel:match("^(.*)/([^/]+)$")
    if parent and name then
        local parent_last = parent:match("([^/]+)$") or parent
        if parent_last == name then
            return "/" .. parent .. "/"
        end
    end
    return "/" .. rel
end

M.md_path_to_url = md_path_to_url

------------------------------------------------------------
-- Tree traversal: prev/next nav within a tree.
--
-- Walks a directory recursively to produce a flat ordered list of
-- markdown pages following these rules:
--   - A directory's own index.md (when it exists) comes first as
--     that directory's entry.
--   - Other children — files (excluding index.md) and subdirs — are
--     merged into one list sorted alphabetically by name.
--   - Subdirs are recursively walked at their sort position.
--
-- inject_tree_nav drops a "← previous … next →" bar right after the
-- page's <h1>. Endpoints render their unreachable side as a grayed
-- span instead of a link.
------------------------------------------------------------

local function read_h1_text(md_path)
    local f = io.open(md_path, "r")
    if not f then return nil end
    for line in f:lines() do
        local title = line:match("^#%s+(.+)$")
        if title then
            f:close()
            -- Strip basic inline markdown for clean display.
            title = title:gsub("`", "")
                         :gsub("%*+", "")
                         :gsub("%s+$", "")
            return title
        end
    end
    f:close()
    return nil
end

-- Derive a readable title from a path when the file has no H1 yet.
-- index.md uses the directory's basename; other files use their own.
-- Dashes and underscores become spaces; first letter is capitalized.
local function title_from_path(md_path)
    local base = md_path:match("([^/]+)$") or md_path
    base = base:gsub("%.md$", "")
    if base == "index" then
        local dir = md_path:match("([^/]+)/[^/]+$") or base
        base = dir
    end
    base = base:gsub("[-_]", " ")
    return (base:gsub("^%l", string.upper))
end

local function list_md_children(dir)
    local files, subdirs = {}, {}
    local handle = io.popen('ls -1aF "' .. dir .. '" 2>/dev/null')
    if not handle then return files, subdirs end
    for entry in handle:lines() do
        if entry ~= "./" and entry ~= "../" then
            if entry:sub(-1) == "/" then
                local name = entry:sub(1, -2)
                if name:sub(1, 1) ~= "." then subdirs[#subdirs + 1] = name end
            else
                local name = (entry:gsub("[%*%@%|%=]$", ""))
                if name:sub(1, 1) ~= "." and name:sub(-3) == ".md" then
                    files[#files + 1] = name
                end
            end
        end
    end
    handle:close()
    return files, subdirs
end

local function walk_tree(root)
    local out = {}

    local function visit(dir)
        local files, subdirs = list_md_children(dir)

        -- index.md (if present) is this dir's entry and goes first.
        local index_path
        local other_files = {}
        for _, f in ipairs(files) do
            if f == "index.md" then
                index_path = dir .. "/" .. f
            else
                other_files[#other_files + 1] = f
            end
        end
        if index_path then out[#out + 1] = index_path end

        -- Merge other files + subdirs into one alphabetically-ordered list.
        local entries = {}
        for _, f in ipairs(other_files) do
            entries[#entries + 1] = {
                name = f, kind = "file", path = dir .. "/" .. f,
            }
        end
        for _, d in ipairs(subdirs) do
            entries[#entries + 1] = {
                name = d, kind = "dir", path = dir .. "/" .. d,
            }
        end

        table.sort(entries, function(a, b) return a.name < b.name end)

        for _, e in ipairs(entries) do
            if e.kind == "file" then
                out[#out + 1] = e.path
            else
                visit(e.path)
            end
        end
    end

    visit(root)
    return out
end

local TREE_NAV_ROOTS = {
    "documentation/requirements",
}

local function tree_root_for(md_path)
    for _, root in ipairs(TREE_NAV_ROOTS) do
        if md_path == root .. ".md"
            or md_path:sub(1, #root + 1) == root .. "/"
        then
            return root
        end
    end
    return nil
end

local function tree_neighbors(md_path)
    local root = tree_root_for(md_path)
    if not root then return nil, nil end
    local ordered = walk_tree(root)
    for i, p in ipairs(ordered) do
        if p == md_path then return ordered[i - 1], ordered[i + 1] end
    end
    return nil, nil
end

local function inject_tree_nav(body_html, md_path)
    if not tree_root_for(md_path) then return body_html end
    local prev, nxt = tree_neighbors(md_path)
    -- Page not in any walked tree (shouldn't happen for in-scope paths).
    if not prev and not nxt and not body_html:find("<h1", 1, true) then
        return body_html
    end

    local function side(p, kind)
        local active = p ~= nil
        local arrow_glyph = (kind == "prev") and "⇦" or "⇨"
        local arrow_html = '<span class="tree-nav-arrow">' .. arrow_glyph .. '</span>'
        if active then
            local title = read_h1_text(p) or title_from_path(p)
            local url = md_path_to_url(p)
            if kind == "prev" then
                return string.format(
                    '<a class="tree-nav-%s" href="%s">%s %s</a>',
                    kind, html_escape(url), arrow_html, html_escape(title)
                )
            else
                return string.format(
                    '<a class="tree-nav-%s" href="%s">%s %s</a>',
                    kind, html_escape(url), html_escape(title), arrow_html
                )
            end
        else
            local placeholder = (kind == "prev") and "prev" or "next"
            if kind == "prev" then
                return string.format(
                    '<span class="tree-nav-%s tree-nav-disabled">%s %s</span>',
                    kind, arrow_html, placeholder
                )
            else
                return string.format(
                    '<span class="tree-nav-%s tree-nav-disabled">%s %s</span>',
                    kind, placeholder, arrow_html
                )
            end
        end
    end

    local nav_html = '<nav class="tree-nav">'
        .. side(prev, "prev")
        .. '<span class="tree-nav-sep">|</span>'
        .. side(nxt,  "next")
        .. '</nav>'

    -- Sits directly under the breadcrumb chrome and above the H1.
    -- The breadcrumb itself is added by add_breadcrumb in the page
    -- template (outside body_html), so prepending here lands the nav
    -- in the right spot.
    return nav_html .. body_html
end

-- Does a given URL path serve a markdown page? Used by the breadcrumb
-- to decide whether each intermediate segment links somewhere. Under the
-- whole-repo-as-root model, URL path IS the filesystem path from repo root.
local function url_has_index(url_path)
    local rel = url_path:gsub("^/+", "")
    if rel == "" then return true end  -- "/" is home (README.md)
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

-- The "current tree" prefix for a given source path.
--   "foo/bar/baz.md" → "foo/bar/"
--   "foo/bar/"       → "foo/bar/"   (already a dir)
--   "README.md"      → ""            (no parent — whole site)
--   nil / ""         → ""
local function tree_of(md_path)
    if not md_path or md_path == "" then return "" end
    if md_path:sub(-1) == "/" then return md_path end
    local dir = md_path:match("^(.-)/[^/]+$")
    if not dir or dir == "" then return "" end
    return dir .. "/"
end

local function add_search_form(nav_tag, prefill, current_tree, tree_active)
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

        if current_tree and current_tree ~= "" then
            form:tag("label", function(lab)
                lab:attr("class", "sidebar-search-tree")
                lab:tag("input", function(cb)
                    cb:attr("type",  "checkbox")
                    cb:attr("name",  "tree")
                    cb:attr("value", current_tree)

                    if tree_active then cb:attr("checked", "checked") end
                end)
                lab:tag("span", function(s) s:text("current tree") end)
            end)
        end
    end)
end

local function add_random_link(nav_tag)
    nav_tag:tag("a", function(a)
        a:attr("class", "sidebar-random")
        a:attr("href",  "/random")
        a:text("Random page")
    end)
end

local function add_issues_link(nav_tag)
    nav_tag:tag("a", function(a)
        a:attr("class", "sidebar-issues")
        a:attr("href",  "/issues")
        a:text("Open issues")
    end)
end

local function add_tags_link(nav_tag)
    nav_tag:tag("a", function(a)
        a:attr("class", "sidebar-tags")
        a:attr("href",  "/documentation/tags")
        a:text("Tags")
    end)
end

local function add_sidebar(nav_tag, current_md_path, search_query, current_tree, tree_active)
    -- Derive tree from the current source path when the caller didn't
    -- pass one (typical for doc-page render; search results pass the
    -- URL's tree explicitly).
    if current_tree == nil then
        current_tree = tree_of(current_md_path)
    end

    nav_tag:tag("button", function(btn)
        btn:attr("class",      "sidebar-hide-btn")
        btn:attr("type",       "button")
        btn:attr("aria-label", "Hide sidebar")
        btn:text("«")
    end)

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

    add_search_form(nav_tag, search_query, current_tree, tree_active)
    add_random_link(nav_tag)
    add_issues_link(nav_tag)
    add_tags_link(nav_tag)
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

    -- Pull headings out of the original markdown source — before any
    -- directive expansion or file-include substitution. Drives both
    -- the TOC (h2/h3 only) and the section-chip eligibility check in
    -- inject_issue_links (any id in the set).
    local all_md_headings = extract_headings_from_md(md)
    local toc_headings = {}
    local original_heading_ids = {}
    for _, h in ipairs(all_md_headings) do
        original_heading_ids[h.id] = true
        if h.level <= 3 then
            toc_headings[#toc_headings + 1] = h
        end
    end

    md = process_file_includes(md, ctx.md_path)
    local request_can_edit = ctx.client_ip ~= nil and config.ip_can_edit(ctx.client_ip)
    md = process_github_issues_directives(md, request_can_edit)
    md = process_tag_list_directive(md)

    local body = M.render(md)
    -- (inject_hero_logo / link_existing_hero_logo were dropped — the
    -- mushroom icon stays in the sidebar header; H1s render plain.)
    body = convert_table_align_to_classes(body)
    body = rewrite_links(body)
    body = mark_external_links(body)
    body = wrap_code_blocks_with_language_label(body)
    body = highlight_json_blocks(body)
    body = highlight_caspian_blocks(body)
    body = inject_issues_panel(body, ctx.md_path, ctx.client_ip)
    body = transform_toc(body, toc_headings)
    body = mark_skeletor_blocks(body)
    body = inject_issue_links(body, ctx.md_path, ctx.client_ip, original_heading_ids)
    body = inject_tree_nav(body, ctx.md_path)

    local html = quick_builder.new("html")
    html:attr("lang", "en")
    add_head(html, ctx.title)
    html:tag("body", function(b)
        b:tag("div", function(layout)
            layout:attr("class", "layout")
            layout:tag("button", function(btn)
                btn:attr("class",      "sidebar-show-btn")
                btn:attr("type",       "button")
                btn:attr("aria-label", "Show sidebar")
                btn:text("»")
            end)
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
    local url_path = ctx.url_path  -- e.g. "/ideas/" — always trailing-slash
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
        -- Pass the dir's fs path (with trailing slash) so the sidebar
        -- can locate "where we are" and auto-expand the ancestor chain.
        -- nav.on_path matches on `current_md_path` starting with
        -- `fs_dir .. "/"`; a trailing-slash dir path satisfies that for
        -- both ancestors and the dir itself.
        current_md_path = fs_path .. "/",
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

            layout:tag("button", function(btn)
                btn:attr("class",      "sidebar-show-btn")
                btn:attr("type",       "button")
                btn:attr("aria-label", "Show sidebar")
                btn:text("»")
            end)

            layout:tag("nav", function(n)
                n:attr("class", "sidebar")
                add_sidebar(n, ctx.current_md_path, ctx.query,
                    ctx.current_tree, ctx.tree_active)
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
