--[[
{
  "module": "orlando.search",
  "role": "Site-wide search across markdown sources. Case-insensitive plain substring match — no stemming, no tokenization. Ranks results by a small additive score (filename/title/body weights). Re-scans the filesystem on every request, in keeping with the Orlando no-caching design.",
  "exports": {
    "search":         "query, tree? -> list of { md_path, url, count, score, preamble } sorted by score desc; tree scopes to files whose md_path starts with the prefix",
    "render":         "query, tree? -> full HTML results page (uses page.render_results_page for site chrome)",
    "handle":         "request_path (incl. query string) -> { status, body, content_type } — server-facing entry",
    "list_md_files": "() -> sorted list of every markdown source path (README.md + documentation/**/*.md); shared with orlando.random"
  },
  "ranking": "score = 10*hit_in_filename + 5*hit_in_title + 1*occurrence_count; ties broken alphabetically by md_path",
  "notes": ["always case-insensitive — query is folded to lowercase before scanning",
    "preamble is the doc's intro prose (post-H1, post-vibecode, pre-first-H2); HTML-escaped on render with light markdown stripping; query hits in the preamble are wrapped in <mark>",
    "tree filter: when tree is non-empty, only files whose md_path starts with the tree prefix are considered (prefix should end with '/'; empty or nil = whole site)"]
}
]]
local page = require("orlando.page")

local M = {}

local PREAMBLE_MAX = 320

-- Score weights for ranking.
local SCORE_FILENAME = 10
local SCORE_TITLE    = 5
local SCORE_BODY_HIT = 1

-- Extract the doc's H1 (first `# ...` line). Returns "" if none.
local function title_of(text)
    return text:match("^#%s+([^\n]*)") or text:match("\n#%s+([^\n]*)") or ""
end

