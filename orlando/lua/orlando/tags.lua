--[[
{
  "module": "orlando.tags",
  "role": "Tag resolution — grep-based. Tags are defined inline in doc source as `<span class=\"tag\">NAME</span>` markers placed right after any heading (H1-H6). To resolve `tag:NAME`, walk documentation/ for files carrying that marker; the tag's target URL is the containing file's URL, appended with `#anchor` when the marker sits under a subsection heading. Called by orlando.route for /tag/<name> HTTP redirects and by orlando.page for tag:<name> markdown link resolution.",
  "exports": {
    "lookup": "tag_name -> url or nil",
    "list_all": "-> array of {name, url, sources[]} sorted by name (sources[] length > 1 means duplicate)"
  },
  "no_caching": "every call re-walks the tree per Orlando's no-caching design; performance is fine for the few-hundred-page scale"
}
]]
local M = {}

-- Directories to search for tag markers. Extendable if new roots ever
-- carry canonical docs.
local SEARCH_ROOTS = {"documentation/requirements", "documentation/ideas", "documentation"}

-- Marker pattern for a tag. Exact string form Orlando enforces:
--   <span class="tag">NAME</span>
-- Whitespace inside the span is not tolerated -- one canonical form so
-- authors and grep speak the same language.
local MARKER_LEFT  = '<span class="tag">'
local MARKER_RIGHT = '</span>'

-- Convert a heading text to a fragment id the same way lunamark's
-- default header-anchor generator does -- lowercase, non-alphanumerics
-- to hyphens, collapse repeats, trim edges.
local function slugify(text)
    text = text:gsub("`", ""):gsub("<[^>]+>", "")
    text = text:lower()
    text = text:gsub("[^%w]+", "-")
    text = text:gsub("^%-+", ""):gsub("%-+$", "")
    return text
end

-- Enumerate every markdown file under the given root, using find.
local function walk_md(root)
    local files = {}
    local cmd = "find " .. root .. " -type f -name '*.md' 2>/dev/null"
    local p = io.popen(cmd)
    if not p then return files end
    for line in p:lines() do
        files[#files + 1] = line
    end
    p:close()
    return files
end

-- Path -> URL, mirroring Orlando's usual rewrite:
--   documentation/foo/bar.md    -> /documentation/foo/bar
--   documentation/foo/index.md  -> /documentation/foo/
local function path_to_url(path)
    local url = "/" .. path
    url = url:gsub("/index%.md$", "/")
    url = url:gsub("%.md$", "")
    return url
end

-- Scan a file for tag markers. Returns an array of
-- {tag = "name", heading_slug = "slug or nil"} for every marker
-- found. heading_slug is nil when the marker sits under H1;
-- non-nil for H2 and deeper.
-- Markers inside code fences (``` or ~~~) are ignored so tag
-- examples in prose don't get picked up as real tags.
local function scan_file(path)
    local hits = {}
    local f = io.open(path, "r")
    if not f then return hits end

    local last_heading_slug = nil
    local last_heading_level = 0
    local in_fence = false
    local fence_marker = nil

    for line in f:lines() do
        local trimmed = line:match("^%s*(.*)")
        if not in_fence then
            local m = trimmed:match("^(```)") or trimmed:match("^(~~~)")
            if m then
                in_fence = true
                fence_marker = m
            end
        elseif fence_marker and trimmed:sub(1, #fence_marker) == fence_marker then
            in_fence = false
            fence_marker = nil
        end

        if not in_fence then
            local hashes, text = line:match("^(#+)%s+(.+)$")
            if hashes then
                last_heading_level = #hashes
                local title = text:gsub("%s+$", "")
                last_heading_slug = slugify(title)
            end

            -- Marker must be the first non-whitespace thing on the
            -- line. Inline uses inside prose (backticked examples,
            -- mentions in sentences) are ignored.
            local rest, indent_end = line:match("^(%s*)()")
            local marker_at = indent_end
            if line:sub(marker_at, marker_at + #MARKER_LEFT - 1) == MARKER_LEFT then
                local b = marker_at + #MARKER_LEFT - 1
                local c = line:find(MARKER_RIGHT, b + 1, true)
                if c then
                    local name = line:sub(b + 1, c - 1)
                    if name and name ~= "" then
                        hits[#hits + 1] = {
                            tag = name,
                            heading_slug = (last_heading_level >= 2) and last_heading_slug or nil,
                        }
                    end
                end
            end
        end
    end
    f:close()
    return hits
end

-- Aggregate all tags across every doc root.
local function collect()
    local by_tag = {}
    local seen_files = {}
    for _, root in ipairs(SEARCH_ROOTS) do
        for _, path in ipairs(walk_md(root)) do
            if not seen_files[path] then
                seen_files[path] = true
                local base_url = path_to_url(path)
                for _, hit in ipairs(scan_file(path)) do
                    local url = base_url
                    if hit.heading_slug then
                        url = url .. "#" .. hit.heading_slug
                    end
                    local entries = by_tag[hit.tag]
                    if not entries then
                        entries = {}
                        by_tag[hit.tag] = entries
                    end
                    entries[#entries + 1] = {url = url, path = path}
                end
            end
        end
    end
    return by_tag
end

-- lookup(tag) -> url or nil. Duplicates return the first source's URL;
-- duplicates are an audit error surfaced by list_all().
function M.lookup(tag)
    local entries = collect()[tag]
    if not entries or #entries == 0 then return nil end
    return entries[1].url
end

-- list_all() -> sorted array of {name, url, sources = [path, ...]}.
function M.list_all()
    local by_tag = collect()
    local names = {}
    for name in pairs(by_tag) do names[#names + 1] = name end
    table.sort(names)

    local out = {}
    for _, name in ipairs(names) do
        local entries = by_tag[name]
        local sources = {}
        for _, e in ipairs(entries) do sources[#sources + 1] = e.path end
        out[#out + 1] = {
            name    = name,
            url     = entries[1].url,
            sources = sources,
        }
    end
    return out
end

return M
