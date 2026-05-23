--[[
{
  "module": "orlando.search",
  "role": "Rudimentary site-wide search across markdown sources. Case-insensitive plain substring match — no stemming, no tokenization, no relevance scoring beyond match count. Re-scans the filesystem on every request, in keeping with the Orlando no-caching design.",
  "exports": {
    "search":         "query -> list of { md_path, url, count, snippets[] } sorted by count desc",
    "render":         "query -> full HTML results page (uses page.render_results_page for site chrome)",
    "handle":         "request_path (incl. query string) -> { status, body, content_type } — server-facing entry",
    "list_md_files": "() -> sorted list of every markdown source path (README.md + documentation/**/*.md); shared with orlando.random"
  },
  "notes": ["always case-insensitive — query is folded to lowercase before scanning",
    "snippet text is plain markdown source with whitespace collapsed; HTML-escaped on render"]
}
]]
local page = require("orlando.page")

local M = {}

local MAX_SNIPPETS_PER_FILE = 5
local SNIPPET_RADIUS        = 60

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

local function snippet_around(text, pos, qlen)
    local lo = math.max(1, pos - SNIPPET_RADIUS)
    local hi = math.min(#text, pos + qlen - 1 + SNIPPET_RADIUS)
    local before = text:sub(lo, pos - 1):gsub("%s+", " ")
    local hit    = text:sub(pos, pos + qlen - 1)
    local after  = text:sub(pos + qlen, hi):gsub("%s+", " ")
    local prefix = (lo > 1)      and "…" or ""
    local suffix = (hi < #text)  and "…" or ""
    return prefix .. html_escape(before)
        .. "<mark>" .. html_escape(hit) .. "</mark>"
        .. html_escape(after) .. suffix
end

local function url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

local function parse_query(qs)
    for kv in (qs or ""):gmatch("[^&]+") do
        local k, v = kv:match("^([^=]+)=(.*)$")

        if k == "q" and v then
            return url_decode(v)
        end
    end

    return ""
end

--[[ {
    "in":  {"query": "string"},
    "out": "table — list of result rows, each { md_path, url, count, snippets[] }; sorted by count desc, ties broken alphabetically by md_path"
} ]]
function M.search(query)
    if not query or query == "" then return {} end
    local q_lower = query:lower()
    local results = {}

    for _, path in ipairs(list_md_files()) do
        local data = read_file(path)

        if data then
            local positions = find_all(data:lower(), q_lower)

            if #positions > 0 then
                local snippets = {}

                for i = 1, math.min(#positions, MAX_SNIPPETS_PER_FILE) do
                    snippets[#snippets + 1] = snippet_around(data, positions[i], #query)
                end

                results[#results + 1] = {
                    md_path  = path,
                    url      = page.md_path_to_url(path),
                    count    = #positions,
                    snippets = snippets,
                }
            end
        end
    end

    table.sort(results, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.md_path < b.md_path
    end)

    return results
end

local function render_body(query, results)
    local parts = { '<h1>Search</h1>' }
    parts[#parts + 1] = '<form class="search-form" action="/search" method="get">'
        .. '<input type="search" name="q" value="' .. html_escape(query)
        .. '" placeholder="Search docs" autofocus>'
        .. '<button type="submit">Search</button>'
        .. '</form>'

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
    parts[#parts + 1] = '<ol class="search-results">'

    for _, r in ipairs(results) do
        parts[#parts + 1] = '<li class="search-result">'
            .. '<a class="search-path" href="' .. r.url .. '">'
            .. html_escape(r.md_path) .. '</a>'
            .. ' <span class="search-count">' .. tostring(r.count)
            .. ' match' .. (r.count == 1 and '' or 'es') .. '</span>'
        parts[#parts + 1] = '<ul class="search-snippets">'

        for _, snip in ipairs(r.snippets) do
            parts[#parts + 1] = '<li>' .. snip .. '</li>'
        end

        parts[#parts + 1] = '</ul></li>'
    end

    parts[#parts + 1] = '</ol>'
    return table.concat(parts)
end

--[[ {
    "in":  {"query": "string"},
    "out": "string (full HTML page)"
} ]]
function M.render(query)
    query = query or ""
    local results = M.search(query)
    local body    = render_body(query, results)
    local title   = query == "" and "Search" or ("Search: " .. query)
    return page.render_results_page({
        title     = title,
        body_html = body,
        query     = query,
    })
end

--[[ {
    "in":  {"request_path": "string — the full path including ?q=..."},
    "out": "{status, body, content_type}"
} ]]
function M.handle(request_path)
    local qs = (request_path or ""):match("%?(.*)$") or ""
    local q  = parse_query(qs)
    return {
        status       = "200 OK",
        body         = M.render(q),
        content_type = "text/html; charset=utf-8",
    }
end

return M