-- Wrap query hits in <mark>. Input is already HTML-escaped.
local function highlight_query(escaped, query)
    if not query or query == "" then return escaped end
    local q_lower = query:lower()
    local lower   = escaped:lower()
    local out     = {}
    local i       = 1

    while true do
        local s, e = lower:find(q_lower, i, true)
        if not s then break end
        out[#out + 1] = escaped:sub(i, s - 1)
        out[#out + 1] = "<mark>" .. escaped:sub(s, e) .. "</mark>"
        i = e + 1
    end

    out[#out + 1] = escaped:sub(i)
    return table.concat(out)
end

-- Basename without the .md extension. Used for filename-match scoring.
local function basename_no_ext(path)
    local name = path:match("([^/]+)$") or path
    return (name:gsub("%.md$", ""))
end

local function list_md_files()
    local files = {}

    if io.open("README.md", "rb") then
        files[#files + 1] = "README.md"
    end

    local handle = io.popen('find documentation -type f -name "*.md" 2>/dev/null')

    if handle then
        for line in handle:lines() do
            files[#files + 1] = line
        end

        handle:close()
    end

    table.sort(files)
    return files
end

M.list_md_files = list_md_files

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function find_all(haystack_lower, needle_lower)
    local positions = {}
    local start = 1

    while true do
        local pos = haystack_lower:find(needle_lower, start, true)
        if not pos then break end
        positions[#positions + 1] = pos
        start = pos + #needle_lower
    end

    return positions
end

local function html_escape(s)
    return (s:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub('"', "&quot;"))
end

-- The doc's intro prose: everything after the H1, after any leading
-- vibecode fence, up to the first H2. Strips light markdown noise
-- (bold/italic/code marks, link syntax) and collapses whitespace so
-- the search result reads as plain text. Highlights the query if it
-- appears in the preamble.
local function preamble_of(text, query)
    -- Cut off at the first H2 if present.
    local h2_pos = text:find("\n## ", 1, true)
    if h2_pos then text = text:sub(1, h2_pos - 1) end

    -- Drop the H1 line (the very first line that starts with "# ").
    text = text:gsub("^#%s+[^\n]*\n", "")
    text = text:gsub("^%s+", "")

    -- Drop vibecode / json config fences wherever they appear in the
    -- preamble — a doc's intro can put them before OR after a subtitle,
    -- and either way they're config noise, not prose.
    text = text:gsub("~~~vibecode%s*\n.-\n~~~%s*\n?", "")
    text = text:gsub("```vibecode%s*\n.-\n```%s*\n?", "")
    text = text:gsub("~~~json%s*\n.-\n~~~%s*\n?", "")
    text = text:gsub("```json%s*\n.-\n```%s*\n?", "")
    text = text:gsub("^%s+", "")

    -- Light markdown / raw-HTML stripping for prose display.
    text = text:gsub("<[^>]+>", "")                  -- raw HTML tags
    text = text:gsub("\n%-%-%-+%s*\n", "\n\n")       -- horizontal rules
    text = text:gsub("%[([^%]]+)%]%([^)]+%)", "%1")  -- links → link text
    text = text:gsub("`([^`]+)`", "%1")              -- inline code
    text = text:gsub("%*%*([^%*]+)%*%*", "%1")       -- bold
    text = text:gsub("([^%w])_([^_]+)_([^%w])", "%1%2%3")  -- italic _x_
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    local truncated = false
    if #text > PREAMBLE_MAX then
        text = text:sub(1, PREAMBLE_MAX):gsub("%s+%S*$", "")
        truncated = true
    end

    local escaped = highlight_query(html_escape(text), query)
    if truncated then escaped = escaped .. "…" end
    return escaped
end

local function url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

local function parse_query(qs)
    local q, tree = "", ""

    for kv in (qs or ""):gmatch("[^&]+") do
        local k, v = kv:match("^([^=]+)=(.*)$")
        if k == "q"    and v then q    = url_decode(v) end
        if k == "tree" and v then tree = url_decode(v) end
    end

    return q, tree
end

--[[ {
    "in":  {"query": "string", "tree": "string? — prefix (e.g. 'documentation/foo/') to scope results to; empty/nil = whole site"},
    "out": "table — list of result rows, each { md_path, url, count, score, preamble }; sorted by score desc, ties broken alphabetically by md_path"
} ]]
function M.search(query, tree)
    if not query or query == "" then return {} end
    local q_lower = query:lower()
    local results = {}
    local scoped  = tree and tree ~= ""

    for _, path in ipairs(list_md_files()) do
        if not scoped or path:sub(1, #tree) == tree then
            local data = read_file(path)

            if data then
                local positions = find_all(data:lower(), q_lower)
                local in_filename =
                    basename_no_ext(path):lower():find(q_lower, 1, true) ~= nil
                local in_title =
                    title_of(data):lower():find(q_lower, 1, true) ~= nil

                if #positions > 0 or in_filename or in_title then
                    local score = #positions * SCORE_BODY_HIT
                    if in_filename then score = score + SCORE_FILENAME end
                    if in_title    then score = score + SCORE_TITLE    end

                    results[#results + 1] = {
                        md_path  = path,
                        url      = page.md_path_to_url(path),
                        title    = title_of(data),
                        count    = #positions,
                        score    = score,
                        preamble = preamble_of(data, query),
                    }
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.md_path < b.md_path
    end)

    return results
end

local function render_body(query, results, tree)
    local parts = { '<h1>Search</h1>' }
    local form_parts = {
        '<form class="search-form" action="/search" method="get">',
        '<input type="search" name="q" value="', html_escape(query),
        '" placeholder="Search docs" autofocus>',
    }

    if tree and tree ~= "" then
        form_parts[#form_parts + 1] =
            '<label class="search-form-tree">'
            .. '<input type="checkbox" name="tree" value="'
            .. html_escape(tree) .. '" checked> current tree</label>'
    end

    form_parts[#form_parts + 1] = '<button type="submit">Search</button></form>'
    parts[#parts + 1] = table.concat(form_parts)

    if query == "" then
        parts[#parts + 1] = '<p class="search-hint">Enter a query above. '
            .. 'Matching is case-insensitive substring.</p>'
        return table.concat(parts)
    end

    if #results == 0 then
        parts[#parts + 1] = '<p class="search-empty">No matches for <strong>'
            .. html_escape(query) .. '</strong>.</p>'
        return table.concat(parts)
    end

    parts[#parts + 1] = '<p class="search-summary">'
        .. tostring(#results) .. ' file'
        .. (#results == 1 and '' or 's')
        .. ' matched <strong>' .. html_escape(query) .. '</strong>.</p>'
    parts[#parts + 1] = '<ul class="search-results">'

    for _, r in ipairs(results) do
        local title = r.title
        if title == nil or title == "" then
            title = basename_no_ext(r.md_path)
        end

        local title_html = highlight_query(html_escape(title), query)
        local count_html = ' <span class="search-count">'
            .. tostring(r.count)
            .. (r.count == 1 and ' match' or ' matches')
            .. '</span>'

        parts[#parts + 1] = '<li class="search-result">'
            .. '<a class="search-title" href="' .. r.url .. '">'
            .. title_html .. '</a>'
            .. count_html
            .. '<div class="search-path">' .. html_escape(r.md_path) .. '</div>'

        if r.preamble and r.preamble ~= "" then
            parts[#parts + 1] = '<p class="search-preamble">'
                .. r.preamble .. '</p>'
        end

        parts[#parts + 1] = '</li>'
    end

    parts[#parts + 1] = '</ul>'
    return table.concat(parts)
end

--[[ {
    "in":  {"query": "string", "tree": "string? — prefix to scope results (empty/nil = whole site)"},
    "out": "string (full HTML page)"
} ]]
function M.render(query, tree)
    query = query or ""
    tree  = tree or ""
    local results = M.search(query, tree)
    local body    = render_body(query, results, tree)
    local title   = query == "" and "Search" or ("Search: " .. query)
    return page.render_results_page({
        title        = title,
        body_html    = body,
        query        = query,
        current_tree = tree,
        tree_active  = tree ~= "",
    })
end

--[[ {
    "in":  {"request_path": "string — the full path including ?q=... and optional &tree=..."},
    "out": "{status, body, content_type}"
} ]]
function M.handle(request_path)
    local qs      = (request_path or ""):match("%?(.*)$") or ""
    local q, tree = parse_query(qs)
    return {
        status       = "200 OK",
        body         = M.render(q, tree),
        content_type = "text/html; charset=utf-8",
    }
end

return M
